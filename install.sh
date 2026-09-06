#!/usr/bin/env bash
# Linux 与 macOS Zsh 跨平台一键配置脚本与更新管理器
# 兼容 Debian/Ubuntu/Fedora/Arch/openSUSE 及 macOS (Homebrew)，支持中英双语交互
set -Eeuo pipefail
export LC_ALL=C

# --- 防范使用 sudo 运行导致污染普通用户家目录权限（借鉴 zsh4humans 防护规范）---
EUID_VAL="$(command id -u 2>/dev/null || echo 1)"
if [[ "$EUID_VAL" == 0 ]]; then
  HOME_LS="$(command ls -ld -- "$HOME" 2>/dev/null || true)"
  HOME_OWNER="$(printf '%s\n' "$HOME_LS" | command awk 'NR==1 {print $3}')"
  if [[ "$HOME_OWNER" != root && -n "$HOME_OWNER" ]]; then
    printf '\033[1;33m[Notice / 提示]\033[0m: %s\n' \
      "检测到您正在使用 sudo 运行安装脚本！" >&2
    printf '请作为普通用户直接运行: \033[1;32mbash install.sh\033[0m （脚本在需要安装系统包时会自动请求 sudo 权限）。\n' >&2
    printf 'Please run directly as normal user without sudo. The script will request sudo when installing system packages.\n' >&2
    exit 1
  fi
fi

# --- 终端 TTY 保护与自动还原 Trap（借鉴 zsh4humans 终端健壮性规范）---
SAVED_TTY=""
if [[ -t 0 ]] && command -v stty >/dev/null 2>&1; then
  SAVED_TTY="$(command stty -g 2>/dev/null || true)"
fi

cleanup_terminal() {
  trap - INT TERM EXIT
  if [[ -n "$SAVED_TTY" ]] && command -v stty >/dev/null 2>&1; then
    command stty "$SAVED_TTY" 2>/dev/null || true
  fi
}
trap 'cleanup_terminal' INT TERM EXIT

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
DRY_RUN=0
PROFILE=basic
PROFILE_SET=0
WITH_VFOX=0
WITH_LAZYDOCKER=0
WITH_TMUX=0
P10K_STYLE=rainbow
P10K_STYLE_SET=0
CHECK_UPDATES=0
DO_UPDATE=0
LANG_CHOICE="${ZSH_PROJECT_LANG:-zh}"
LANG_SET=0
BACKUP=''
ROLLBACK=''
SKIPPED=()

msg() {
  if [[ "$LANG_CHOICE" == en ]]; then
    printf '%s' "$2"
  else
    printf '%s' "$1"
  fi
}

usage() {
  cat <<EOF
$(msg "用法：bash install.sh [选项]" "Usage: bash install.sh [options]")
  --dry-run             $(msg "只展示计划，不联网、不写文件、不调用权限提升" "Show execution plan only; no network, no file writes, no elevation")
  --profile basic|full  $(msg "基础安装（OMZ+主题+3核心插件）或完整安装（+全套CLI工具）" "Basic install (OMZ+theme+3 plugins) or full install (+all modern CLI tools)")
  --p10k-style STYLE    $(msg "P10k 主题风格：rainbow(经典彩虹,默认), lean(极简), classic(传统), wizard(向导), skip(跳过)" "P10k prompt style: rainbow(default), lean, classic, wizard, skip")
  --p10k-wizard         $(msg "安装完成后立即启动 p10k configure 官方交互式配置向导" "Launch p10k configure interactive wizard after installation")
  --with-vfox           $(msg "请求安装 vfox 多版本管理工具，不自动安装 SDK" "Install vfox version manager (does not install SDKs automatically)")
  --with-lazydocker     $(msg "请求安装 lazydocker，不配置 Docker 服务或权限" "Install lazydocker (does not configure Docker daemon or permissions)")
  --with-tmux           $(msg "请求安装并配置 tmux 终端复用器（含剪贴板互通与美化主题）" "Install and configure tmux terminal multiplexer (with clipboard & themes)")
  --check-updates       $(msg "检测已安装的 Zsh 插件与常用应用是否有新版本" "Check if installed plugins and CLI tools have new updates")
  --update              $(msg "交互式升级已安装的 Zsh/Tmux 插件、主题与包管理器工具" "Interactively update installed plugins, themes, and CLI tools")
  --lang zh|en          $(msg "界面语言（zh 为中文，en 为英文）" "UI language (zh for Chinese, en for English)")
  --rollback DIR        $(msg "恢复某次安装备份，只恢复配置文件" "Rollback configurations from a specific backup directory")
  --help|-h             $(msg "显示帮助" "Show help")
$(msg "实际安装必须在交互终端确认，不提供无人值守默认授权。" "Actual installation must be confirmed interactively.")
EOF
}

die() { printf '\033[1;31m%s: %s\033[0m\n' "$(msg '错误' 'Error')" "$*" >&2; exit 1; }
info() { printf '\033[1;34mℹ %s\033[0m\n' "$*"; }
success() { printf '\033[1;32m✓ %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m⚠ %s\033[0m\n' "$*"; }

# --- 单键免回车瞬时读取函数（借鉴 zsh4humans，按键即响应，免按回车）---
read_key() {
  local key=''
  if [[ -t 0 ]] && command -v stty >/dev/null 2>&1; then
    local old_stty
    old_stty="$(command stty -g 2>/dev/null || true)"
    command stty -icanon min 1 time 0 2>/dev/null || true
    while :; do
      local c
      c="$(command dd bs=1 count=1 2>/dev/null && echo x)"
      key="$key${c%x}"
      [[ -n "$key" ]] && break
    done
    [[ -n "$old_stty" ]] && command stty "$old_stty" 2>/dev/null || true
    if [[ "$key" == $'\n' || "$key" == $'\r' ]]; then
      echo ""
      return 0
    fi
    echo "$key"
  else
    read -r key || key=''
    echo "$key"
  fi
}

ask() {
  local prompt=$1
  printf '%s [y/N] ' "$prompt"
  local ans
  ans="$(read_key)"
  case "$ans" in
    y|Y) echo "y"; return 0 ;;
    q|Q) echo "q"; info "$(msg "用户已中止操作。" "Operation aborted by user.")"; exit 0 ;;
    *) echo "n"; return 1 ;;
  esac
}

# 跨平台计算 SHA-256 哈希值
calc_sha256() {
  local target=$1
  [[ -f "$target" ]] || return 1
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$target" 2>/dev/null | cut -d ' ' -f1
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$target" 2>/dev/null | cut -d ' ' -f1
  elif command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 "$target" 2>/dev/null | awk '{print $NF}'
  else
    die "$(msg "系统中未找到 sha256sum、shasum 或 openssl 计算工具" "No sha256sum, shasum, or openssl found in system")"
  fi
}

