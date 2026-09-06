#!/usr/bin/env bash
# Linux 与 macOS Zsh 跨平台一键配置脚本与更新管理器
# 兼容 Debian/Ubuntu/Fedora/Arch/openSUSE 及 macOS (Homebrew)
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
BACKUP=''
ROLLBACK=''
SKIPPED=()

usage() {
  cat <<'EOF'
用法：bash install.sh [选项]
  --dry-run             只展示计划，不联网、不写文件、不调用权限提升
  --profile basic|full  基础安装（OMZ+主题+3核心插件）或完整安装（+全套CLI工具）
  --with-vfox           请求安装 vfox 多版本管理工具，不自动安装 SDK
  --with-lazydocker     请求安装 lazydocker，不配置 Docker 服务或权限
  --check-updates       检测已安装的 Zsh 插件与常用应用是否有新版本
  --update              交互式升级已安装的 Zsh 插件、主题与包管理器工具
  --rollback DIR        恢复某次安装备份，只恢复配置文件
  --help|-h             显示帮助
实际安装必须在交互终端确认，不提供无人值守默认授权。
EOF
}

die() { printf '错误：%s\n' "$*" >&2; exit 1; }
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
    die "系统中未找到 sha256sum、shasum 或 openssl 计算工具"
  fi
}

while (($#)); do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --profile) (($# >= 2)) || die '--profile 缺少值'; PROFILE=$2; PROFILE_SET=1; shift ;;
    --with-vfox) WITH_VFOX=1 ;;
    --with-lazydocker) WITH_LAZYDOCKER=1 ;;
    --check-updates) CHECK_UPDATES=1 ;;
    --update) DO_UPDATE=1 ;;
    --rollback) (($# >= 2)) || die '--rollback 缺少目录'; ROLLBACK=$2; shift ;;
    --help|-h) usage; exit 0 ;;
    *) die "未知参数：$1" ;;
  esac
  shift
done

# 1. 优先处理版本检测
if ((CHECK_UPDATES)); then
  if [[ -f "$SCRIPT_DIR/scripts/check_updates.sh" ]]; then
    bash "$SCRIPT_DIR/scripts/check_updates.sh"
  else
    die "缺少更新检测脚本：$SCRIPT_DIR/scripts/check_updates.sh"
  fi
  exit 0
fi

# 2. 交互式更新流程
if ((DO_UPDATE)); then
  info "正在检测已安装插件与工具的更新状态..."
  if [[ -f "$SCRIPT_DIR/scripts/check_updates.sh" ]]; then
    bash "$SCRIPT_DIR/scripts/check_updates.sh"
  fi

  STATE_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}/zsh-project"
  AVAILABLE_FILE="$STATE_ROOT/available_updates"
  if [[ ! -s "$AVAILABLE_FILE" ]]; then
    success "所有组件已是最新，无需更新！"
    exit 0
  fi

  echo ""
  if ! ask "是否确认现在更新以上有新版本的组件？"; then
    echo "已取消更新。"
    exit 0
  fi

  info "开始更新 Git 插件与主题..."
  update_git_repo() {
    local name=$1 dir=$2
    [[ -d "$dir/.git" ]] || return 0
    if [[ -n $(git -C "$dir" status --porcelain 2>/dev/null) ]]; then
      warn "$name 存在未提交的本地修改，跳过自动拉取以防止冲突。"
      return 0
    fi
    info "正在拉取 $name 最新代码..."
    if git -C "$dir" pull --ff-only --quiet 2>/dev/null; then
      success "$name 更新完成"
    else
      warn "$name 自动更新失败，请稍后手动检查 git status"
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
    info "正在通过 Homebrew 升级命令行工具..."
    brew upgrade fzf fd bat eza zoxide yazi neovim fastfetch lazydocker vfox zsh git 2>/dev/null || true
  elif [[ "$OS_TYPE" == Linux ]]; then
    if command -v apt-get >/dev/null 2>&1; then
      info "提示：可在终端运行 sudo apt update && sudo apt --only-upgrade install <包名> 升级系统包。"
    fi
  fi

  # 清理更新状态缓存
  : > "$AVAILABLE_FILE"
  if [[ -f "$HOME/.zshrc" ]]; then
    zsh -n "$HOME/.zshrc" && success "配置语法检查通过。"
  fi
  success "更新流程执行完毕！请新开终端体验新版本。"
  exit 0
fi

# 3. 基础环境与配置目录校验
[[ "$PROFILE" == basic || "$PROFILE" == full ]] || die '安装类型必须是 basic 或 full'
OS=$(uname -s)
case "$OS" in
  Linux) ;;
  Darwin) ;;
  *) die "暂不支持该操作系统：$OS。请在 Linux 或 macOS 终端中运行。" ;;
