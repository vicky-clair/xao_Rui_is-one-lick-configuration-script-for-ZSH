#!/usr/bin/env bash
# Zsh 插件与常用应用新版本检测工具
# 兼容 Linux 与 macOS，支持双语（中/英）交互与静默后台缓存写入。
set -Eeuo pipefail
export LC_ALL=C

TIMEOUT_SEC=5
QUIET=0
CHECK_FAILED=0
LANG_CHOICE="${ZSH_PROJECT_LANG:-zh}"
STATE_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}/zsh-project"
OUTPUT_FILE="$STATE_ROOT/available_updates"
TIMESTAMP_FILE="$STATE_ROOT/last_update_check"

msg() {
  if [[ "$LANG_CHOICE" == en ]]; then
    printf '%s' "$2"
  else
    printf '%s' "$1"
  fi
}

usage() {
  cat <<EOF
$(msg "用法：bash check_updates.sh [选项]" "Usage: bash check_updates.sh [options]")
  -q, --quiet         $(msg "静默运行，仅将结果写入缓存文件" "Quiet mode, write results to cache file only")
  -o, --output FILE   $(msg "指定更新结果缓存文件路径" "Specify output cache file path")
  -t, --timeout SEC   $(msg "网络检测超时时间（秒，默认 5 秒）" "Network check timeout in seconds (default 5s)")
  --lang zh|en        $(msg "界面语言（zh 为中文，en 为英文）" "UI language (zh: Chinese, en: English)")
  -h, --help          $(msg "显示帮助" "Show help")
EOF
}

