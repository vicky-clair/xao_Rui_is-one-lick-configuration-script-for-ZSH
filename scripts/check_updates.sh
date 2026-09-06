#!/usr/bin/env bash
# Zsh 插件与常用应用新版本检测工具
# 兼容 Linux 与 macOS，支持交互式展示与静默后台缓存写入。
set -Eeuo pipefail
export LC_ALL=C

TIMEOUT_SEC=5
QUIET=0
STATE_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}/zsh-project"
OUTPUT_FILE="$STATE_ROOT/available_updates"
TIMESTAMP_FILE="$STATE_ROOT/last_update_check"

usage() {
  cat <<'EOF'
用法：bash check_updates.sh [选项]
  -q, --quiet         静默运行，仅将结果写入缓存文件（适用于 Shell 启动时后台轮询）
  -o, --output FILE   指定更新结果缓存文件路径
  -t, --timeout SEC   网络检测超时时间（秒，默认 5 秒）
  -h, --help          显示帮助
EOF
}

while (($#)); do
  case "$1" in
    -q|--quiet) QUIET=1 ;;
    -o|--output) (($# >= 2)) || { echo "缺少输出文件路径" >&2; exit 1; }; OUTPUT_FILE=$2; shift ;;
    -t|--timeout) (($# >= 2)) || { echo "缺少超时秒数" >&2; exit 1; }; TIMEOUT_SEC=$2; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "未知参数：$1" >&2; exit 1 ;;
  esac
  shift
done

mkdir -p "$(dirname "$OUTPUT_FILE")"
mkdir -p "$STATE_ROOT"

# 记录本次检查时间戳
date +%s > "$TIMESTAMP_FILE" 2>/dev/null || true

# 超时命令封装（兼容 Linux timeout 与 macOS gtimeout / 降级）
run_with_timeout() {
  local sec=$1; shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$sec" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$sec" "$@"
  else
    "$@"
  fi
}

# 快速网络连通性测试（若离线则直接退出，不阻塞）
if ! run_with_timeout 2 curl -fsI --connect-timeout 2 https://github.com >/dev/null 2>&1; then
  ((QUIET)) || echo "网络不可用或连接 GitHub 超时，跳过更新检测。"
  exit 0
fi

UPDATES=()
ALL_CHECKED=()

check_git_repo() {
  local name=$1 dir=$2
  [[ -d "$dir/.git" ]] || return 0

  # 获取默认跟踪分支
  local upstream
  upstream=$(git -C "$dir" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)
  if [[ -z "$upstream" ]]; then
    if git -C "$dir" show-ref --verify --quiet refs/remotes/origin/master; then
      upstream="origin/master"
    elif git -C "$dir" show-ref --verify --quiet refs/remotes/origin/main; then
      upstream="origin/main"
    else
      return 0
    fi
  fi

  # 静默拉取远端信息
  if run_with_timeout "$TIMEOUT_SEC" git -C "$dir" fetch --quiet origin 2>/dev/null; then
    local local_hash remote_hash behind
    local_hash=$(git -C "$dir" rev-parse HEAD 2>/dev/null || true)
    remote_hash=$(git -C "$dir" rev-parse "$upstream" 2>/dev/null || true)
    if [[ -n "$local_hash" && -n "$remote_hash" && "$local_hash" != "$remote_hash" ]]; then
      behind=$(git -C "$dir" rev-list --count HEAD.."$upstream" 2>/dev/null || echo 0)
      if ((behind > 0)); then
        UPDATES+=("[插件/主题] $name (落后 $behind 个提交)")
        ALL_CHECKED+=("$name: 有新版本 (落后 $behind 提交)")
        return 0
      fi
    fi
    ALL_CHECKED+=("$name: 已是最新")
  else
    ALL_CHECKED+=("$name: 检测超时")
  fi
}

# 1. 检测 Oh My Zsh
check_git_repo "Oh My Zsh" "$HOME/.oh-my-zsh"

# 2. 检测 Powerlevel10k 主题
if [[ -d "$HOME/powerlevel10k" ]]; then
  check_git_repo "Powerlevel10k" "$HOME/powerlevel10k"
elif [[ -d "$HOME/.oh-my-zsh/custom/themes/powerlevel10k" ]]; then
  check_git_repo "Powerlevel10k" "$HOME/.oh-my-zsh/custom/themes/powerlevel10k"
fi

# 3. 检测自定义插件
CUSTOM_PLUGINS_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins"
if [[ -d "$CUSTOM_PLUGINS_DIR" ]]; then
  for pdir in "$CUSTOM_PLUGINS_DIR"/*; do
    if [[ -d "$pdir/.git" ]]; then
      pname=$(basename "$pdir")
      check_git_repo "$pname" "$pdir"
    fi
  done
fi

# 4. 检测命令行应用/工具（Linux / macOS）
check_apps() {
  local os
  os=$(uname -s)
  if [[ "$os" == Darwin ]] && command -v brew >/dev/null 2>&1; then
    # macOS Homebrew 检测
    local outdated
    outdated=$(run_with_timeout "$TIMEOUT_SEC" brew outdated --formula --quiet 2>/dev/null || true)
    if [[ -n "$outdated" ]]; then
      local tools=(fzf fd bat eza zoxide yazi neovim fastfetch lazydocker vfox zsh git)
      for t in "${tools[@]}"; do
        if echo "$outdated" | grep -qFx "$t"; then
          UPDATES+=("[应用工具] $t (Homebrew 有新版本)")
          ALL_CHECKED+=("$t: 有新版本")
        fi
      done
    fi
  elif [[ "$os" == Linux ]]; then
    if command -v apt-get >/dev/null 2>&1 && command -v apt >/dev/null 2>&1; then
      local upgradable
      upgradable=$(apt list --upgradable 2>/dev/null || true)
      local tools=(fzf fd-find bat eza zoxide yazi neovim fastfetch lazydocker vfox zsh)
      for t in "${tools[@]}"; do
        if echo "$upgradable" | grep -qE "^$t/"; then
          UPDATES+=("[应用工具] $t (系统包管理器有新版本)")
          ALL_CHECKED+=("$t: 有新版本")
        fi
      done
    elif command -v dnf >/dev/null 2>&1; then
      local upgradable
      upgradable=$(dnf check-update --quiet 2>/dev/null || true)
      local tools=(fzf fd-find bat eza zoxide yazi neovim fastfetch lazydocker vfox zsh)
      for t in "${tools[@]}"; do
        if echo "$upgradable" | grep -qE "^$t\."; then
          UPDATES+=("[应用工具] $t (DNF 包仓库有新版本)")
          ALL_CHECKED+=("$t: 有新版本")
        fi
      done
    elif command -v checkupdates >/dev/null 2>&1; then
      # Arch Linux
      local upgradable
      upgradable=$(checkupdates 2>/dev/null || true)
      local tools=(fzf fd bat eza zoxide yazi neovim fastfetch lazydocker vfox zsh)
      for t in "${tools[@]}"; do
        if echo "$upgradable" | grep -qE "^$t "; then
          UPDATES+=("[应用工具] $t (Arch 包仓库有新版本)")
          ALL_CHECKED+=("$t: 有新版本")
        fi
      done
    fi
  fi
}

check_apps

# 写入缓存文件
temp_out=$(mktemp "$OUTPUT_FILE.tmp.XXXXXX")
if ((${#UPDATES[@]} > 0)); then
  printf '%s\n' "${UPDATES[@]}" > "$temp_out"
else
  : > "$temp_out"
fi
mv "$temp_out" "$OUTPUT_FILE"

# 若非静默模式，直接输出清晰汇总
if ((!QUIET)); then
  echo "========================================"
  echo "         Zsh 插件与工具检测结果         "
  echo "========================================"
  if ((${#UPDATES[@]} > 0)); then
    echo "💡 发现以下 ${#UPDATES[@]} 个组件可更新："
    for item in "${UPDATES[@]}"; do
      echo "  • $item"
    done
    echo ""
    echo "提示：可运行 'bash install.sh --update' 或在 Zsh 中运行 'zsh-update' 进行升级。"
  else
    echo "✅ 所有已安装的插件、主题与应用均为最新版本！"
  fi
  echo "========================================"
fi