esac

ARCH=$(uname -m)
case "$ARCH" in
  x86_64|amd64) ARCH=x86_64 ;;
  aarch64|arm64) ARCH=arm64 ;;
  *) die "暂不自动支持架构：$ARCH" ;;
esac

[[ $EUID -ne 0 ]] || die '请以普通用户运行；需要系统权限时安装器会单独调用 sudo'
[[ -z "${ZDOTDIR:-}" || "$ZDOTDIR" == "$HOME" ]] || die '检测到自定义 ZDOTDIR，请先手动适配；安装器不会覆盖其它配置目录'
[[ "$HOME" == /* && -d "$HOME" ]] || die 'HOME 不是有效目录'

# 4. 配置回退恢复逻辑
restore() {
  local dir=$1 file expected actual
  [[ -d "$dir" && ! -L "$dir" && -f "$dir/manifest" ]] || die '备份目录或清单不存在'
  [[ $(head -n 1 "$dir/manifest") == "$HOME" ]] || die '备份不属于当前 HOME'
  for file in .zshrc .zsh-project-options; do
    [[ -f "$dir/$file.sha256" && -f "$dir/$file.state" ]] || die "备份不完整：$file"
    [[ ! -L "$HOME/$file" ]] || die "目标已变成符号链接：$file"
    expected=$(cat "$dir/$file.sha256")
    actual=$(calc_sha256 "$HOME/$file") || actual=missing
    [[ "$actual" == "$expected" ]] || die "$file 在安装后发生变化，请手动比较备份再恢复"
    case $(cat "$dir/$file.state") in
      present) [[ -f "$dir/$file" ]] || die "缺少原文件：$file" ;;
      absent) ;;
      *) die '备份状态无效' ;;
    esac
  done
  printf '将恢复 .zshrc 与安装器选项文件。软件、插件、默认 Shell 不会自动回退。\n'
  ((DRY_RUN)) && return
  ask '确认恢复以上配置？' || return
  for file in .zshrc .zsh-project-options; do
    if [[ $(cat "$dir/$file.state") == present ]]; then
      cp -p -- "$dir/$file" "$HOME/$file"
    else
      rm -f -- "$HOME/$file"
    fi
  done
  success '配置已恢复。请新开终端验证。'
}

if [[ -n "$ROLLBACK" ]]; then
  ((DRY_RUN)) || [[ -t 0 ]] || die '恢复需要交互终端'
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
    warn "在 macOS 上未检测到 Homebrew。"
    if ((DRY_RUN)); then
      FAMILY=brew
      info "[预演模式] 将在实际安装时引导安装 Homebrew (https://brew.sh)"
    elif [[ -t 0 ]] && ask "是否现在自动安装 Homebrew？(国内用户可配置镜像)"; then
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      if [[ -x "/opt/homebrew/bin/brew" ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
      elif [[ -x "/usr/local/bin/brew" ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
      fi
      FAMILY=brew
    else
      die "macOS 环境建议通过 Homebrew 安装工具，请先访问 https://brew.sh 安装后重试。"
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
      *) die "暂不自动支持发行版：${ID:-未知系统}；请使用手动教程" ;;
    esac
  elif ((DRY_RUN)); then
    FAMILY=apt
    info "[预演模式] 未找到 ./os_mock.txt，默认模拟 apt 发行版"
  else
    die '缺少 ./os_mock.txt'
  fi
fi

[[ -r "$SCRIPT_DIR/templates/zshrc.zsh" ]] || die '缺少 templates/zshrc.zsh，请下载完整项目'
for file in .zshrc .zsh-project-options; do
  [[ ! -L "$HOME/$file" && ! -d "$HOME/$file" ]] || die "$file 是链接或目录，请手动处理"
  [[ ! -e "$HOME/$file" || -f "$HOME/$file" ]] || die "$file 不是普通文件"
done

if [[ -e "$HOME/.oh-my-zsh" && ! -r "$HOME/.oh-my-zsh/oh-my-zsh.sh" ]]; then
  die '现有 OMZ 不完整；请按排查文档恢复，安装器不会覆盖 custom 或移动现有目录'
fi

# 6. 收集用户选项
if ((!DRY_RUN)); then
  [[ -t 0 ]] || die '安装需要交互终端；查看计划请用 --dry-run'
  if ((!PROFILE_SET)); then
    if ask '是否选择完整工具集？选 N 安装基础主题、补全、高亮和建议'; then PROFILE=full; fi
  fi
  ((WITH_VFOX)) || { if ask '是否启用 vfox 版本管理（自动目录钩子默认关闭）？'; then WITH_VFOX=1; fi; }
  ((WITH_LAZYDOCKER)) || { if ask '是否安装 lazydocker 容器终端管理（不配置 Docker）？'; then WITH_LAZYDOCKER=1; fi; }
fi

printf '\n系统：%s；架构：%s；包管理器：%s；用户：%s\n' "${PRETTY_NAME:-$OS}" "$ARCH" "$FAMILY" "$(id -un)"
printf '安装类型：%s；vfox：%s；lazydocker：%s\n' "$PROFILE" "$WITH_VFOX" "$WITH_LAZYDOCKER"
printf '%s\n' '基础依赖：zsh git curl ca-certificates coreutils；OMZ、Powerlevel10k、三个 Zsh 核心插件。'
[[ "$PROFILE" == full ]] && printf '%s\n' '完整工具：fzf fd bat eza zoxide yazi neovim fastfetch（仓库没有则跳过并记录）。'
printf '%s\n' '备份并更新 ~/.zshrc 和 ~/.zsh-project-options；保留 .zshenv、个人主题、custom 和历史文件。'
printf '%s\n' '默认 Shell 将在配置安装成功后单独询问。'

if ((DRY_RUN)); then
  printf '\n预演结束。实际可用包将在确认安装后通过本机仓库检测。\n'
  exit 0
fi

echo ""
ask '确认按以上计划安装并替换配置？' || exit 0

# 权限校验：Linux 依赖包管理器需要 sudo，macOS Homebrew 必须以普通用户运行
if [[ "$FAMILY" != brew ]]; then
  command -v sudo >/dev/null || die '缺少 sudo，请先由管理员安装依赖'
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
info "正在安装基础核心依赖..."
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
  warn "可选包未在仓库中找到：$pkg，已跳过安装。"
}

# 8. 安装完整工具集
if [[ "$PROFILE" == full ]]; then
  info "正在安装完整工具集..."
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
    [[ -r "$dest/$entry" ]] || die "已有目录不完整：$dest；保留原目录，停止安装"
    info "保留已有组件：$dest"
    return
  fi
  mkdir -p "$(dirname "$dest")"
  temp=$(mktemp -d "$(dirname "$dest")/.zsh-download-XXXXXXXX")
  git clone --depth=1 "$url" "$temp/repo"
  [[ -r "$temp/repo/$entry" ]] || die "下载组件缺少入口：$entry"
  mv "$temp/repo" "$dest"
  rmdir "$temp" 2>/dev/null || rm -rf "$temp"
  success "成功克隆：$dest"
}

info "正在克隆 Oh My Zsh 与主题插件..."
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
  bash "$STATE_ROOT/scripts/check_updates.sh" -q >/dev/null 2>&1 || true
fi

printf '\n\033[1;32m🎉 Zsh 配置安装完成！\033[0m\n'
printf '备份目录与安装日志：%s\n' "$BACKUP"
printf '跳过的未安装包：%s\n' "${SKIPPED[*]:-无}"
printf '提示：请运行 zsh 验证交互环境；首次可用 p10k configure 配置外观。\n'

# 11. 切换默认 Shell（Linux 与 macOS 分别适配）
if ask '是否将 Zsh 设为当前用户的默认登录 Shell？'; then
  zsh_bin=$(command -v zsh)
  current_shell="${SHELL:-}"

  if [[ "$current_shell" == *zsh ]]; then
    info "当前默认 Shell 已经是 Zsh ($current_shell)，无需修改。"
  else
    if ! grep -Fxq "$zsh_bin" /etc/shells; then
      warn "路径 $zsh_bin 不在 /etc/shells 列表中，正在请求权限添加..."
      if command -v sudo >/dev/null 2>&1; then
        echo "$zsh_bin" | sudo tee -a /etc/shells >/dev/null
      fi
    fi

    if grep -Fxq "$zsh_bin" /etc/shells && command -v chsh >/dev/null 2>&1; then
      chsh -s "$zsh_bin" || warn "默认 Shell 修改失败，请稍后手动运行: chsh -s $zsh_bin"
    else
      warn "未修改默认 Shell：缺少 chsh 或权限不足。"
    fi
  fi
fi

printf '\n若需要回退配置，请运行：\n  bash %s/install.sh --rollback %q\n' "$SCRIPT_DIR" "$BACKUP"