while (($#)); do
  case "$1" in
    -q|--quiet) QUIET=1 ;;
    -o|--output) (($# >= 2)) || { echo "Missing output path / 缺少输出文件路径" >&2; exit 1; }; OUTPUT_FILE=$2; shift ;;
    -t|--timeout) (($# >= 2)) || { echo "Missing timeout / 缺少超时秒数" >&2; exit 1; }; TIMEOUT_SEC=$2; shift ;;
    --lang) (($# >= 2)) || { echo "Missing language / 缺少语言值" >&2; exit 1; }; LANG_CHOICE=$2; shift ;;
    --lang=*) LANG_CHOICE="${1#*=}" ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown parameter / 未知参数：$1" >&2; exit 1 ;;
  esac
  shift
done

command mkdir -p "$(dirname "$OUTPUT_FILE")"
command mkdir -p "$STATE_ROOT"

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
  ((QUIET)) || echo "$(msg "网络不可用或连接 GitHub 超时，跳过更新检测。" "Network unavailable or GitHub connection timed out, skipping update check.")"
  exit 2
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
        UPDATES+=("$(msg "[插件/主题] $name (落后 $behind 个提交)" "[Plugin/Theme] $name (behind $behind commits)")")
        ALL_CHECKED+=("$name: $(msg "有新版本 (落后 $behind 提交)" "update available (behind $behind commits)")")
        return 0
      fi
    fi
    ALL_CHECKED+=("$name: $(msg "已是最新" "up to date")")
  else
    CHECK_FAILED=1
    ALL_CHECKED+=("$name: $(msg "检测超时" "check timed out")")
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

# 4. 检测 Tmux TPM 插件
TMUX_PLUGINS_DIR="$HOME/.tmux/plugins"
if [[ -d "$TMUX_PLUGINS_DIR" ]]; then
  for pdir in "$TMUX_PLUGINS_DIR"/*; do
    if [[ -d "$pdir/.git" ]]; then
      pname=$(basename "$pdir")
      check_git_repo "tmux/$pname" "$pdir"
    fi
  done
fi

# 4.5. 检测 FZF 官方仓库更新（若通过 ~/.fzf 安装）
if [[ -d "$HOME/.fzf/.git" ]]; then
  check_git_repo "FZF (Binary Repo)" "$HOME/.fzf"
fi

# 5. 检测命令行应用/工具（Linux / macOS）
check_apps() {
  local os
  os=$(uname -s)
  if [[ "$os" == Darwin ]] && command -v brew >/dev/null 2>&1; then
    # macOS Homebrew 检测
    local outdated
    outdated=$(run_with_timeout "$TIMEOUT_SEC" brew outdated --formula --quiet 2>/dev/null) || { CHECK_FAILED=1; return 0; }
    if [[ -n "$outdated" ]]; then
      local tools=(fzf fd bat eza zoxide yazi neovim fastfetch lazydocker lazygit vfox zsh git tmux)
      for t in "${tools[@]}"; do
        if echo "$outdated" | grep -qFx "$t"; then
          UPDATES+=("$(msg "[应用工具] $t (Homebrew 有新版本)" "[CLI Tool] $t (Homebrew update available)")")
          ALL_CHECKED+=("$t: $(msg "有新版本" "update available")")
        fi
      done
    fi
  elif [[ "$os" == Linux ]]; then
    if command -v apt-get >/dev/null 2>&1 && command -v apt >/dev/null 2>&1; then
      local upgradable
      upgradable=$(run_with_timeout "$TIMEOUT_SEC" apt list --upgradable 2>/dev/null) || { CHECK_FAILED=1; return 0; }
      local tools=(fzf fd-find bat eza zoxide yazi neovim fastfetch lazydocker lazygit vfox zsh tmux)
      for t in "${tools[@]}"; do
        if echo "$upgradable" | grep -qE "^$t/"; then
          UPDATES+=("$(msg "[应用工具] $t (APT 包管理器有新版本)" "[CLI Tool] $t (APT package update available)")")
          ALL_CHECKED+=("$t: $(msg "有新版本" "update available")")
        fi
      done
    elif command -v dnf >/dev/null 2>&1; then
      local upgradable
      local status=0
      upgradable=$(run_with_timeout "$TIMEOUT_SEC" dnf check-update --quiet 2>/dev/null) || status=$?
      if [[ "$status" != 0 && "$status" != 100 ]]; then CHECK_FAILED=1; return 0; fi
      local tools=(fzf fd-find bat eza zoxide yazi neovim fastfetch lazydocker lazygit vfox zsh tmux)
      for t in "${tools[@]}"; do
        if echo "$upgradable" | grep -qE "^$t\."; then
          UPDATES+=("$(msg "[应用工具] $t (DNF 包仓库有新版本)" "[CLI Tool] $t (DNF repository update available)")")
          ALL_CHECKED+=("$t: $(msg "有新版本" "update available")")
        fi
      done
    elif command -v checkupdates >/dev/null 2>&1; then
      # Arch Linux
      local upgradable
      local status=0
      upgradable=$(run_with_timeout "$TIMEOUT_SEC" checkupdates 2>/dev/null) || status=$?
      if [[ "$status" != 0 && "$status" != 2 ]]; then CHECK_FAILED=1; return 0; fi
      local tools=(fzf fd bat eza zoxide yazi neovim fastfetch lazydocker lazygit vfox zsh tmux)
      for t in "${tools[@]}"; do
        if echo "$upgradable" | grep -qE "^$t "; then
          UPDATES+=("$(msg "[应用工具] $t (Arch 包仓库有新版本)" "[CLI Tool] $t (Arch repository update available)")")
          ALL_CHECKED+=("$t: $(msg "有新版本" "update available")")
        fi
      done
    fi
  fi
}

check_apps

# 不用不完整的检查覆盖上次结果，防止网络错误被当成“没有更新”。
if ((CHECK_FAILED)); then
  ((QUIET)) || echo "$(msg '部分检测失败，保留原缓存，请稍后重试。' 'Some checks failed; previous cache preserved. Retry later.')"
  exit 2
fi

# 写入缓存文件
temp_out=$(mktemp "$OUTPUT_FILE.tmp.XXXXXX")
if ((${#UPDATES[@]} > 0)); then
  printf '%s\n' "${UPDATES[@]}" > "$temp_out"
else
  : > "$temp_out"
fi
mv "$temp_out" "$OUTPUT_FILE"
command date +%s > "$TIMESTAMP_FILE" 2>/dev/null || true

# 若非静默模式，直接输出清晰汇总
if ((!QUIET)); then
  echo "========================================"
  echo "       $(msg 'Zsh 插件与工具检测结果' 'Zsh Plugins & Tools Update Check')       "
  echo "========================================"
  if ((${#UPDATES[@]} > 0)); then
    echo "$(msg "💡 发现以下 ${#UPDATES[@]} 个组件可更新：" "💡 Found ${#UPDATES[@]} component(s) with updates available:")"
    for item in "${UPDATES[@]}"; do
      echo "  • $item"
    done
    echo ""
    echo "$(msg "提示：可运行 'bash install.sh --update' 或在 Zsh 中运行 'zsh-update' 进行升级。" "Tip: Run 'bash install.sh --update' or 'zsh-update' in Zsh to upgrade.")"
  else
    echo "$(msg "✅ 所有已安装的插件、主题与应用均为最新版本！" "✅ All installed plugins, themes, and CLI tools are up to date!")"
  fi
  echo "========================================"
fi
