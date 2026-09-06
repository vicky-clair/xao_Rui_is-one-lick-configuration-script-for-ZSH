#!/usr/bin/env bash
# Linux 与 macOS Zsh 跨平台一键配置脚本与更新管理器
# 兼容 Debian/Ubuntu/Fedora/Arch/openSUSE 及 macOS (Homebrew)，支持中英双语交互
set -Eeuo pipefail
export LC_ALL=C

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
DRY_RUN=0
PROFILE=basic
PROFILE_SET=0
WITH_VFOX=0
WITH_LAZYDOCKER=0
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
  --with-vfox           $(msg "请求安装 vfox 多版本管理工具，不自动安装 SDK" "Install vfox version manager (does not install SDKs automatically)")
  --with-lazydocker     $(msg "请求安装 lazydocker，不配置 Docker 服务或权限" "Install lazydocker (does not configure Docker daemon or permissions)")
  --check-updates       $(msg "检测已安装的 Zsh 插件与常用应用是否有新版本" "Check if installed plugins and CLI tools have new updates")
  --update              $(msg "交互式升级已安装的 Zsh 插件、主题与包管理器工具" "Interactively update installed plugins, themes, and CLI tools")
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

ask() {
  local answer
  read -r -p "$1 [y/N] " answer || return 1
  [[ "$answer" == y || "$answer" == Y ]]
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
    --with-vfox) WITH_VFOX=1 ;;
    --with-lazydocker) WITH_LAZYDOCKER=1 ;;
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

# 交互式语言选择菜单（若未通过命令行显式指定 --lang）
if ((!DRY_RUN)) && [[ -t 0 ]] && ((!LANG_SET)) && [[ -z "$ROLLBACK" ]]; then
  printf '\n\033[1;36m🌐 Please select language / 请选择界面语言:\033[0m\n'
  printf '  1) 简体中文 (Chinese) [默认]\n'
  printf '  2) English\n'
  read -r -p "Enter choice / 请输入编号 [1/2]: " _l_choice || _l_choice=1
  case "$_l_choice" in
    2|en|EN|English|english) LANG_CHOICE="en" ;;
    *) LANG_CHOICE="zh" ;;
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

  # 应用工具升级
  OS_TYPE=$(uname -s)
  if [[ "$OS_TYPE" == Darwin ]] && command -v brew >/dev/null 2>&1; then
    info "$(msg "正在通过 Homebrew 升级命令行工具..." "Upgrading CLI tools via Homebrew...")"
    brew upgrade fzf fd bat eza zoxide yazi neovim fastfetch lazydocker vfox zsh git 2>/dev/null || true
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
  for file in .zshrc .zsh-project-options; do
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
  printf '%s\n' "$(msg '将恢复 .zshrc 与安装器选项文件。软件、插件、默认 Shell 不会自动回退。' 'Restoring .zshrc and options file. Software, plugins, and default shell will not be reverted.')"
  ((DRY_RUN)) && return
  ask "$(msg '确认恢复以上配置？' 'Confirm restoring the above configuration?')" || return
  for file in .zshrc .zsh-project-options; do
    if [[ $(cat "$dir/$file.state") == present ]]; then
      cp -p -- "$dir/$file" "$HOME/$file"
    else
      rm -f -- "$HOME/$file"
    fi
  done
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

[[ -r "$SCRIPT_DIR/templates/zshrc.zsh" ]] || die "$(msg '缺少 templates/zshrc.zsh，请下载完整项目' 'templates/zshrc.zsh missing; please download the full repository')"
for file in .zshrc .zsh-project-options; do
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
  ((WITH_VFOX)) || { if ask "$(msg '是否启用 vfox 版本管理（自动目录钩子默认关闭）？' 'Enable vfox version manager (auto directory hook disabled by default)?')"; then WITH_VFOX=1; fi; }
  ((WITH_LAZYDOCKER)) || { if ask "$(msg '是否安装 lazydocker 容器终端管理（不配置 Docker）？' 'Install lazydocker container UI (Docker daemon not configured)?')"; then WITH_LAZYDOCKER=1; fi; }
fi

printf '\n%s: %s; %s: %s; %s: %s; %s: %s\n' \
  "$(msg '系统' 'OS')" "${PRETTY_NAME:-$OS}" \
  "$(msg '架构' 'Arch')" "$ARCH" \
  "$(msg '包管理器' 'Package Manager')" "$FAMILY" \
  "$(msg '用户' 'User')" "$(id -un)"