while (($#)); do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --profile) (($# >= 2)) || die "$(msg '--profile 缺少值' '--profile requires value')"; PROFILE=$2; PROFILE_SET=1; shift ;;
    --p10k-style)
      (($# >= 2)) || die "$(msg '--p10k-style 缺少参数 (rainbow|lean|classic|wizard|skip)' '--p10k-style requires value (rainbow|lean|classic|wizard|skip)')"
      P10K_STYLE="$2"; P10K_STYLE_SET=1; shift ;;
    --p10k-style=*) P10K_STYLE="${1#*=}"; P10K_STYLE_SET=1 ;;
    --p10k-wizard) P10K_STYLE="wizard"; P10K_STYLE_SET=1 ;;
    --p10k-rainbow) P10K_STYLE="rainbow"; P10K_STYLE_SET=1 ;;
    --p10k-lean) P10K_STYLE="lean"; P10K_STYLE_SET=1 ;;
    --p10k-classic) P10K_STYLE="classic"; P10K_STYLE_SET=1 ;;
    --p10k-skip) P10K_STYLE="skip"; P10K_STYLE_SET=1 ;;
    --with-vfox) WITH_VFOX=1 ;;
    --with-lazydocker) WITH_LAZYDOCKER=1 ;;
    --with-tmux) WITH_TMUX=1 ;;
    --check-updates) CHECK_UPDATES=1 ;;
    --update) DO_UPDATE=1 ;;
    --lang) (($# >= 2)) || die "$(msg '--lang 缺少语言代码 (zh|en)' '--lang requires value (zh|en)')"; LANG_CHOICE=$2; LANG_SET=1; shift ;;
    --lang=*) LANG_CHOICE="${1#*=}"; LANG_SET=1 ;;
    --rollback) (($# >= 2)) || die "$(msg '--rollback 缺少目录' '--rollback requires directory')"; ROLLBACK=$2; shift ;;
    --help|-h) usage; exit 0 ;;
    *) die "$(msg "未知参数：$1" "Unknown parameter: $1")" ;;
  esac
  shift
done

case "$P10K_STYLE" in
  rainbow|lean|classic|wizard|skip) ;;
  *) die "$(msg "无效的 P10k 样式：$P10K_STYLE (可选：rainbow, lean, classic, wizard, skip)" "Invalid P10k style: $P10K_STYLE (available: rainbow, lean, classic, wizard, skip)")" ;;
esac

# 交互式语言选择菜单（若未通过命令行显式指定 --lang，按键即响应）
if ((!DRY_RUN)) && [[ -t 0 ]] && ((!LANG_SET)) && [[ -z "$ROLLBACK" ]]; then
  printf '\n\033[1;36m🌐 Please select language / 请选择界面语言:\033[0m\n'
  printf '  1) 简体中文 (Chinese) [默认]\n'
  printf '  2) English\n'
  printf '  q) Quit / 退出\n'
  printf 'Enter choice / 请按键选择 [1/2/q]: '
  _l_key="$(read_key)"
  case "$_l_key" in
    2|e|E) echo "2"; LANG_CHOICE="en" ;;
    q|Q) echo "q"; exit 0 ;;
    *) echo "1"; LANG_CHOICE="zh" ;;
  esac
fi

# 1. 优先处理版本检测
if ((CHECK_UPDATES)); then
  if [[ -f "$SCRIPT_DIR/scripts/check_updates.sh" ]]; then
    bash "$SCRIPT_DIR/scripts/check_updates.sh" --lang "$LANG_CHOICE"
  else
    die "$(msg "缺少更新检测脚本：$SCRIPT_DIR/scripts/check_updates.sh" "Update check script missing: $SCRIPT_DIR/scripts/check_updates.sh")"
  fi
  exit 0
fi