printf '%s: %s; vfox: %s; lazydocker: %s; %s: %s\n' \
  "$(msg '安装类型' 'Profile')" "$PROFILE" "$WITH_VFOX" "$WITH_LAZYDOCKER" \
  "$(msg '语言' 'Language')" "$LANG_CHOICE"
printf '%s\n' "$(msg '基础依赖：zsh git curl ca-certificates coreutils；OMZ、Powerlevel10k、三个 Zsh 核心插件。' 'Base dependencies: zsh, git, curl, ca-certificates, coreutils; OMZ, Powerlevel10k, 3 core plugins.')"
[[ "$PROFILE" == full ]] && printf '%s\n' "$(msg '完整工具：fzf fd bat eza zoxide yazi neovim fastfetch（仓库没有则跳过并记录）。' 'Full tools: fzf, fd, bat, eza, zoxide, yazi, neovim, fastfetch (skipped if unavailable in repository).')"
printf '%s\n' "$(msg '备份并更新 ~/.zshrc 和 ~/.zsh-project-options；保留 .zshenv、个人主题、custom 和历史文件。' 'Backup and update ~/.zshrc and ~/.zsh-project-options; preserving .zshenv, custom themes and history.')"
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
for file in .zshrc .zsh-project-options; do
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
    brew install zsh git curl coreutils
    ;;
  apt)
    sudo apt-get update
    sudo apt-get install -y zsh git curl ca-certificates coreutils
    ;;
  dnf)
    sudo dnf install -y zsh git curl ca-certificates coreutils
    ;;
  pacman)
    sudo pacman -Syu --needed --noconfirm zsh git curl ca-certificates coreutils
    ;;
  zypper)
    sudo zypper install -y zsh git curl ca-certificates coreutils
    ;;
esac

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
      if apt-cache policy "$pkg" 2>/dev/null | grep -Eq 'Candidate: [^ (]'; then
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
fi

((WITH_VFOX)) && optional_package vfox vfox
((WITH_LAZYDOCKER)) && optional_package lazydocker lazydocker

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
ZSH_PROJECT_DIR="$SCRIPT_DIR"
ZSH_PROJECT_LANG="$LANG_CHOICE"
ZSH_PROJECT_AUTO_CHECK_UPDATE=1
ZSH_PROJECT_CHECK_INTERVAL_DAYS=7
EOF

zsh -n "$BACKUP/new.zshrc"
zsh -n "$BACKUP/new.options"

install -m 600 "$BACKUP/new.options" "$HOME/.zsh-project-options"
install -m 600 "$BACKUP/new.zshrc" "$HOME/.zshrc"

for file in .zshrc .zsh-project-options; do
  calc_sha256 "$HOME/$file" > "$BACKUP/$file.sha256"
done

# 首次执行一次静默后台版本检测（生成初始缓存）
if [[ -f "$STATE_ROOT/scripts/check_updates.sh" ]]; then
  bash "$STATE_ROOT/scripts/check_updates.sh" -q --lang "$LANG_CHOICE" >/dev/null 2>&1 || true
fi

printf '\n\033[1;32m🎉 %s\033[0m\n' "$(msg 'Zsh 配置安装完成！' 'Zsh configuration installed successfully!')"
printf '%s: %s\n' "$(msg '备份目录与安装日志' 'Backup directory and install log')" "$BACKUP"
printf '%s: %s\n' "$(msg '跳过的未安装包' 'Skipped packages')" "${SKIPPED[*]:-none}"
printf '%s\n' "$(msg '提示：请运行 zsh 验证交互环境；首次可用 p10k configure 配置外观。' 'Tip: Run zsh to verify. Configure prompt with p10k configure.')"

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
      chsh -s "$zsh_bin" || warn "$(msg "默认 Shell 修改失败，请稍后手动运行: chsh -s $zsh_bin" "chsh failed; please run manually: chsh -s $zsh_bin")"
    else
      warn "$(msg "未修改默认 Shell：缺少 chsh 或权限不足。" "Default shell not modified: missing chsh or insufficient permissions.")"
    fi
  fi
fi

printf '\n%s:\n  bash %s/install.sh --rollback %q\n' \
  "$(msg '若需要回退配置，请运行' 'To rollback configuration, run')" "$SCRIPT_DIR" "$BACKUP"