# 2. 交互式更新流程
if ((DO_UPDATE)); then
  info "$(msg "正在检测已安装插件与工具的更新状态..." "Checking update status for installed plugins and tools...")"
  if [[ -f "$SCRIPT_DIR/scripts/check_updates.sh" ]]; then
    bash "$SCRIPT_DIR/scripts/check_updates.sh" --lang "$LANG_CHOICE"
  fi

  STATE_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}/zsh-project"
  AVAILABLE_FILE="$STATE_ROOT/available_updates"
  if [[ ! -s "$AVAILABLE_FILE" ]]; then
    success "$(msg "所有组件已是最新，无需更新！" "All components are already up to date!")"
    exit 0
  fi

  echo ""
  if ! ask "$(msg "是否确认现在更新以上有新版本的组件？" "Confirm updating the above components now?")"; then
    echo "$(msg "已取消更新。" "Update cancelled.")"
    exit 0
  fi

  info "$(msg "开始更新 Git 插件与主题..." "Updating Git plugins and themes...")"
  update_git_repo() {
    local name=$1 dir=$2
    [[ -d "$dir/.git" ]] || return 0
    if [[ -n $(git -C "$dir" status --porcelain 2>/dev/null) ]]; then
      warn "$(msg "$name 存在未提交的本地修改，跳过自动拉取以防止冲突。" "$name has uncommitted local changes; skipping pull to prevent conflicts.")"
      return 0
    fi
    info "$(msg "正在拉取 $name 最新代码..." "Pulling latest code for $name...")"
    if git -C "$dir" pull --ff-only --quiet 2>/dev/null; then
      success "$(msg "$name 更新完成" "$name updated successfully")"
    else
      warn "$(msg "$name 自动更新失败，请稍后手动检查 git status" "$name update failed; please check git status manually")"
    fi
  }

  update_git_repo "Oh My Zsh" "$HOME/.oh-my-zsh"
  [[ -d "$HOME/powerlevel10k" ]] && update_git_repo "Powerlevel10k" "$HOME/powerlevel10k"
  [[ -d "$HOME/.oh-my-zsh/custom/themes/powerlevel10k" ]] && update_git_repo "Powerlevel10k" "$HOME/.oh-my-zsh/custom/themes/powerlevel10k"

  CUSTOM_PLUGINS_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins"
  if [[ -d "$CUSTOM_PLUGINS_DIR" ]]; then
    for pdir in "$CUSTOM_PLUGINS_DIR"/*; do
      if [[ -d "$pdir/.git" ]]; then
        update_git_repo "$(basename "$pdir")" "$pdir"
      fi
    done
  fi

  # Tmux 插件升级
  if [[ -x "$HOME/.tmux/plugins/tpm/bin/update_plugins" ]]; then
    info "$(msg "正在更新 Tmux 插件..." "Updating Tmux plugins...")"
    bash "$HOME/.tmux/plugins/tpm/bin/update_plugins" all >/dev/null 2>&1 || true
    success "$(msg "Tmux 插件更新完成" "Tmux plugins updated successfully")"
  fi

  # FZF 官方仓库升级
  if [[ -d "$HOME/.fzf/.git" ]]; then
    update_git_repo "FZF" "$HOME/.fzf"
    if [[ -x "$HOME/.fzf/install" ]]; then
      bash "$HOME/.fzf/install" --bin --no-update-rc >/dev/null 2>&1 || true
      ln -sf "$HOME/.fzf/bin/fzf" "$HOME/.local/bin/fzf" 2>/dev/null || true
    fi
  fi

  # 应用工具升级
  OS_TYPE=$(uname -s)
  if [[ "$OS_TYPE" == Darwin ]] && command -v brew >/dev/null 2>&1; then
    info "$(msg "正在通过 Homebrew 升级命令行工具..." "Upgrading CLI tools via Homebrew...")"
    brew upgrade fzf fd bat eza zoxide yazi neovim fastfetch lazydocker vfox zsh git tmux 2>/dev/null || true
  elif [[ "$OS_TYPE" == Linux ]]; then
    if command -v apt-get >/dev/null 2>&1; then
      info "$(msg "提示：可在终端运行 sudo apt update && sudo apt --only-upgrade install <包名> 升级系统包。" "Tip: You can run sudo apt update && sudo apt --only-upgrade install <pkg> to upgrade system packages.")"
    elif command -v dnf >/dev/null 2>&1; then
      info "$(msg "提示：可在终端运行 sudo dnf upgrade <包名> 升级系统包。" "Tip: You can run sudo dnf upgrade <pkg> to upgrade system packages.")"
    fi
  fi

  # 清理更新状态缓存
  : > "$AVAILABLE_FILE"
  if [[ -f "$HOME/.zshrc" ]]; then
    zsh -n "$HOME/.zshrc" && success "$(msg "配置语法检查通过。" "Configuration syntax check passed.")"
  fi
  success "$(msg "更新流程执行完毕！请新开终端体验新版本。" "Update finished! Please open a new terminal session.")"
  exit 0
fi

# 3. 基础环境与配置目录校验
[[ "$PROFILE" == basic || "$PROFILE" == full ]] || die "$(msg '安装类型必须是 basic 或 full' 'Profile must be basic or full')"
OS=$(uname -s)
case "$OS" in
  Linux) ;;
  Darwin) ;;
  *) die "$(msg "暂不支持该操作系统：$OS。请在 Linux 或 macOS 终端中运行。" "Unsupported operating system: $OS. Please run in Linux or macOS.")" ;;
esac

ARCH=$(uname -m)
case "$ARCH" in
  x86_64|amd64) ARCH=x86_64 ;;
  aarch64|arm64) ARCH=arm64 ;;
  *) die "$(msg "暂不自动支持架构：$ARCH" "Unsupported architecture: $ARCH")" ;;
esac

[[ $EUID -ne 0 ]] || die "$(msg '请以普通用户运行；需要系统权限时安装器会单独调用 sudo' 'Please run as a regular user; sudo will be called when needed')"
[[ -z "${ZDOTDIR:-}" || "$ZDOTDIR" == "$HOME" ]] || die "$(msg '检测到自定义 ZDOTDIR，请先手动适配；安装器不会覆盖其它配置目录' 'Custom ZDOTDIR detected; installer will not overwrite other directories')"
[[ "$HOME" == /* && -d "$HOME" ]] || die "$(msg 'HOME 不是有效目录' 'HOME is not a valid directory')"

# 4. 配置回退恢复逻辑
restore() {
  local dir=$1 file expected actual
  [[ -d "$dir" && ! -L "$dir" && -f "$dir/manifest" ]] || die "$(msg '备份目录或清单不存在' 'Backup directory or manifest does not exist')"
  [[ $(head -n 1 "$dir/manifest") == "$HOME" ]] || die "$(msg '备份不属于当前 HOME' 'Backup does not belong to current HOME')"
  local managed_files=(.zshrc .zsh-project-options)
  [[ -f "$dir/.tmux.conf.state" ]] && managed_files+=(.tmux.conf)
  for file in "${managed_files[@]}"; do
    [[ -f "$dir/$file.sha256" && -f "$dir/$file.state" ]] || die "$(msg "备份不完整：$file" "Incomplete backup: $file")"
    [[ ! -L "$HOME/$file" ]] || die "$(msg "目标已变成符号链接：$file" "Target is a symlink: $file")"
    expected=$(cat "$dir/$file.sha256")
    actual=$(calc_sha256 "$HOME/$file") || actual=missing
    [[ "$actual" == "$expected" ]] || die "$(msg "$file 在安装后发生变化，请手动比较备份再恢复" "$file has changed after install; compare manually before restoring")"
    case $(cat "$dir/$file.state") in
      present) [[ -f "$dir/$file" ]] || die "$(msg "缺少原文件：$file" "Original file missing: $file")" ;;
      absent) ;;
      *) die "$(msg '备份状态无效' 'Invalid backup state')" ;;
    esac
  done
  printf '%s\n' "$(msg '将恢复受管配置文件。软件、插件、默认 Shell 不会自动回退。' 'Restoring managed configurations. Software, plugins, and default shell will not be reverted.')"
  ((DRY_RUN)) && return
  ask "$(msg '确认恢复以上配置？' 'Confirm restoring the above configuration?')" || return
  for file in "${managed_files[@]}"; do
    if [[ $(cat "$dir/$file.state") == present ]]; then
      command cp -p -- "$dir/$file" "$HOME/$file"
    else
      command rm -f -- "$HOME/$file"
    fi
  done
  command rm -f -- "$HOME/.zshrc.zwc" "$HOME/.zshenv.zwc" "$HOME/.zprofile.zwc" 2>/dev/null || true
  success "$(msg '配置已恢复。请新开终端验证。' 'Configuration restored. Please open a new terminal session to verify.')"
}

if [[ -n "$ROLLBACK" ]]; then
  ((DRY_RUN)) || [[ -t 0 ]] || die "$(msg '恢复需要交互终端' 'Rollback requires an interactive terminal')"
  restore "$ROLLBACK"
  exit 0
fi

# 5. 包管理器识别与适配
FAMILY=""
if [[ "$OS" == Darwin ]]; then
  # macOS Homebrew 识别
  if command -v brew >/dev/null 2>&1; then
    FAMILY=brew
  elif [[ -x "/opt/homebrew/bin/brew" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
    FAMILY=brew
  elif [[ -x "/usr/local/bin/brew" ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
    FAMILY=brew
  else
    warn "$(msg "在 macOS 上未检测到 Homebrew。" "Homebrew not detected on macOS.")"
    if ((DRY_RUN)); then
      FAMILY=brew
      info "$(msg "[预演模式] 将在实际安装时引导安装 Homebrew (https://brew.sh)" "[Dry Run] Homebrew installation will be guided during actual install")"
    elif [[ -t 0 ]] && ask "$(msg "是否现在自动安装 Homebrew？(国内用户可配置镜像)" "Install Homebrew automatically now?")"; then
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      if [[ -x "/opt/homebrew/bin/brew" ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
      elif [[ -x "/usr/local/bin/brew" ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
      fi
      FAMILY=brew
    else
      die "$(msg "macOS 环境建议通过 Homebrew 安装工具，请先访问 https://brew.sh 安装后重试。" "Homebrew is recommended for macOS. Please visit https://brew.sh and retry.")"
    fi
  fi
elif [[ "$OS" == Linux ]]; then
  if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    case "${ID:-}" in
      debian|ubuntu|linuxmint|kali|pop|raspbian) FAMILY=apt ;;
      fedora|rhel|centos|rocky|alma) FAMILY=dnf ;;
      arch|manjaro|endeavouros|artix) FAMILY=pacman ;;
      opensuse*|suse) FAMILY=zypper ;;
      *) die "$(msg "暂不自动支持发行版：${ID:-未知系统}；请使用手动教程" "Distribution not automatically supported: ${ID:-unknown}; refer to manual guide")" ;;
    esac
  elif ((DRY_RUN)); then
    FAMILY=apt
    info "$(msg "[预演模式] 未找到 /etc/os-release，默认模拟 apt 发行版" "[Dry Run] /etc/os-release not found; simulating apt distribution")"
  else
    die "$(msg '缺少 /etc/os-release' 'Missing /etc/os-release')"
  fi
fi

# 检查并自动自举项目模板（支持一行 curl/wget 管道远程直装，借鉴 zsh4humans 远程免克隆设计）
if [[ ! -r "$SCRIPT_DIR/templates/zshrc.zsh" ]]; then
  LOCAL_BOOTSTRAP_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/zsh-project-repo"
  info "$(msg "未在本地检测到完整模板，正在通过网络自动拉取最新项目资源至 $LOCAL_BOOTSTRAP_DIR..." "Templates not found locally; auto-bootstrapping repository into $LOCAL_BOOTSTRAP_DIR...")"
  command mkdir -p "$LOCAL_BOOTSTRAP_DIR"
  REPO_REMOTE="https://github.com/vicky-clair/xao_Rui_is-one-lick-configuration-script-for-ZSH.git"
  if command -v git >/dev/null 2>&1; then
    if [[ -d "$LOCAL_BOOTSTRAP_DIR/.git" ]]; then
      command git -C "$LOCAL_BOOTSTRAP_DIR" pull --quiet 2>/dev/null || true
    else
      command git clone --depth=1 "$REPO_REMOTE" "$LOCAL_BOOTSTRAP_DIR" --quiet 2>/dev/null || true
    fi
  fi
  # 若无 git 或 clone 失败，通过 curl/wget 提取必要模板
  if [[ ! -r "$LOCAL_BOOTSTRAP_DIR/templates/zshrc.zsh" ]]; then
    RAW_BASE="https://raw.githubusercontent.com/vicky-clair/xao_Rui_is-one-lick-configuration-script-for-ZSH/main"
    command mkdir -p "$LOCAL_BOOTSTRAP_DIR/templates" "$LOCAL_BOOTSTRAP_DIR/scripts"
    if command -v curl >/dev/null 2>&1; then
      command curl -fsSL "$RAW_BASE/templates/zshrc.zsh" -o "$LOCAL_BOOTSTRAP_DIR/templates/zshrc.zsh" 2>/dev/null || true
      command curl -fsSL "$RAW_BASE/templates/tmux.conf" -o "$LOCAL_BOOTSTRAP_DIR/templates/tmux.conf" 2>/dev/null || true
      command curl -fsSL "$RAW_BASE/scripts/check_updates.sh" -o "$LOCAL_BOOTSTRAP_DIR/scripts/check_updates.sh" 2>/dev/null || true
    elif command -v wget >/dev/null 2>&1; then
      command wget -qO "$LOCAL_BOOTSTRAP_DIR/templates/zshrc.zsh" "$RAW_BASE/templates/zshrc.zsh" 2>/dev/null || true
      command wget -qO "$LOCAL_BOOTSTRAP_DIR/templates/tmux.conf" "$RAW_BASE/templates/tmux.conf" 2>/dev/null || true
      command wget -qO "$LOCAL_BOOTSTRAP_DIR/scripts/check_updates.sh" "$RAW_BASE/scripts/check_updates.sh" 2>/dev/null || true
    fi
    command chmod +x "$LOCAL_BOOTSTRAP_DIR/scripts/check_updates.sh" 2>/dev/null || true
  fi
  if [[ -r "$LOCAL_BOOTSTRAP_DIR/templates/zshrc.zsh" ]]; then
    SCRIPT_DIR="$LOCAL_BOOTSTRAP_DIR"
    success "$(msg "项目资源自举成功" "Repository bootstrapped successfully")"
  else
    die "$(msg '缺少 templates/zshrc.zsh，且自动下载失败，请检查网络或克隆完整仓库' 'templates/zshrc.zsh missing and auto-download failed; please check network or clone repository')"
  fi
fi

target_files=(.zshrc .zsh-project-options)
if ((WITH_TMUX)); then
  [[ -r "$SCRIPT_DIR/templates/tmux.conf" ]] || die "$(msg '缺少 templates/tmux.conf，请下载完整项目' 'templates/tmux.conf missing; please download the full repository')"
  target_files+=(.tmux.conf)
fi
for file in "${target_files[@]}"; do
  [[ ! -L "$HOME/$file" && ! -d "$HOME/$file" ]] || die "$(msg "$file 是链接或目录，请手动处理" "$file is a symlink or directory; please resolve manually")"
  [[ ! -e "$HOME/$file" || -f "$HOME/$file" ]] || die "$(msg "$file 不是普通文件" "$file is not a regular file")"
done

if [[ -e "$HOME/.oh-my-zsh" && ! -r "$HOME/.oh-my-zsh/oh-my-zsh.sh" ]]; then
  die "$(msg '现有 OMZ 不完整；请按排查文档恢复，安装器不会覆盖 custom 或移动现有目录' 'Existing OMZ is incomplete; please recover per documentation') "
fi

# 6. 收集用户选项
if ((!DRY_RUN)); then
  [[ -t 0 ]] || die "$(msg '安装需要交互终端；查看计划请用 --dry-run' 'Installation requires interactive terminal; use --dry-run to view plan')"
  if ((!PROFILE_SET)); then
    if ask "$(msg '是否选择完整工具集？选 N 安装基础主题、补全、高亮和建议' 'Install full CLI toolchain? Select N for basic theme, completions, and suggestions')"; then PROFILE=full; fi
  fi
  if ((!P10K_STYLE_SET)); then
    printf '\n\033[1;36m🎨 %s:\033[0m\n' \
      "$(msg '请选择 Powerlevel10k 终端主题配置方式' 'Select Powerlevel10k Prompt Configuration')"
    printf '  1) %s\n' "$(msg '经典彩虹高颜值主题 (Rainbow) [默认推荐，开箱即用]' 'Classic Rainbow Theme [Recommended, ready-to-use]')"
    printf '  2) %s\n' "$(msg '现代极简纯净主题 (Lean) [简约清爽]' 'Lean Pure Theme [Minimalist & clean]')"
    printf '  3) %s\n' "$(msg '经典传统流线主题 (Classic) [传统箭头]' 'Classic Flow Theme [Traditional arrows]')"
    printf '  4) %s\n' "$(msg '安装完成后启动官方配置向导 (p10k configure) [自由定制]' 'Interactive Setup Wizard (p10k configure) [Full customization]')"
    printf '  5) %s\n' "$(msg '保持现有配置 / 暂不生成 ~/.p10k.zsh (Skip)' 'Keep existing ~/.p10k.zsh / Skip for now')"
    printf '%s [1/2/3/4/5]: ' "$(msg '请按键选择' 'Enter choice')"
    _p_key="$(read_key)"
    case "$_p_key" in
      2) echo "2"; P10K_STYLE="lean" ;;
      3) echo "3"; P10K_STYLE="classic" ;;
      4) echo "4"; P10K_STYLE="wizard" ;;
      5) echo "5"; P10K_STYLE="skip" ;;
      q|Q) echo "q"; info "$(msg "用户已中止操作。" "Operation aborted by user.")"; exit 0 ;;
      *) echo "1"; P10K_STYLE="rainbow" ;;
    esac
  fi
  ((WITH_VFOX)) || { if ask "$(msg '是否启用 vfox 版本管理（自动目录钩子默认关闭）？' 'Enable vfox version manager (auto directory hook disabled by default)?')"; then WITH_VFOX=1; fi; }
  ((WITH_LAZYDOCKER)) || { if ask "$(msg '是否安装 lazydocker 容器终端管理（不配置 Docker）？' 'Install lazydocker container UI (Docker daemon not configured)?')"; then WITH_LAZYDOCKER=1; fi; }
  ((WITH_TMUX)) || { if ask "$(msg '是否安装并配置 tmux 终端复用器（含全平台剪贴板互通与美化主题）？' 'Install and configure tmux terminal multiplexer (with clipboard & themes)?')"; then WITH_TMUX=1; fi; }
fi

printf '\n%s: %s; %s: %s; %s: %s; %s: %s\n' \
  "$(msg '系统' 'OS')" "${PRETTY_NAME:-$OS}" \
  "$(msg '架构' 'Arch')" "$ARCH" \
  "$(msg '包管理器' 'Package Manager')" "$FAMILY" \
  "$(msg '用户' 'User')" "$(id -un)"
printf '%s: %s; %s: %s; vfox: %s; lazydocker: %s; tmux: %s; %s: %s\n' \
  "$(msg '安装类型' 'Profile')" "$PROFILE" \
  "$(msg 'P10k主题' 'P10k Style')" "$P10K_STYLE" \
  "$WITH_VFOX" "$WITH_LAZYDOCKER" "$WITH_TMUX" \
  "$(msg '语言' 'Language')" "$LANG_CHOICE"
case "$P10K_STYLE" in
  rainbow) printf '%s\n' "$(msg '主题配置：经典彩虹流线双行主题（Rainbow，开箱即用）。' 'Prompt config: Classic rainbow theme (Rainbow, ready-to-use).')" ;;
  lean) printf '%s\n' "$(msg '主题配置：现代极简纯净主题（Lean，简约高效）。' 'Prompt config: Lean minimalist pure theme (Lean, clean & fast).')" ;;
  classic) printf '%s\n' "$(msg '主题配置：经典传统流线主题（Classic，传统箭头）。' 'Prompt config: Classic flow theme (Classic, traditional arrows).')" ;;
  wizard) printf '%s\n' "$(msg '主题配置：安装完成后自动唤起 p10k configure 官方配置向导。' 'Prompt config: Automatically launch p10k configure wizard after install.')" ;;
  skip) printf '%s\n' "$(msg '主题配置：保持原有设置，不覆盖 ~/.p10k.zsh。' 'Prompt config: Keep existing setup, do not touch ~/.p10k.zsh.')" ;;
esac
printf '%s\n' "$(msg '基础依赖：zsh git curl ca-certificates coreutils unzip tar；OMZ、Powerlevel10k、三个 Zsh 核心插件。' 'Base dependencies: zsh, git, curl, ca-certificates, coreutils, unzip, tar; OMZ, Powerlevel10k, 3 core plugins.')"
[[ "$PROFILE" == full ]] && printf '%s\n' "$(msg '完整工具：fzf fd bat eza zoxide yazi neovim fastfetch（仓库没有则跳过并记录）。' 'Full tools: fzf, fd, bat, eza, zoxide, yazi, neovim, fastfetch (skipped if unavailable in repository).')"
((WITH_TMUX)) && printf '%s\n' "$(msg 'Tmux 增强：安装 tmux、终端剪贴板工具、TPM 插件生态并部署 ~/.tmux.conf。' 'Tmux enhancement: install tmux, clipboard tools, TPM plugins, and ~/.tmux.conf.')"
printf '%s\n' "$(msg '备份并更新受管配置文件；保留 .zshenv、个人主题、custom 和历史文件。' 'Backup and update managed configurations; preserving .zshenv, custom themes and history.')"
printf '%s\n' "$(msg '默认 Shell 将在配置安装成功后单独询问。' 'Default login shell will be prompted separately after configuration.')"

if ((DRY_RUN)); then
  printf '\n%s\n' "$(msg '预演结束。实际可用包将在确认安装后通过本机仓库检测。' 'Dry run finished. Available packages will be checked via local repositories upon confirmation.')"
  exit 0
fi

echo ""
ask "$(msg '确认按以上计划安装并替换配置？' 'Confirm installation and replace configuration according to plan?')" || exit 0

# 权限校验：Linux 依赖包管理器需要 sudo，macOS Homebrew 必须以普通用户运行
if [[ "$FAMILY" != brew ]]; then
  command -v sudo >/dev/null || die "$(msg '缺少 sudo，请先由管理员安装依赖' 'Missing sudo; please ask administrator to install dependencies')"
  sudo -v
fi

STATE_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}/zsh-project"
mkdir -p "$STATE_ROOT"
BACKUP=$(mktemp -d "$STATE_ROOT/install-XXXXXXXX")
chmod 700 "$BACKUP"
exec > >(tee -a "$BACKUP/install.log") 2>&1
trap 'printf "安装未完成。日志与原配置：%s\n系统软件安装不会自动回退。\n" "$BACKUP" >&2' ERR

printf '%s\n' "$HOME" > "$BACKUP/manifest"
backup_files=(.zshrc .zsh-project-options)
((WITH_TMUX)) && backup_files+=(.tmux.conf)
for file in "${backup_files[@]}"; do
  if [[ -f "$HOME/$file" ]]; then
    cp -p -- "$HOME/$file" "$BACKUP/$file"
    printf 'present\n' > "$BACKUP/$file.state"
  else
    printf 'absent\n' > "$BACKUP/$file.state"
  fi
done

# 7. 安装基础系统软件
info "$(msg "正在安装基础核心依赖..." "Installing core base dependencies...")"
case "$FAMILY" in
  brew)
    brew install zsh git curl coreutils unzip tar
    ;;
  apt)
    sudo apt-get update
    sudo apt-get install -y zsh git curl ca-certificates coreutils unzip tar
    ;;
  dnf)
    sudo dnf install -y zsh git curl ca-certificates coreutils unzip tar
    ;;
  pacman)
    sudo pacman -Syu --needed --noconfirm zsh git curl ca-certificates coreutils unzip tar
    ;;
  zypper)
    sudo zypper install -y zsh git curl ca-certificates coreutils unzip tar
    ;;
esac

# 辅助函数：从已跳过列表中移除（用于回退安装成功后剔除）
remove_skipped() {
  local target=$1
  local updated=()
  for item in "${SKIPPED[@]}"; do
    [[ "$item" != "$target" ]] && updated+=("$item")
  done
  SKIPPED=("${updated[@]}")
}

mkdir -p "$HOME/.local/bin"
export PATH="$HOME/.local/bin:$PATH"

# 可选软件包安装函数
optional_package() {
  local cmd=$1 pkg=$2
  command -v "$cmd" >/dev/null 2>&1 && return 0
  case "$FAMILY" in
    brew)
      if brew info "$pkg" >/dev/null 2>&1; then
        brew install "$pkg" && return 0
      fi
      ;;
    apt)
      if apt-cache show "$pkg" >/dev/null 2>&1 || apt-get install -s -qq "$pkg" >/dev/null 2>&1; then
        sudo apt-get install -y "$pkg" && return 0
      fi
      ;;
    dnf)
      if dnf -q info --available "$pkg" >/dev/null 2>&1; then
        sudo dnf install -y "$pkg" && return 0
      fi
      ;;
    pacman)
      if pacman -Si "$pkg" >/dev/null 2>&1; then
        sudo pacman -S --needed --noconfirm "$pkg" && return 0
      fi
      ;;
    zypper)
      if zypper info "$pkg" >/dev/null 2>&1; then
        sudo zypper install -y "$pkg" && return 0
      fi
      ;;
  esac
  SKIPPED+=("$pkg")
  warn "$(msg "可选包未在仓库中找到：$pkg，已跳过安装。" "Optional package not found in repository: $pkg, skipped.")"
}

# 8. 安装完整工具集
if [[ "$PROFILE" == full ]]; then
  info "$(msg "正在安装完整工具集..." "Installing full modern CLI toolchain...")"
  fd_pkg=fd
  [[ "$FAMILY" == apt || "$FAMILY" == dnf || "$FAMILY" == zypper ]] && fd_pkg=fd-find

  optional_package fzf fzf
  optional_package fd "$fd_pkg"
  optional_package bat bat
  for pkg in eza zoxide yazi fastfetch; do
    optional_package "$pkg" "$pkg"
  done
  optional_package nvim neovim

  # 架构匹配定义
  ARCH_UNAME=$(uname -m 2>/dev/null || echo "$ARCH")
  EZA_ARCH=""
  FF_ARCH=""
  YAZI_ARCH=""
  case "$ARCH_UNAME" in
    x86_64|amd64)
      EZA_ARCH="x86_64"
      FF_ARCH="amd64"
      YAZI_ARCH="x86_64"
      ;;
    aarch64|arm64)
      EZA_ARCH="aarch64"
      FF_ARCH="aarch64"
      YAZI_ARCH="aarch64"
      ;;
  esac

  # --- FZF 现代版本保障（针对 Debian 12 等自带旧版 0.38 不支持 fzf --zsh）---
  if ! command -v fzf >/dev/null 2>&1 || ! fzf --zsh >/dev/null 2>&1; then
    info "$(msg "系统 FZF 缺失或版本过旧（不支持 --zsh 快捷键），正在通过官方仓库升级至 ~/.local/bin..." "FZF missing or outdated (no --zsh support); installing modern version to ~/.local/bin...")"
    if [[ ! -d "$HOME/.fzf" ]]; then
      git clone --depth 1 https://github.com/junegunn/fzf.git "$HOME/.fzf" >/dev/null 2>&1 || true
    else
      git -C "$HOME/.fzf" pull --quiet 2>/dev/null || true
    fi
    if [[ -x "$HOME/.fzf/install" ]]; then
      bash "$HOME/.fzf/install" --bin --no-update-rc >/dev/null 2>&1 || true
      if [[ -x "$HOME/.fzf/bin/fzf" ]]; then
        mkdir -p "$HOME/.local/bin"
        ln -sf "$HOME/.fzf/bin/fzf" "$HOME/.local/bin/fzf"
        success "$(msg "FZF 安装/升级成功（最新版本已链接至 ~/.local/bin/fzf）" "FZF installed/updated successfully (~/.local/bin/fzf)")"
        remove_skipped fzf
      fi
    fi
  fi

  # --- EZA 官方预编译二进制自动回退（Debian 12 等发行版仓库无此包）---
  if ! command -v eza >/dev/null 2>&1 && [[ -n "$EZA_ARCH" ]]; then
    info "$(msg "系统仓库无 eza，正在从 GitHub Release 下载官方预编译二进制至 ~/.local/bin..." "eza not in repo; downloading official binary...")"
    eza_stage=$(mktemp -d "$HOME/.eza-tmp-XXXXXX")
    eza_url="https://github.com/eza-community/eza/releases/latest/download/eza_${EZA_ARCH}-unknown-linux-gnu.tar.gz"
    if curl -fsSL --connect-timeout 10 -m 60 "$eza_url" -o "$eza_stage/eza.tar.gz" 2>/dev/null; then
      if tar -xzf "$eza_stage/eza.tar.gz" -C "$eza_stage" 2>/dev/null; then
        eza_bin=$(find "$eza_stage" -type f -name eza -perm -111 2>/dev/null | head -n 1)
        if [[ -n "$eza_bin" && -x "$eza_bin" ]]; then
          mkdir -p "$HOME/.local/bin"
          install -m 755 "$eza_bin" "$HOME/.local/bin/eza"
          success "$(msg "eza 安装成功（位于 ~/.local/bin/eza）" "eza installed successfully (in ~/.local/bin/eza)")"
          remove_skipped eza
        fi
      fi
    fi
    rm -rf "$eza_stage"
  fi

  # --- FASTFETCH 官方发布版自动回退（Debian 12 等仓库无此包）---
  if ! command -v fastfetch >/dev/null 2>&1 && [[ -n "$FF_ARCH" ]]; then
    info "$(msg "系统仓库无 fastfetch，正在从 GitHub Release 下载官方发布版..." "fastfetch not in repo; downloading official release...")"
    ff_stage=$(mktemp -d "$HOME/.ff-tmp-XXXXXX")
    if [[ "$FAMILY" == apt ]]; then
      ff_url="https://github.com/fastfetch-cli/fastfetch/releases/latest/download/fastfetch-linux-${FF_ARCH}.deb"
      if curl -fsSL --connect-timeout 10 -m 60 "$ff_url" -o "$ff_stage/fastfetch.deb" 2>/dev/null; then
        if sudo dpkg -i "$ff_stage/fastfetch.deb" >/dev/null 2>&1 || (sudo apt-get install -fy >/dev/null 2>&1 && sudo dpkg -i "$ff_stage/fastfetch.deb" >/dev/null 2>&1); then
          success "$(msg "fastfetch 安装成功 (deb 软件包)" "fastfetch installed successfully via deb")"
          remove_skipped fastfetch
        fi
      fi
    fi
    if ! command -v fastfetch >/dev/null 2>&1; then
      ff_tar_url="https://github.com/fastfetch-cli/fastfetch/releases/latest/download/fastfetch-linux-${FF_ARCH}.tar.gz"
      if curl -fsSL --connect-timeout 10 -m 60 "$ff_tar_url" -o "$ff_stage/fastfetch.tar.gz" 2>/dev/null; then
        tar -xzf "$ff_stage/fastfetch.tar.gz" -C "$ff_stage" 2>/dev/null || true
        ff_bin=$(find "$ff_stage" -type f -name fastfetch -perm -111 2>/dev/null | head -n 1)
        if [[ -n "$ff_bin" && -x "$ff_bin" ]]; then
          mkdir -p "$HOME/.local/bin"
          install -m 755 "$ff_bin" "$HOME/.local/bin/fastfetch"
          success "$(msg "fastfetch 安装成功（位于 ~/.local/bin/fastfetch）" "fastfetch installed successfully (in ~/.local/bin/fastfetch)")"
          remove_skipped fastfetch
        fi
      fi
    fi
    rm -rf "$ff_stage"
  fi

  # --- YAZI 官方静态发布包自动回退（使用 musl 静态编译版，彻底避免 glibc 2.39 缺失问题）---
  if (! command -v yazi >/dev/null 2>&1 || ! yazi --version >/dev/null 2>&1) && [[ -n "$YAZI_ARCH" ]]; then
    info "$(msg "正在从 GitHub Release 下载官方静态编译发布版 (musl) 至 ~/.local/bin..." "Downloading official static musl release to ~/.local/bin...")"
    yazi_stage=$(mktemp -d "$HOME/.yazi-tmp-XXXXXX")
    yazi_url="https://github.com/sxyazi/yazi/releases/latest/download/yazi-${YAZI_ARCH}-unknown-linux-musl.zip"
    if curl -fsSL --connect-timeout 10 -m 60 "$yazi_url" -o "$yazi_stage/yazi.zip" 2>/dev/null; then
      if command -v unzip >/dev/null 2>&1; then
        unzip -q "$yazi_stage/yazi.zip" -d "$yazi_stage" 2>/dev/null || true
      elif command -v python3 >/dev/null 2>&1; then
        python3 -c "import zipfile; zipfile.ZipFile('$yazi_stage/yazi.zip').extractall('$yazi_stage')" 2>/dev/null || true
      fi
      yazi_bin=$(find "$yazi_stage" -type f -name yazi -perm -111 2>/dev/null | head -n 1)
      if [[ -n "$yazi_bin" && -x "$yazi_bin" ]]; then
        mkdir -p "$HOME/.local/bin"
        install -m 755 "$yazi_bin" "$HOME/.local/bin/yazi"
        success "$(msg "yazi 静态版安装成功（位于 ~/.local/bin/yazi）" "yazi static musl installed successfully (in ~/.local/bin/yazi)")"
        remove_skipped yazi
      fi
    fi
    rm -rf "$yazi_stage"
  fi
fi

# vfox 可选版本管理安装（优先包管理器，缺失时尝试官方用户态脚本）
if ((WITH_VFOX)) && ! command -v vfox >/dev/null 2>&1; then
  optional_package vfox vfox
  if ! command -v vfox >/dev/null 2>&1; then
    info "$(msg "系统仓库无 vfox，正在尝试通过官方脚本安装至用户目录..." "vfox not in repo; attempting official install script...")"
    vfox_stage=$(mktemp -d "$HOME/.vfox-tmp-XXXXXX")
    if curl -fsSL "https://raw.githubusercontent.com/version-fox/vfox/main/install.sh" -o "$vfox_stage/install.sh" 2>/dev/null; then
      if bash "$vfox_stage/install.sh" --user >/dev/null 2>&1; then
        success "$(msg "vfox 官方脚本安装成功" "vfox installed successfully via official script")"
        remove_skipped vfox
      fi
    fi
    rm -rf "$vfox_stage"
  fi
fi

# lazydocker 容器管理面板安装（优先包管理器，缺失时尝试官方独立预编译二进制）
if ((WITH_LAZYDOCKER)) && ! command -v lazydocker >/dev/null 2>&1; then
  optional_package lazydocker lazydocker
  if ! command -v lazydocker >/dev/null 2>&1; then
    info "$(msg "系统仓库无 lazydocker，正在尝试下载官方独立二进制至 ~/.local/bin..." "lazydocker not in repo; downloading official binary...")"
    lzd_arch="x86_64"
    [[ "$ARCH" == arm64 || "$ARCH" == aarch64 ]] && lzd_arch="arm64"
    lzd_stage=$(mktemp -d "$HOME/.lzd-tmp-XXXXXX")
    lzd_url="https://github.com/jesseduffield/lazydocker/releases/latest/download/lazydocker_Linux_${lzd_arch}.tar.gz"
    if curl -fsSL "$lzd_url" -o "$lzd_stage/lzd.tar.gz" 2>/dev/null; then
      if tar -xzf "$lzd_stage/lzd.tar.gz" -C "$lzd_stage" lazydocker 2>/dev/null && [[ -x "$lzd_stage/lazydocker" ]]; then
        mkdir -p "$HOME/.local/bin"
        install -m 755 "$lzd_stage/lazydocker" "$HOME/.local/bin/lazydocker"
        success "$(msg "lazydocker 安装成功（位于 ~/.local/bin/lazydocker）" "lazydocker installed successfully (in ~/.local/bin/lazydocker)")"
        remove_skipped lazydocker
      fi
    fi
    rm -rf "$lzd_stage"
  fi
fi

if ((WITH_TMUX)); then
  info "$(msg "正在安装 tmux 及终端剪贴板依赖..." "Installing tmux and clipboard dependencies...")"
  optional_package tmux tmux
  if [[ "$FAMILY" == apt || "$FAMILY" == dnf || "$FAMILY" == pacman || "$FAMILY" == zypper ]]; then
    optional_package xclip xclip
    optional_package wl-copy wl-clipboard
    [[ "$FAMILY" == apt ]] && optional_package "" ncurses-term
  fi
fi

# 命令名软链接映射（兼容各发行版的 fdfind / batcat）
mkdir -p "$HOME/.local/bin"
if ! command -v fd >/dev/null 2>&1 && command -v fdfind >/dev/null 2>&1; then
  [[ ! -e "$HOME/.local/bin/fd" ]] && ln -s "$(command -v fdfind)" "$HOME/.local/bin/fd" 2>/dev/null || true
fi
if ! command -v bat >/dev/null 2>&1 && command -v batcat >/dev/null 2>&1; then
  [[ ! -e "$HOME/.local/bin/bat" ]] && ln -s "$(command -v batcat)" "$HOME/.local/bin/bat" 2>/dev/null || true
fi

# 9. 安装 Oh My Zsh、主题及插件
clone_missing() {
  local url=$1 dest=$2 entry=$3 temp
  if [[ -e "$dest" || -L "$dest" ]]; then
    [[ -r "$dest/$entry" ]] || die "$(msg "已有目录不完整：$dest；保留原目录，停止安装" "Existing directory incomplete: $dest; stopping")"
    info "$(msg "保留已有组件：$dest" "Preserving existing component: $dest")"
    return
  fi
  mkdir -p "$(dirname "$dest")"
  temp=$(mktemp -d "$(dirname "$dest")/.zsh-download-XXXXXXXX")
  git clone --depth=1 "$url" "$temp/repo"
  [[ -r "$temp/repo/$entry" ]] || die "$(msg "下载组件缺少入口：$entry" "Component missing entrypoint: $entry")"
  mv "$temp/repo" "$dest"
  rmdir "$temp" 2>/dev/null || rm -rf "$temp"
  success "$(msg "成功克隆：$dest" "Cloned successfully: $dest")"
}

info "$(msg "正在克隆 Oh My Zsh 与主题插件..." "Cloning Oh My Zsh, themes, and plugins...")"
clone_missing https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh" oh-my-zsh.sh
clone_missing https://github.com/romkatv/powerlevel10k.git "$HOME/powerlevel10k" powerlevel10k.zsh-theme

for plugin in zsh-autosuggestions zsh-completions zsh-syntax-highlighting; do
  entry="$plugin.zsh"
  [[ "$plugin" == zsh-completions ]] && entry=README.md
  clone_missing "https://github.com/zsh-users/$plugin.git" "$HOME/.oh-my-zsh/custom/plugins/$plugin" "$entry"
done

# 部署 Powerlevel10k 主题配置
case "$P10K_STYLE" in
  rainbow)
    if [[ -f "$HOME/powerlevel10k/config/p10k-rainbow.zsh" ]]; then
      cp "$HOME/powerlevel10k/config/p10k-rainbow.zsh" "$HOME/.p10k.zsh"
      success "$(msg "已生成 Powerlevel10k 经典彩虹主题配置 (~/.p10k.zsh)" "Generated Powerlevel10k rainbow theme config (~/.p10k.zsh)")"
    fi
    ;;
  lean)
    if [[ -f "$HOME/powerlevel10k/config/p10k-lean.zsh" ]]; then
      cp "$HOME/powerlevel10k/config/p10k-lean.zsh" "$HOME/.p10k.zsh"
      success "$(msg "已生成 Powerlevel10k 现代极简主题配置 (~/.p10k.zsh)" "Generated Powerlevel10k lean theme config (~/.p10k.zsh)")"
    fi
    ;;
  classic)
    if [[ -f "$HOME/powerlevel10k/config/p10k-classic.zsh" ]]; then
      cp "$HOME/powerlevel10k/config/p10k-classic.zsh" "$HOME/.p10k.zsh"
      success "$(msg "已生成 Powerlevel10k 经典传统主题配置 (~/.p10k.zsh)" "Generated Powerlevel10k classic theme config (~/.p10k.zsh)")"
    fi
    ;;
  wizard)
    # 用户选择向导配置：若已有配置备份后移除，确保安装后向导能干净启动
    if [[ -f "$HOME/.p10k.zsh" ]]; then
      cp "$HOME/.p10k.zsh" "$BACKUP/old.p10k.zsh" 2>/dev/null || true
      rm -f "$HOME/.p10k.zsh"
    fi
    info "$(msg "已就绪：将在安装结束时自动唤起 p10k configure 官方配置向导" "Ready: will launch p10k configure wizard automatically after install")"
    ;;
  skip)
    info "$(msg "保持当前主题配置，不覆盖 ~/.p10k.zsh" "Keeping existing prompt config, ~/.p10k.zsh untouched")"
    ;;
esac

if ((WITH_TMUX)); then
  info "$(msg "正在配置 Tmux 与 TPM 插件管理器..." "Configuring Tmux and TPM plugin manager...")"
  clone_missing https://github.com/tmux-plugins/tpm.git "$HOME/.tmux/plugins/tpm" tpm
  if [[ -r "$SCRIPT_DIR/templates/tmux.conf" ]]; then
    cp "$SCRIPT_DIR/templates/tmux.conf" "$BACKUP/new.tmux.conf"
    install -m 600 "$BACKUP/new.tmux.conf" "$HOME/.tmux.conf"
    success "$(msg "已部署 ~/.tmux.conf" "Deployed ~/.tmux.conf successfully")"
  fi
  if [[ -x "$HOME/.tmux/plugins/tpm/bin/install_plugins" ]]; then
    info "$(msg "正在自动下载并安装 Tmux 插件..." "Installing Tmux plugins automatically...")"
    bash "$HOME/.tmux/plugins/tpm/bin/install_plugins" >/dev/null 2>&1 || true
    success "$(msg "Tmux 插件初始化完成" "Tmux plugins initialized successfully")"
  fi
fi

# 复制更新检测辅助脚本到统一状态或脚本目录
mkdir -p "$STATE_ROOT/scripts"
if [[ -f "$SCRIPT_DIR/scripts/check_updates.sh" ]]; then
  cp -p "$SCRIPT_DIR/scripts/check_updates.sh" "$STATE_ROOT/scripts/check_updates.sh"
  chmod 755 "$STATE_ROOT/scripts/check_updates.sh"
fi

# 10. 部署配置文件
cp "$SCRIPT_DIR/templates/zshrc.zsh" "$BACKUP/new.zshrc"

cat <<EOF > "$BACKUP/new.options"
# 安装器生成；1 为启用，0 为关闭。
ZSH_PROJECT_FULL=$([[ "$PROFILE" == full ]] && echo 1 || echo 0)
ZSH_PROJECT_VFOX=$WITH_VFOX
ZSH_PROJECT_LAZYDOCKER=$WITH_LAZYDOCKER
ZSH_PROJECT_TMUX=$WITH_TMUX
ZSH_PROJECT_DIR="$SCRIPT_DIR"
ZSH_PROJECT_LANG="$LANG_CHOICE"
ZSH_PROJECT_AUTO_CHECK_UPDATE=1
ZSH_PROJECT_CHECK_INTERVAL_DAYS=7
EOF

zsh -n "$BACKUP/new.zshrc"
zsh -n "$BACKUP/new.options"

install -m 600 "$BACKUP/new.options" "$HOME/.zsh-project-options"
install -m 600 "$BACKUP/new.zshrc" "$HOME/.zshrc"

# 清理旧的编译字节码（若存在，借鉴 zsh4humans 规范），防止 Zsh 继续读取失效旧缓存
command rm -f -- "$HOME/.zshrc.zwc" "$HOME/.zshenv.zwc" "$HOME/.zprofile.zwc" 2>/dev/null || true

deployed_files=(.zshrc .zsh-project-options)
((WITH_TMUX)) && deployed_files+=(.tmux.conf)
for file in "${deployed_files[@]}"; do
  [[ -f "$HOME/$file" ]] && calc_sha256 "$HOME/$file" > "$BACKUP/$file.sha256"
done

# 首次执行一次静默后台版本检测（生成初始缓存）
if [[ -f "$STATE_ROOT/scripts/check_updates.sh" ]]; then
  bash "$STATE_ROOT/scripts/check_updates.sh" -q --lang "$LANG_CHOICE" >/dev/null 2>&1 || true
fi

printf '\n\033[1;32m🎉 %s\033[0m\n' "$(msg 'Zsh 配置安装完成！' 'Zsh configuration installed successfully!')"
printf '%s: %s\n' "$(msg '备份目录与安装日志' 'Backup directory and install log')" "$BACKUP"
printf '%s: %s\n' "$(msg '跳过的未安装包' 'Skipped packages')" "${SKIPPED[*]:-none}"
if ((${#SKIPPED[@]} > 0)); then
  info "$(msg "提示：若因网络原因某些独立二进制或包未能自动下载，可参考文档手动安装或重试安装器。" "Tip: If some standalone binaries or packages failed to download due to network, please refer to the documentation or retry.")"
fi
case "$P10K_STYLE" in
  wizard)
    info "$(msg "提示：您已选择向导配置，稍后将自动拉起 p10k configure 进行个性化设置。" "Tip: You selected wizard mode; p10k configure will launch shortly.")"
    ;;
  skip)
    info "$(msg "提示：已保留原有主题配置。" "Tip: Preserved original prompt configuration.")"
    ;;
  *)
    info "$(msg "提示：已为您部署所选主题；如需个性化调整，可随时在终端运行 p10k configure。" "Tip: Default prompt configured. Run p10k configure anytime to customize.")"
    ;;
esac

# 11. 切换默认 Shell（Linux 与 macOS 分别适配）
if ask "$(msg '是否将 Zsh 设为当前用户的默认登录 Shell？' 'Set Zsh as default login shell for current user?') "; then
  zsh_bin=$(command -v zsh)
  current_shell="${SHELL:-}"

  if [[ "$current_shell" == *zsh ]]; then
    info "$(msg "当前默认 Shell 已经是 Zsh ($current_shell)，无需修改。" "Current default shell is already Zsh ($current_shell); no change needed.")"
  else
    if ! grep -Fxq "$zsh_bin" /etc/shells; then
      warn "$(msg "路径 $zsh_bin 不在 /etc/shells 列表中，正在请求权限添加..." "$zsh_bin not in /etc/shells, requesting permission to add...")"
      if command -v sudo >/dev/null 2>&1; then
        echo "$zsh_bin" | sudo tee -a /etc/shells >/dev/null
      fi
    fi

    if grep -Fxq "$zsh_bin" /etc/shells && command -v chsh >/dev/null 2>&1; then
      info "$(msg "正在调用 chsh（若提示 Password 请输入当前用户密码）..." "Calling chsh (please enter user password if prompted)...")"
      chsh -s "$zsh_bin" || warn "$(msg "默认 Shell 修改失败，请稍后手动运行: chsh -s $zsh_bin" "chsh failed; please run manually: chsh -s $zsh_bin")"
    else
      warn "$(msg "未修改默认 Shell：缺少 chsh 或权限不足。" "Default shell not modified: missing chsh or insufficient permissions.")"
    fi
  fi
fi

printf '\n%s:\n  bash %s/install.sh --rollback %q\n' \
  "$(msg '若需要回退配置，请运行' 'To rollback configuration, run')" "$SCRIPT_DIR" "$BACKUP"

# 12. 立即启动新 Shell 会话自举（借鉴 zsh4humans 体验）
if [[ "$P10K_STYLE" == wizard ]] && [[ -t 0 ]] && command -v zsh >/dev/null 2>&1; then
  echo ""
  printf '\n\033[1;36m%s\033[0m\n' "$(msg '🛠️ 正在为您启动 Powerlevel10k 官方配置向导...' '🛠️ Launching Powerlevel10k configuration wizard...')"
  info "$(msg "提示：向导配置完成后将直接停留在全新的 Zsh 交互终端中。" "Tip: You will remain in the newly configured Zsh session when finished.")"
  exec zsh -ic "p10k configure; exec zsh -l"
elif [[ -t 0 ]] && command -v zsh >/dev/null 2>&1; then
  echo ""
  if ask "$(msg '是否现在立即进入全新的 Zsh 交互环境？' 'Start fresh Zsh session now?') "; then
    printf '\n\033[1;32m%s\033[0m\n' "$(msg '🚀 正在启动全新 Zsh 交互环境...' '🚀 Starting fresh Zsh environment...')"
    exec zsh -l
  fi
fi
