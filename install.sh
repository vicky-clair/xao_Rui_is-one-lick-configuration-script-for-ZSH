#!/usr/bin/env bash
# Linux 与 macOS Zsh 跨平台一键配置脚本与更新管理器
# 兼容 Debian/Ubuntu/Fedora/Arch/openSUSE 及 macOS (Homebrew)，支持中英双语交互
set -Eeuo pipefail
ORIG_LC_ALL="${LC_ALL:-}"
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
# 独立管理命令不进入安装流程，也不要求重新安装组件。
for _management_arg in "$@"; do
  case "$_management_arg" in
    --disable|--enable|--doctor|--configure|--set|--profile-startup|--retry-failed|--list-backups|--diff-backup|--restore-backup)
      [[ -r "$SCRIPT_DIR/scripts/manage.sh" ]] || { printf '缺少 scripts/manage.sh，请获取完整项目。\n' >&2; exit 1; }
      exec bash "$SCRIPT_DIR/scripts/manage.sh" "$@" ;;
  esac
done
unset _management_arg
# 统一补充常用包管理器与语言工具链 bin 目录（Homebrew/Go/Cargo/pnpm/vfox），确保检测与安装一致
if [[ -z "${ZSH_PROJECT_TEST_MARKER:-${AUDIT_MARKER:-}}" ]]; then
  _EXTRA_PATHS="$HOME/.local/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:/opt/nvim:$HOME/go/bin:$HOME/.cargo/bin:$HOME/.local/share/pnpm:$HOME/.version-fox/sdks/golang/packages/bin"
  export PATH="$_EXTRA_PATHS:$PATH"
  unset _EXTRA_PATHS
fi
DRY_RUN=0
PROFILE=basic
PROFILE_SET=0
WITH_VFOX=0
WITH_LAZYDOCKER=0
WITH_LAZYGIT=0
WITH_TMUX=0
WITHOUT_TMUX=0
WITH_LATEST_NVIM=0
P10K_STYLE=rainbow
P10K_STYLE_SET=0
CHECK_UPDATES=0
DO_UPDATE=0
LANG_CHOICE="${ZSH_PROJECT_LANG:-zh}"
LANG_SET=0
ASSUME_YES=0
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
  --with-latest-nvim    $(msg "从 GitHub Release 下载安装最新官方 Neovim (>= 0.10.x)" "Install latest official Neovim from GitHub release (>= 0.10.x)")
  --with-vfox           $(msg "请求安装 vfox 多版本管理工具，不自动安装 SDK" "Install vfox version manager (does not install SDKs automatically)")
  --with-lazydocker     $(msg "请求安装 lazydocker，不配置 Docker 服务或权限" "Install lazydocker (does not configure Docker daemon or permissions)")
  --with-lazygit        $(msg "请求安装 lazygit Git 终端管理面板" "Install lazygit Git TUI panel")
  --with-tmux           $(msg "请求安装并配置 tmux 终端复用器（含剪贴板互通与美化主题）" "Install and configure tmux terminal multiplexer (with clipboard & themes)")
  --without-tmux|--no-tmux $(msg "显式跳过 tmux 及其配置（即使系统已安装 tmux 也不启用）" "Explicitly skip tmux and its configuration even if installed")
  --check-updates       $(msg "检测已安装的 Zsh 插件与常用应用是否有新版本" "Check if installed plugins and CLI tools have new updates")
  --update              $(msg "交互式升级已安装的 Zsh/Tmux 插件、主题与包管理器工具" "Interactively update installed plugins, themes, and CLI tools")
  --lang zh|en          $(msg "界面语言（zh 为中文，en 为英文）" "UI language (zh for Chinese, en for English)")
  --rollback DIR        $(msg "恢复某次安装备份，只恢复配置文件" "Rollback configurations from a specific backup directory")
  --disable / --enable  停用/恢复 Zsh 配置，保留应用与 tmux
  --doctor              只读配置体检
  --configure           交互式开关菜单（新会话生效）
  --set KEY=0|1         设置一个功能开关；管理命令支持 --yes
  --profile-startup     手动测量初始化阶段与钩子耗时
  --retry-failed [TOOL] 重试失败组件，不重新部署配置
  --list-backups        列出安装与配置管理备份
  --diff-backup DIR     比较备份与当前配置
  --yes|-y              $(msg "非交互模式，对所有询问默认确认（适用自动化脚本与 CI）" "Assume yes for all prompts / non-interactive mode")
  --help|-h             $(msg "显示帮助" "Show help")
$(msg "实际安装必须在交互终端确认，或显式传入 --yes 参数。" "Actual installation must be confirmed interactively or via --yes.")
EOF
}

die() { printf '\033[1;31m%s: %s\033[0m\n' "$(msg '错误' 'Error')" "$*" >&2; exit 1; }
info() { printf '\033[1;34mℹ %s\033[0m\n' "$*"; }
success() { printf '\033[1;32m✓ %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m⚠ %s\033[0m\n' "$*"; }

# --- 单键免回车瞬时读取函数（静默捕获，彻底消除终端回显+脚本echo导致的重复显示如 yy）---
read_key() {
  local key=''
  if [[ -t 0 ]]; then
    # -s: 关闭终端硬件回显，彻底杜绝按键在终端被打印两次（如 yy）的问题
    # -n 1: 瞬时读取单个字符，无需用户敲击 Enter 回车键
    read -s -n 1 -r key || key=''
    # 清理输入流中可能残留的多余换行符，防止污染后续选项（兼容 macOS Bash 3.2）
    if (( BASH_VERSINFO[0] >= 4 )); then
      while read -t 0.05 -n 1000 -r _discard 2>/dev/null; do :; done
    elif command -v zsh >/dev/null 2>&1; then
      zsh -f -c 'while read -s -t 0.05 -k 1 -u 0 _discard 2>/dev/null; do :; done' 2>/dev/null || true
    fi
  else
    read -r key || key=''
  fi
  if [[ "$key" == $'\n' || "$key" == $'\r' ]]; then
    echo ""
    return 0
  fi
  echo "$key"
}

ask() {
  local prompt=$1
  if ((ASSUME_YES)); then
    printf '%s [y/N] y\n' "$prompt"
    return 0
  fi
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

# ==============================================================================
# Neovim 独立目录原子替换函数 (Atomic Directory Swap)
# ==============================================================================
# 设计背景与安全保障机制：
# 1. 为什么需要整树原子交换：
#    Neovim 官方发布包包含 bin/、lib/、share/nvim/runtime 等完整目录树。
#    直接解压覆盖容易由于旧动态库、旧 Lua 运行时残留造成段错误 (Segmentation Fault)。
# 2. 隔离与前置功能自测：
#    新版本先解压到临时目录 $stage/new 中，直接执行 "$stage/new/bin/nvim --version" 校验；
#    只有可执行文件能够正常启动并返回 0，才允许执行后续的目录替换。
# 3. 失败零破坏原子回退：
#    使用 mv 进行原子重命名。若任何一步发生异常，立刻把原目录和原软链接还原，
#    绝不删除旧版本，并将排查信息保存在 $stage 中。
# 4. 软链接覆盖陷阱防护：
#    若目标链接已存在且指向目录，直接 `mv new_link old_link` 会错误地把新链接移动进该目录；
#    因此必须先将原链接移至 $stage/displaced-link，再把新链接原子移至目标位置。
install_nvim_tree() {
  local source_dir=$1 stage target link old=0 had_link=0
  target="$HOME/.local/opt/nvim"
  link="$HOME/.local/bin/nvim"
  [[ ! -L "$target" && ! -L "$HOME/.local/opt" ]] || return 1
  [[ ! -e "$target" || -d "$target" ]] || return 1
  [[ ! -d "$link" || -L "$link" ]] || return 1
  mkdir -p "$HOME/.local/opt" "$HOME/.local/bin" || return 1
  stage=$(mktemp -d "$HOME/.local/opt/.nvim-swap-XXXXXXXX") || return 1
  cp -R "$source_dir" "$stage/new" || return 1
  "$stage/new/bin/nvim" --version > "$stage/version.txt" 2>&1 || return 1
  if [[ -e "$link" || -L "$link" ]]; then
    cp -Pp "$link" "$stage/previous-link" || return 1
    had_link=1
  fi
  ln -s "$target/bin/nvim" "$stage/new-link" || return 1
  if [[ -d "$target" ]]; then
    mv "$target" "$stage/previous" || return 1
    old=1
  fi
  if ! mv "$stage/new" "$target"; then
    ((old == 0)) || mv "$stage/previous" "$target"
    return 1
  fi
  # 先移走目标链接，避免 mv 在链接指向目录时把新链接放进该目录。
  if [[ -e "$link" || -L "$link" ]]; then
    if ! mv "$link" "$stage/displaced-link"; then
      mv "$target" "$stage/failed-new"
      ((old == 0)) || mv "$stage/previous" "$target"
      return 1
    fi
  fi
  if ! mv "$stage/new-link" "$link"; then
    mv "$target" "$stage/failed-new"
    ((old == 0)) || mv "$stage/previous" "$target"
    ((had_link == 0)) || cp -Pp "$stage/previous-link" "$link"
    return 1
  fi
  printf 'Neovim 验证并切换完成；旧目录与链接保留在：%s\n' "$stage"
}

while (($#)); do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --yes|-y) ASSUME_YES=1 ;;
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
    --with-latest-nvim) WITH_LATEST_NVIM=1 ;;
    --with-vfox) WITH_VFOX=1 ;;
    --with-lazydocker) WITH_LAZYDOCKER=1 ;;
    --with-lazygit) WITH_LAZYGIT=1 ;;
    --with-tmux) WITH_TMUX=1; WITHOUT_TMUX=0 ;;
    --without-tmux|--no-tmux) WITHOUT_TMUX=1; WITH_TMUX=0 ;;
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

# 统一预演出口必须早于语言交互、自举下载、更新检查和任何状态写入。
[[ "$PROFILE" == basic || "$PROFILE" == full ]] || die 'Invalid profile: basic|full'
[[ "$LANG_CHOICE" == zh || "$LANG_CHOICE" == en ]] || die 'Invalid language: zh|en'
if ((DRY_RUN)); then
  printf '[DRY RUN] OS=%s ARCH=%s profile=%s theme=%s\n' "$(uname -s)" "$(uname -m)" "$PROFILE" "$P10K_STYLE"
  printf '[DRY RUN] vfox=%s lazydocker=%s lazygit=%s tmux=%s latest-nvim=%s\n' "$WITH_VFOX" "$WITH_LAZYDOCKER" "$WITH_LAZYGIT" "$WITH_TMUX" "$WITH_LATEST_NVIM"
  if [[ -n "$ROLLBACK" ]]; then
    printf '[DRY RUN] 将校验并恢复备份目录：%s（此次不验证或写入）\n' "$ROLLBACK"
  elif ((CHECK_UPDATES || DO_UPDATE)); then
    printf '[DRY RUN] 将检查更新；更新模式会另行确认。此次不联网、不写缓存、不执行更新。\n'
  else
    printf '[DRY RUN] 实际安装将检测包管理器、收集选项、检查目标、备份配置并安装所选组件。\n'
    printf '[DRY RUN] 缺失模板将在实际运行时下载；本次不调用下载器或 sudo。\n'
  fi
  exit 0
fi

[[ ! -e "${XDG_STATE_HOME:-$HOME/.local/state}/zsh-project/disabled" || $CHECK_UPDATES == 1 || $DO_UPDATE == 1 ]] || die '项目配置已停用；请先 --enable，再重新安装或回退。'

# 交互式语言选择菜单（若未通过命令行显式指定 --lang，按键即响应）
if ((!DRY_RUN)) && [[ -t 0 ]] && ((!LANG_SET)) && ((!ASSUME_YES)) && [[ -z "$ROLLBACK" ]]; then
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
  [[ -t 0 ]] || die 'Update requires an interactive terminal'
  UPDATE_INCOMPLETE=0
  STATE_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}/zsh-project"
  AVAILABLE_FILE="$STATE_ROOT/available_updates"

  info "$(msg "正在检测已安装插件与工具的更新状态..." "Checking update status for installed plugins and tools...")"
  check_status=0
  if [[ -f "$SCRIPT_DIR/scripts/check_updates.sh" ]]; then
    bash "$SCRIPT_DIR/scripts/check_updates.sh" --lang "$LANG_CHOICE" || check_status=$?
  fi

  if ((check_status != 0)); then
    if [[ -s "$AVAILABLE_FILE" ]]; then
      echo ""
      warn "$(msg "在线检测遇到网络延迟，但检测到本地此前记录的可用更新清单：" "Online check encountered network delay, but cached update list found:")"
      while IFS= read -r _u_item || [[ -n "$_u_item" ]]; do
        [[ -n "$_u_item" ]] && printf '  \033[1;36m•\033[0m %s\n' "$_u_item"
      done < "$AVAILABLE_FILE"
      echo ""
      if ! ask "$(msg "是否基于已有缓存清单继续尝试升级？" "Proceed with update using cached list?")"; then
        echo "$(msg "已取消更新。" "Update cancelled.")"
        exit 0
      fi
    else
      die "$(msg "更新检测未完成（网络连接超时），且无本地缓存。请检查网络后重试。" "Update check failed (connection timed out) and no local cache available.")"
    fi
  else
    if [[ ! -s "$AVAILABLE_FILE" ]]; then
      success "$(msg "所有组件已是最新，无需更新！" "All components are already up to date!")"
      exit 0
    fi

    echo ""
    if ! ask "$(msg "是否确认现在更新以上有新版本的组件？" "Confirm updating the above components now?")"; then
      echo "$(msg "已取消更新。" "Update cancelled.")"
      exit 0
    fi
  fi

  UPDATED_OK=()
  UPDATED_FAIL=()
  UPDATED_SKIP=()

  info "$(msg "开始更新 Git 插件与主题..." "Updating Git plugins and themes...")"
  update_git_repo() {
    local name=$1 dir=$2
    [[ -d "$dir/.git" ]] || return 0
    # 使用 -uno 仅检测受版本控制文件的修改与删除，避免运行期生成的缓存（如 __pycache__）误判为代码冲突
    if [[ -n $(git -C "$dir" status --porcelain -uno 2>/dev/null) ]]; then
      UPDATE_INCOMPLETE=1
      UPDATED_SKIP+=("$name | $(msg "存在未提交的本地修改，已跳过自动拉取以防止代码冲突" "has local changes, skipped auto-pull to prevent conflict") | cd \"$dir\" && git status")
      warn "$(msg "$name 存在未提交的本地修改，跳过自动拉取以防止冲突。" "$name has uncommitted local changes; skipping pull to prevent conflicts.")"
      return 0
    fi
    info "$(msg "正在拉取 $name 最新代码..." "Pulling latest code for $name...")"
    local pull_out
    if pull_out=$(git -C "$dir" pull --ff-only 2>&1); then
      UPDATED_OK+=("$name")
      success "$(msg "$name 更新完成" "$name updated successfully")"
    else
      UPDATE_INCOMPLETE=1
      local first_err
      first_err=$(printf '%s\n' "$pull_out" | command grep -v '^[[:space:]]*$' | head -n 1)
      UPDATED_FAIL+=("$name | ${first_err:-$(msg "拉取超时或网络连接失败" "Pull timed out or network failed")} | cd \"$dir\" && git pull")
      warn "$(msg "$name 自动更新失败 (${first_err:-网络超时})" "$name update failed (${first_err:-network timeout})")"
    fi
  }

  update_git_repo "Oh My Zsh" "$HOME/.oh-my-zsh"
  [[ -d "$HOME/powerlevel10k/.git" ]] && update_git_repo "Powerlevel10k" "$HOME/powerlevel10k"
  if [[ -d "$HOME/.oh-my-zsh/custom/themes/powerlevel10k/.git" ]]; then
    if [[ ! -d "$HOME/powerlevel10k/.git" ]]; then
      update_git_repo "Powerlevel10k" "$HOME/.oh-my-zsh/custom/themes/powerlevel10k"
    else
      update_git_repo "Powerlevel10k (OMZ)" "$HOME/.oh-my-zsh/custom/themes/powerlevel10k"
    fi
  fi

  CUSTOM_PLUGINS_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins"
  if [[ -d "$CUSTOM_PLUGINS_DIR" ]]; then
    for pdir in "$CUSTOM_PLUGINS_DIR"/*; do
      if [[ -d "$pdir/.git" ]]; then
        update_git_repo "$(basename "$pdir")" "$pdir"
      fi
    done
  fi

  # Tmux 插件升级（逐个 Git 仓库升级以保证与检测脚本完全对应并精准剔除缓存）
  TMUX_PLUGINS_DIR="$HOME/.tmux/plugins"
  if [[ -d "$TMUX_PLUGINS_DIR" ]]; then
    info "$(msg "正在更新 Tmux 插件..." "Updating Tmux plugins...")"
    for pdir in "$TMUX_PLUGINS_DIR"/*; do
      if [[ -d "$pdir/.git" ]]; then
        pname=$(basename "$pdir")
        update_git_repo "tmux/$pname" "$pdir"
      fi
    done
  fi

  # FZF 官方仓库升级
  if [[ -d "$HOME/.fzf/.git" ]]; then
    update_git_repo "FZF" "$HOME/.fzf"
    if [[ -x "$HOME/.fzf/install" ]]; then
      if bash "$HOME/.fzf/install" --bin --no-update-rc 2>/dev/null; then
        ln -sf "$HOME/.fzf/bin/fzf" "$HOME/.local/bin/fzf" 2>/dev/null || true
      else
        UPDATE_INCOMPLETE=1
        UPDATED_FAIL+=("FZF 二进制安装 | $(msg "install 脚本执行失败" "install script failed") | cd \"$HOME/.fzf\" && ./install --bin")
      fi
    fi
  fi

  # 应用工具升级
  OS_TYPE=$(uname -s)
  if [[ "$OS_TYPE" == Darwin ]] && command -v brew >/dev/null 2>&1; then
    info "$(msg "正在通过 Homebrew 升级命令行工具..." "Upgrading CLI tools via Homebrew...")"
    brew_outdated=$(HOMEBREW_NO_AUTO_UPDATE=1 brew outdated --formula --quiet 2>/dev/null) || true
    brew_targets=()
    for _b_pkg in fzf fd bat eza zoxide yazi neovim fastfetch lazydocker lazygit vfox zsh git tmux television tre-command tre ripgrep jq poppler sevenzip resvg ffmpeg-full imagemagick-full ffmpeg imagemagick; do
      if printf '%s\n' "${brew_outdated:-}" | grep -qFx "$_b_pkg"; then
        brew_targets+=("$_b_pkg")
      fi
    done
    for _b_target in ${brew_targets[@]+"${brew_targets[@]}"}; do
      info "$(msg "正在升级 Homebrew 软件包: $_b_target ..." "Upgrading Homebrew package: $_b_target ...")"
      if HOMEBREW_NO_AUTO_UPDATE=1 brew upgrade "$_b_target" 2>/dev/null; then
        UPDATED_OK+=("Homebrew: $_b_target")
        success "$(msg "$_b_target 升级成功" "$_b_target upgraded successfully")"
      else
        UPDATE_INCOMPLETE=1
        UPDATED_FAIL+=("Homebrew: $_b_target | $(msg "升级失败" "Upgrade failed") | brew upgrade $_b_target")
        warn "$(msg "$_b_target 升级失败" "$_b_target upgrade failed")"
      fi
    done
  elif [[ "$OS_TYPE" == Linux ]]; then
    if command -v apt-get >/dev/null 2>&1; then
      info "$(msg "提示：如需升级 Linux 系统包，可运行: sudo apt update && sudo apt --only-upgrade install <包名>" "Tip: To upgrade Linux system packages, run: sudo apt update && sudo apt --only-upgrade install <pkg>")"
    elif command -v dnf >/dev/null 2>&1; then
      info "$(msg "提示：如需升级 Linux 系统包，可运行: sudo dnf upgrade <包名>" "Tip: To upgrade Linux system packages, run: sudo dnf upgrade <pkg>")"
    fi
  fi

  # 智能同步缓存：将成功更新的组件从 available_updates 清单中剔除
  if [[ -f "$AVAILABLE_FILE" ]] && ((${#UPDATED_OK[@]} > 0)); then
    tmp_avail=$(mktemp "$AVAILABLE_FILE.tmp.XXXXXX")
    while IFS= read -r a_line || [[ -n "$a_line" ]]; do
      matched=0
      for ok_item in "${UPDATED_OK[@]}"; do
        match_target="$ok_item"
        [[ "$match_target" == "Homebrew: "* ]] && match_target="${match_target#Homebrew: }"
        if [[ "$a_line" == *"$match_target"* ]]; then
          matched=1
          break
        fi
      done
      ((matched == 0)) && printf '%s\n' "$a_line" >> "$tmp_avail"
    done < "$AVAILABLE_FILE"
    mv "$tmp_avail" "$AVAILABLE_FILE"
  fi

  if [[ -f "$HOME/.zshrc" ]]; then
    zsh -n "$HOME/.zshrc" && success "$(msg "配置语法检查通过。" "Configuration syntax check passed.")"
  fi

  # 输出格式化升级结果汇总卡
  echo ""
  echo "============================================================"
  printf '        \033[1;34m%s\033[0m\n' "$(msg "📋 组件升级结果汇总" "📋 Component Update Summary")"
  echo "============================================================"
  if ((${#UPDATED_OK[@]} > 0)); then
    printf '\033[1;32m%s (%d):\033[0m\n' "$(msg "✅ 升级成功" "✅ Successfully Updated")" "${#UPDATED_OK[@]}"
    for item in "${UPDATED_OK[@]}"; do
      printf '  \033[32m✔\033[0m %s\n' "$item"
    done
    echo ""
  fi

  if ((${#UPDATED_SKIP[@]} > 0)); then
    printf '\033[1;33m%s (%d):\033[0m\n' "$(msg "⚠ 跳过升级" "⚠ Skipped Updates")" "${#UPDATED_SKIP[@]}"
    for item in "${UPDATED_SKIP[@]}"; do
      s_name="${item%% | *}"
      s_act="${item#* | }"
      printf '  \033[33m•\033[0m %s\n' "$s_name"
      [[ "$s_act" != "$item" ]] && printf '    \033[36m👉 %s\033[0m\n' "$s_act"
    done
    echo ""
  fi

  if ((${#UPDATED_FAIL[@]} > 0)); then
    printf '\033[1;31m%s (%d):\033[0m\n' "$(msg "❌ 升级失败 (可单独处理)" "❌ Failed Updates (Action Required)")" "${#UPDATED_FAIL[@]}"
    for item in "${UPDATED_FAIL[@]}"; do
      f_name="${item%% | *}"
      rest="${item#* | }"
      f_reason="${rest%% | *}"
      f_act="${rest#* | }"
      printf '  \033[31m✖\033[0m \033[1m%s\033[0m (%s)\n' "$f_name" "$f_reason"
      [[ "$f_act" != "$rest" ]] && printf '    \033[36m👉 %s\033[0m\n' "$f_act"
    done
    echo ""
  fi

  printf '\033[1;35m%s\033[0m\n' "$(msg "💡 单独处理与重试指引:" "💡 Individual Component Action Guide:")"
  printf '  • %s: \033[33mbash install.sh --retry-failed [组件名]\033[0m\n' "$(msg "独立包重试安装" "Retry individual package")"
  printf '  • %s: \033[33mbash install.sh --doctor\033[0m\n' "$(msg "环境只读健康体检" "Read-only health check")"
  echo "============================================================"

  if ((UPDATE_INCOMPLETE)) || [[ -s "$AVAILABLE_FILE" ]]; then
    warn "$(msg "部分组件未完成更新，未成功的项目已保留在提醒列表中，可通过上述提示单独处理。" "Some components were not updated; pending items remain in notice list.")"
    exit 1
  fi
  success "$(msg "所有待更新组件均已完成更新！请新开终端验证。" "All components updated successfully! Please open a new terminal to verify.")"
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

# ==============================================================================
# 4. 配置回退恢复逻辑 (Rollback & Restore)
# ==============================================================================
# 设计原则与防御性检查：
# 1. 归属权校验：读取 manifest 文件，确保备份目录属于当前 $HOME，严防多用户/跨系统误操作；
# 2. 状态与哈希双重比对：
#    对受管文件（.zshrc、.zsh-project-options、.p10k.zsh、.tmux.conf）校验其 .state（present/absent）
#    以及 .sha256 哈希值。如果安装后用户又手动修改了配置，哈希比对会识别出变动并主动拒绝恢复，
#    避免粗暴覆盖用户的最新修改；
# 3. 字节码失效清理：恢复配置后立即清理残留的 .zwc 编译文件，防止 Zsh 运行时继续执行旧配置。
restore() {
  local dir=$1 file expected actual
  [[ -d "$dir" && ! -L "$dir" && -f "$dir/manifest" ]] || die "$(msg '备份目录或清单不存在' 'Backup directory or manifest does not exist')"
  [[ $(head -n 1 "$dir/manifest") == "$HOME" ]] || die "$(msg '备份不属于当前 HOME' 'Backup does not belong to current HOME')"
  local managed_files=(.zshrc .zsh-project-options)
  [[ -f "$dir/.tmux.conf.state" ]] && managed_files+=(.tmux.conf)
  [[ -f "$dir/.p10k.zsh.state" ]] && managed_files+=(.p10k.zsh)
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
  command rm -f -- "$HOME/.zshrc.zwc" "$HOME/.zshenv.zwc" "$HOME/.zprofile.zwc" "$HOME/.p10k.zsh.zwc" 2>/dev/null || true
  success "$(msg '配置已恢复。请新开终端验证。' 'Configuration restored. Please open a new terminal session to verify.')"
}

if [[ -n "$ROLLBACK" ]]; then
  ((DRY_RUN)) || [[ -t 0 ]] || die "$(msg '恢复需要交互终端' 'Rollback requires an interactive terminal')"
  restore "$ROLLBACK"
  exit 0
fi

# ==============================================================================
# 5. 包管理器自动识别与适配 (Package Manager Detection)
# ==============================================================================
# 兼容 macOS 及各大主流 Linux 发行版体系：
# - macOS: 优先检测系统已有 brew，自动映射 Apple Silicon (/opt/homebrew) 与 Intel (/usr/local)；
# - Linux: 读取 /etc/os-release，映射至四大包管理器家族：
#   * apt: Debian, Ubuntu, Linux Mint, Kali Linux, Pop!_OS, Deepin, UOS, Kylin 等
#   * dnf/yum: Fedora, Red Hat Enterprise Linux, CentOS, Rocky Linux, AlmaLinux, Amazon Linux 等
#   * pacman: Arch Linux, Manjaro, EndeavourOS, Artix, Garuda 等
#   * zypper: openSUSE Leap, openSUSE Tumbleweed, SUSE Enterprise 等
FAMILY=""
if [[ "$OS" == Darwin ]]; then
  # macOS Homebrew 识别与环境变量初始化
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
    ID_LOWER="${ID:-}"
    ID_LIKE_LOWER="${ID_LIKE:-}"
    for _distro_token in $ID_LOWER $ID_LIKE_LOWER; do
      case "$_distro_token" in
        debian|ubuntu|mint|kali|pop|raspbian|deepin|uos|kylin) FAMILY=apt; break ;;
        fedora|rhel|centos|rocky|almalinux|alma|ol|amzn) FAMILY=dnf; break ;;
        arch|manjaro|endeavouros|artix|garuda) FAMILY=pacman; break ;;
        opensuse*|suse|sles) FAMILY=zypper; break ;;
      esac
    done
    if [[ -z "${FAMILY:-}" ]]; then
      case "$ID_LOWER $ID_LIKE_LOWER" in
        *debian*|*ubuntu*|*mint*|*kali*|*pop*|*raspbian*|*deepin*|*uos*|*kylin*) FAMILY=apt ;;
        *fedora*|*rhel*|*centos*|*rocky*|*almalinux*|*amzn*) FAMILY=dnf ;;
        *arch*|*manjaro*|*endeavouros*|*artix*|*garuda*) FAMILY=pacman ;;
        *opensuse*|*suse*) FAMILY=zypper ;;
        *)
          if command -v apt-get >/dev/null 2>&1; then FAMILY=apt;
          elif command -v dnf >/dev/null 2>&1 || command -v yum >/dev/null 2>&1; then FAMILY=dnf;
          elif command -v pacman >/dev/null 2>&1; then FAMILY=pacman;
          elif command -v zypper >/dev/null 2>&1; then FAMILY=zypper;
          else die "$(msg "暂不自动支持发行版：${ID:-未知系统}；请参考教程手动安装" "Distribution not automatically supported: ${ID:-unknown}; refer to manual guide")"; fi
          ;;
      esac
    fi
  elif ((DRY_RUN)); then
    FAMILY=apt
    info "$(msg "[预演模式] 未找到 /etc/os-release，默认模拟 apt 发行版" "[Dry Run] /etc/os-release not found; simulating apt distribution")"
  else
    if command -v apt-get >/dev/null 2>&1; then FAMILY=apt;
    elif command -v dnf >/dev/null 2>&1 || command -v yum >/dev/null 2>&1; then FAMILY=dnf;
    elif command -v pacman >/dev/null 2>&1; then FAMILY=pacman;
    elif command -v zypper >/dev/null 2>&1; then FAMILY=zypper;
    else die "$(msg '缺少 /etc/os-release 且未探测到主流包管理器' 'Missing /etc/os-release and no supported package manager found')"; fi
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
  # 若无 git 或 clone 失败，通过 curl/wget 提取必要模板与管理脚本
  if [[ ! -r "$LOCAL_BOOTSTRAP_DIR/templates/zshrc.zsh" ]]; then
    RAW_BASE="https://raw.githubusercontent.com/vicky-clair/xao_Rui_is-one-lick-configuration-script-for-ZSH/main"
    command mkdir -p "$LOCAL_BOOTSTRAP_DIR/templates" "$LOCAL_BOOTSTRAP_DIR/scripts"
    _bootstrap_files=(
      "install.sh"
      "templates/zshrc.zsh"
      "templates/tmux.conf"
      "scripts/manage.sh"
      "scripts/retry_tools.sh"
      "scripts/check_updates.sh"
    )
    for _bf in "${_bootstrap_files[@]}"; do
      if command -v curl >/dev/null 2>&1; then
        command curl -fsSL --connect-timeout 10 -m 30 "$RAW_BASE/$_bf" -o "$LOCAL_BOOTSTRAP_DIR/$_bf" 2>/dev/null || true
      elif command -v wget >/dev/null 2>&1; then
        command wget -T 30 -qO "$LOCAL_BOOTSTRAP_DIR/$_bf" "$RAW_BASE/$_bf" 2>/dev/null || true
      fi
    done
    command chmod +x "$LOCAL_BOOTSTRAP_DIR/install.sh" "$LOCAL_BOOTSTRAP_DIR/scripts"/*.sh 2>/dev/null || true
  fi
  if [[ -r "$LOCAL_BOOTSTRAP_DIR/templates/zshrc.zsh" ]]; then
    SCRIPT_DIR="$LOCAL_BOOTSTRAP_DIR"
    success "$(msg "项目资源自举成功" "Repository bootstrapped successfully")"
  else
    die "$(msg '缺少 templates/zshrc.zsh，且自动下载失败，请检查网络或克隆完整仓库' 'templates/zshrc.zsh missing and auto-download failed; please check network or clone repository')"
  fi
fi

if [[ -e "$HOME/.oh-my-zsh" && ! -r "$HOME/.oh-my-zsh/oh-my-zsh.sh" ]]; then
  die "$(msg '现有 OMZ 不完整；请按排查文档恢复，安装器不会覆盖 custom 或移动现有目录' 'Existing OMZ is incomplete; please recover per documentation') "
fi

# 6. 收集用户选项
if ((!DRY_RUN)); then
  [[ -t 0 ]] || ((ASSUME_YES)) || die "$(msg '安装需要交互终端；查看计划请用 --dry-run，自动化测试请用 --yes' 'Installation requires interactive terminal; use --dry-run to view plan or --yes for non-interactive') "
  if ((!PROFILE_SET)); then
    if ((ASSUME_YES)); then
      # 显式非交互模式且未指定 profile 时，默认保持 basic
      :
    elif ask "$(msg '是否选择完整工具集？选 N 安装基础主题、补全、高亮和建议' 'Install full CLI toolchain? Select N for basic theme, completions, and suggestions')"; then
      PROFILE=full
    fi
  fi
  if ((!P10K_STYLE_SET)); then
    if ((ASSUME_YES)); then
      P10K_STYLE="rainbow"
    else
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
  fi
  ((WITH_VFOX)) || { if command -v vfox >/dev/null 2>&1; then WITH_VFOX=1; elif ((!ASSUME_YES)) && ask "$(msg '是否启用 vfox 版本管理（自动目录钩子默认关闭）？' 'Enable vfox version manager (auto directory hook disabled by default)?')"; then WITH_VFOX=1; fi; }
  ((WITH_LAZYDOCKER)) || { if command -v lazydocker >/dev/null 2>&1; then WITH_LAZYDOCKER=1; elif ((!ASSUME_YES)) && ask "$(msg '是否安装 lazydocker 容器终端管理（不配置 Docker）？' 'Install lazydocker container UI (Docker daemon not configured)?')"; then WITH_LAZYDOCKER=1; fi; }
  ((WITH_LAZYGIT)) || { if command -v lazygit >/dev/null 2>&1; then WITH_LAZYGIT=1; elif ((!ASSUME_YES)) && ask "$(msg '是否安装 lazygit Git 终端管理面板？' 'Install lazygit Git TUI panel?')"; then WITH_LAZYGIT=1; fi; }
  ((WITHOUT_TMUX)) || ((WITH_TMUX)) || { if command -v tmux >/dev/null 2>&1; then WITH_TMUX=1; elif ((!ASSUME_YES)) && ask "$(msg '是否安装并配置 tmux 终端复用器（含全平台剪贴板互通与美化主题）？' 'Install and configure tmux terminal multiplexer (with clipboard & themes)?')"; then WITH_TMUX=1; fi; }
fi

# 选项收集完成后生成同一份清单，供检查、备份、部署校验和回退使用。
target_files=(.zshrc .zsh-project-options)
if ((WITH_TMUX)); then
  [[ -r "$SCRIPT_DIR/templates/tmux.conf" ]] || die '缺少 templates/tmux.conf'
  target_files+=(.tmux.conf)
fi
[[ "$P10K_STYLE" == skip ]] || target_files+=(.p10k.zsh)
for file in "${target_files[@]}"; do
  [[ ! -L "$HOME/$file" && ! -d "$HOME/$file" ]] || die "$file 是链接或目录，请手动处理"
  [[ ! -e "$HOME/$file" || -f "$HOME/$file" ]] || die "$file 不是普通文件"
done

printf '\n%s: %s; %s: %s; %s: %s; %s: %s\n' \
  "$(msg '系统' 'OS')" "${PRETTY_NAME:-$OS}" \
  "$(msg '架构' 'Arch')" "$ARCH" \
  "$(msg '包管理器' 'Package Manager')" "$FAMILY" \
  "$(msg '用户' 'User')" "$(id -un)"
printf '%s: %s; %s: %s; vfox: %s; lazydocker: %s; lazygit: %s; tmux: %s; %s: %s\n' \
  "$(msg '安装类型' 'Profile')" "$PROFILE" \
  "$(msg 'P10k主题' 'P10k Style')" "$P10K_STYLE" \
  "$WITH_VFOX" "$WITH_LAZYDOCKER" "$WITH_LAZYGIT" "$WITH_TMUX" \
  "$(msg '语言' 'Language')" "$LANG_CHOICE"
case "$P10K_STYLE" in
  rainbow) printf '%s\n' "$(msg '主题配置：经典彩虹流线双行主题（Rainbow，开箱即用）。' 'Prompt config: Classic rainbow theme (Rainbow, ready-to-use).')" ;;
  lean) printf '%s\n' "$(msg '主题配置：现代极简纯净主题（Lean，简约高效）。' 'Prompt config: Lean minimalist pure theme (Lean, clean & fast).')" ;;
  classic) printf '%s\n' "$(msg '主题配置：经典传统流线主题（Classic，传统箭头）。' 'Prompt config: Classic flow theme (Classic, traditional arrows).')" ;;
  wizard) printf '%s\n' "$(msg '主题配置：安装完成后自动唤起 p10k configure 官方配置向导。' 'Prompt config: Automatically launch p10k configure wizard after install.')" ;;
  skip) printf '%s\n' "$(msg '主题配置：保持原有设置，不覆盖 ~/.p10k.zsh。' 'Prompt config: Keep existing setup, do not touch ~/.p10k.zsh.')" ;;
esac
printf '%s\n' "$(msg '基础依赖：zsh git curl ca-certificates coreutils unzip tar file；OMZ、Powerlevel10k、三个 Zsh 核心插件。' 'Base dependencies: zsh, git, curl, ca-certificates, coreutils, unzip, tar, file; OMZ, Powerlevel10k, 3 core plugins.')"
[[ "$PROFILE" == full ]] && printf '%s\n' "$(msg '完整工具：fzf fd bat eza zoxide yazi neovim fastfetch television tre agrep 及 Yazi 预览依赖（ripgrep jq ffmpeg 7-zip poppler imagemagick 等，仓库没有则跳过并记录）。' 'Full tools: fzf, fd, bat, eza, zoxide, yazi, neovim, fastfetch, television, tre, agrep and Yazi preview dependencies (ripgrep, jq, ffmpeg, 7-zip, poppler, imagemagick; skipped if unavailable in repository).')"
((WITH_TMUX)) && printf '%s\n' "$(msg 'Tmux 增强：安装 tmux、终端剪贴板工具、TPM 插件生态并部署 ~/.tmux.conf。' 'Tmux enhancement: install tmux, clipboard tools, TPM plugins, and ~/.tmux.conf.')"
printf '%s\n' "$(msg '备份并更新受管配置；选定主题样式会备份并替换 .p10k.zsh，skip 则保留。保留 .zshenv、custom 和历史。' 'Back up managed configs; theme selection replaces .p10k.zsh after backup; skip preserves it. Keep .zshenv, custom and history.')"
printf '%s\n' "$(msg '默认 Shell 将在配置安装成功后单独询问。' 'Default login shell will be prompted separately after configuration.')"
[[ "$FAMILY" == pacman ]] && printf '%s\n' "$(msg '系统维护：Arch Linux 滚动架构下，若缺失基础核心依赖将执行 pacman -Syu 同步升级。' 'System maintenance: On Arch Linux, missing core dependencies will trigger pacman -Syu.')"

if ((DRY_RUN)); then
  printf '\n%s\n' "$(msg '预演结束。实际可用包将在确认安装后通过本机仓库检测。' 'Dry run finished. Available packages will be checked via local repositories upon confirmation.')"
  exit 0
fi

echo ""
ask "$(msg '确认按以上计划安装并替换配置？' 'Confirm installation and replace configuration according to plan?')" || exit 0

# 权限与基础核心依赖前置检测（幂等性、按需提权与零冗余开销保障）
base_missing=()
if [[ "$FAMILY" == brew ]]; then
  command -v gtimeout >/dev/null 2>&1 || base_missing+=(coreutils)
  for _base_cmd in zsh git curl unzip file; do
    command -v "$_base_cmd" >/dev/null 2>&1 || base_missing+=("$_base_cmd")
  done
  command -v tar >/dev/null 2>&1 || base_missing+=(gnu-tar)
else
  for _base_cmd in zsh git curl unzip tar file; do
    command -v "$_base_cmd" >/dev/null 2>&1 || base_missing+=("$_base_cmd")
  done

  # 动态评估是否需要管理员提权（sudo）：
  # 1. 存在缺失的基础核心包（base_missing > 0）
  # 2. 用户选定完整工具链（PROFILE == full，后续需安装系统包）
  # 3. 用户启用了 tmux 但系统中尚未安装 tmux
  needs_elevation=0
  if ((${#base_missing[@]} > 0)); then
    needs_elevation=1
  elif [[ "$PROFILE" == full ]]; then
    needs_elevation=1
  elif ((WITH_TMUX)) && ! command -v tmux >/dev/null 2>&1; then
    needs_elevation=1
  fi

  if ((needs_elevation)); then
    # 若当前已是 root 用户（例如在 Docker 容器中直接执行），无需依赖 sudo
    if [[ "${EUID:-$(id -u 2>/dev/null || echo 1)}" -ne 0 ]]; then
      command -v sudo >/dev/null || die "$(msg '缺少 sudo，请先由管理员安装依赖' 'Missing sudo; please ask administrator to install dependencies')"
      sudo -v
    fi
  elif sudo -n true 2>/dev/null; then
    # 纯配置模式且已有免密凭据时，顺带刷新，确保后续可选微调安全执行
    sudo -v 2>/dev/null || true
  fi
fi

STATE_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}/zsh-project"
mkdir -p "$STATE_ROOT"
BACKUP=$(mktemp -d "$STATE_ROOT/install-XXXXXXXX")
chmod 700 "$BACKUP"
exec 3>&1 4>&2
exec > >(tee -a "$BACKUP/install.log") 2>&1
trap 'printf "安装未完成。日志与原配置：%s\n系统软件安装不会自动回退。\n" "$BACKUP" >&2' ERR

printf '%s\n' "$HOME" > "$BACKUP/manifest"
backup_files=("${target_files[@]}")
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
    # Homebrew 核心依赖：探测缺失组件，使用 gnu-tar 替代系统中无此 formula 的 tar
    export HOMEBREW_NO_AUTO_UPDATE=1
    if ((${#base_missing[@]} > 0)); then
      brew install "${base_missing[@]}"
    fi
    ;;
  apt)
    if ((${#base_missing[@]} > 0)); then
      sudo apt-get update || true
      sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${base_missing[@]}" ca-certificates ncurses-term x11-utils 2>/dev/null || \
      sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${base_missing[@]}" ca-certificates ncurses-term
    else
      success "$(msg "基础核心依赖已全部就绪，无需重复调用包管理器。" "All core base dependencies already installed, skipping redundant apt install.")"
    fi
    ;;
  dnf)
    if ((${#base_missing[@]} > 0)); then
      if command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y "${base_missing[@]}" ca-certificates
      else
        sudo yum install -y "${base_missing[@]}" ca-certificates
      fi
    else
      success "$(msg "基础核心依赖已全部就绪，无需重复调用包管理器。" "All core base dependencies already installed.")"
    fi
    ;;
  pacman)
    if ((${#base_missing[@]} > 0)); then
      sudo pacman -Syu --needed --noconfirm "${base_missing[@]}" ca-certificates
    else
      success "$(msg "基础核心依赖已全部就绪，无需重复调用包管理器。" "All core base dependencies already installed.")"
    fi
    ;;
  zypper)
    if ((${#base_missing[@]} > 0)); then
      sudo zypper install -y "${base_missing[@]}" ca-certificates
    else
      success "$(msg "基础核心依赖已全部就绪，无需重复调用包管理器。" "All core base dependencies already installed.")"
    fi
    ;;
esac

# 辅助函数：从已跳过列表中移除（用于回退安装成功后剔除，兼容 Bash 3.2 set -u 空数组）
remove_skipped() {
  local target=$1
  local updated=()
  for item in ${SKIPPED[@]+"${SKIPPED[@]}"}; do
    [[ "$item" != "$target" ]] && updated+=("$item")
  done
  SKIPPED=(${updated[@]+"${updated[@]}"})
}

mkdir -p "$HOME/.local/bin"
# 确保常用路径与 Homebrew 在 PATH 中
if [[ -z "${ZSH_PROJECT_TEST_MARKER:-${AUDIT_MARKER:-}}" ]]; then
  _EXTRA_PATHS="$HOME/.local/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:/opt/nvim:$HOME/go/bin:$HOME/.cargo/bin:$HOME/.local/share/pnpm:$HOME/.version-fox/sdks/golang/packages/bin"
  export PATH="$_EXTRA_PATHS:$PATH"
  unset _EXTRA_PATHS
else
  export PATH="$HOME/.local/bin:$PATH"
fi

# 辅助函数：检测系统或用户目录是否已安装 Nerd Font
has_nerd_font() {
  if command -v fc-list >/dev/null 2>&1; then
    if fc-list : family 2>/dev/null | grep -qiE 'nerd font|nerdfont'; then
      return 0
    fi
  fi
  local font_dir
  for font_dir in "$HOME/.local/share/fonts" "$HOME/.fonts" "/usr/share/fonts" "/usr/local/share/fonts" "$HOME/Library/Fonts" "/Library/Fonts"; do
    if [[ -d "$font_dir" ]] && find "$font_dir" -maxdepth 3 \( -iname "*nerdfont*" -o -iname "*nerd font*" -o -iname "*symbols*nerd*" \) 2>/dev/null | head -n 1 | grep -q .; then
      return 0
    fi
  done
  return 1
}

# ==============================================================================
# 可选软件包安装函数：实现严格幂等性检查（Idempotency）与多别名自动识别
# ==============================================================================
# 设计原则：
# 1. 目标命令或发行版特定别名（如 Debian 的 fdfind/batcat、Arch 的 7zz）只要存在，立即返回 0；
# 2. 杜绝任何多余、重复的包管理器调用（避免耗时 apt/dnf/pacman 网络事务）；
# 3. 若包管理器仓库中确实无此包，将其记录到 SKIPPED 数组并提示跳过，不阻断主流程。
optional_package() {
  local cmd=$1 pkg=$2

  # 1. 基础命令存在性检查：若已有目标命令，直接跳过安装
  [[ -n "$cmd" ]] && command -v "$cmd" >/dev/null 2>&1 && return 0

  # 2. 发行版专用命令别名检测（避免因二进制名不同而触发重复安装）：
  # - fd 在 Debian/Ubuntu/Fedora 系统下包名/二进制为 fdfind
  if [[ "$cmd" == fd ]] && command -v fdfind >/dev/null 2>&1; then return 0; fi
  # - bat 在 Debian/Ubuntu 下为避免与现有工具冲突改名为 batcat
  if [[ "$cmd" == bat ]] && command -v batcat >/dev/null 2>&1; then return 0; fi
  # - agrep 在 Debian/Ubuntu 下由 tre-agrep 提供
  if [[ "$cmd" == agrep ]] && command -v tre-agrep >/dev/null 2>&1; then return 0; fi
  # - 7-Zip 在 Arch 等系统中二进制名称为 7zz 或 7z
  if [[ "$cmd" == 7z ]] && command -v 7zz >/dev/null 2>&1; then return 0; fi
  # - ImageMagick v7 二进制为 magick，v6 或传统系统为 convert
  if [[ "$cmd" == magick ]] && command -v convert >/dev/null 2>&1; then return 0; fi
  # - ripgrep 在某些发行版中别名为 rg 或 ripgrep
  if [[ "$cmd" == rg ]] && command -v ripgrep >/dev/null 2>&1; then return 0; fi
  # - Linux 剪贴板驱动（wl-copy、xclip、xsel）：三者只要任意一个可用即视为满足要求
  if [[ "$cmd" == xclip || "$cmd" == wl-copy || "$cmd" == xsel ]]; then
    if command -v wl-copy >/dev/null 2>&1 || command -v xclip >/dev/null 2>&1 || command -v xsel >/dev/null 2>&1; then
      return 0
    fi
  fi

  # 3. 按不同包管理器家族执行安装（仅在检测到缺失时调用）
  case "$FAMILY" in
    brew)
      if HOMEBREW_NO_AUTO_UPDATE=1 brew install "$pkg"; then
        return 0
      fi
      ;;
    apt)
      # 预检软件包是否存在于 apt 缓存中，并强制非交互式防止 debconf 挂起
      if apt-cache show "$pkg" >/dev/null 2>&1 || apt-get install -s -qq "$pkg" >/dev/null 2>&1; then
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg" && return 0
      fi
      ;;
    dnf)
      if command -v dnf >/dev/null 2>&1; then
        if dnf -q info --available "$pkg" >/dev/null 2>&1; then
          sudo dnf install -y "$pkg" && return 0
        fi
      elif command -v yum >/dev/null 2>&1; then
        if yum info "$pkg" >/dev/null 2>&1; then
          sudo yum install -y "$pkg" && return 0
        fi
      fi
      ;;
    pacman)
      # pacman 使用 --needed 标志，如果包已最新则自动跳过
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

  # 4. 仓库中无此包时安全记录并警告，保持向后兼容
  SKIPPED+=("$pkg")
  warn "$(msg "可选包未在仓库中找到：$pkg，已跳过安装。" "Optional package not found in repository: $pkg, skipped.")"
  return 1
}

# 8. 安装完整工具集
if [[ "$PROFILE" == full ]]; then
  info "$(msg "正在安装完整工具集..." "Installing full modern CLI toolchain...")"

  # ============================================================================
  # Homebrew (macOS)：针对 Yazi 官方指南推荐的伴生依赖套件进行预检与批量部署
  # 参见 Yazi 官方安装文档：https://yazi-rs.github.io/docs/installation/
  # ============================================================================
  if [[ "$FAMILY" == brew ]]; then
    brew_missing=()
    # 逐一核验 12 项组件是否已安装；仅把系统中真正缺失的项加入 brew_missing 数组
    command -v yazi >/dev/null 2>&1 || brew_missing+=(yazi)
    command -v ffmpeg >/dev/null 2>&1 || brew_missing+=(ffmpeg-full)
    (command -v 7z >/dev/null 2>&1 || command -v 7zz >/dev/null 2>&1) || brew_missing+=(sevenzip)
    command -v jq >/dev/null 2>&1 || brew_missing+=(jq)
    command -v pdftoppm >/dev/null 2>&1 || brew_missing+=(poppler)
    (command -v fd >/dev/null 2>&1 || command -v fdfind >/dev/null 2>&1) || brew_missing+=(fd)
    (command -v rg >/dev/null 2>&1 || command -v ripgrep >/dev/null 2>&1) || brew_missing+=(ripgrep)
    command -v fzf >/dev/null 2>&1 || brew_missing+=(fzf)
    command -v zoxide >/dev/null 2>&1 || brew_missing+=(zoxide)
    command -v resvg >/dev/null 2>&1 || brew_missing+=(resvg)
    (command -v magick >/dev/null 2>&1 || command -v convert >/dev/null 2>&1) || brew_missing+=(imagemagick-full)
    has_nerd_font || brew_missing+=(font-symbols-only-nerd-font)

    # 严格幂等：若所有组件均已安装，完全不执行 brew install，杜绝重复操作
    if ((${#brew_missing[@]} > 0)); then
      info "$(msg "检测到缺失的工具/伴生依赖: ${brew_missing[*]}，正在通过 Homebrew 安装..." "Missing tools/dependencies detected: ${brew_missing[*]}; installing via Homebrew...")"
      HOMEBREW_NO_AUTO_UPDATE=1 brew install "${brew_missing[@]}" 2>/dev/null || {
        # 批量安装失败时，降级为逐个尝试安装并自动回退（如 ffmpeg-full -> ffmpeg）
        for _y_pkg in "${brew_missing[@]}"; do
          if [[ "$_y_pkg" == ffmpeg-full ]]; then
            HOMEBREW_NO_AUTO_UPDATE=1 brew install ffmpeg-full 2>/dev/null || HOMEBREW_NO_AUTO_UPDATE=1 brew install ffmpeg 2>/dev/null || true
          elif [[ "$_y_pkg" == imagemagick-full ]]; then
            HOMEBREW_NO_AUTO_UPDATE=1 brew install imagemagick-full 2>/dev/null || HOMEBREW_NO_AUTO_UPDATE=1 brew install imagemagick 2>/dev/null || true
          elif [[ "$_y_pkg" == font-symbols-only-nerd-font ]]; then
            HOMEBREW_NO_AUTO_UPDATE=1 brew install font-symbols-only-nerd-font 2>/dev/null || HOMEBREW_NO_AUTO_UPDATE=1 brew install --cask font-symbols-only-nerd-font 2>/dev/null || true
          else
            optional_package "$_y_pkg" "$_y_pkg" || true
          fi
        done
      }
      # 强制链接带完整扩展格式支持的 ffmpeg 与 imagemagick
      HOMEBREW_NO_AUTO_UPDATE=1 brew link ffmpeg-full imagemagick-full -f --overwrite 2>/dev/null || true
    else
      success "$(msg "Yazi 及其全部推荐伴生依赖已安装，跳过重复安装。" "Yazi and all companion dependencies already installed; skipping redundant install.")"
    fi
  fi

  fd_pkg=fd
  [[ "$FAMILY" == apt || "$FAMILY" == dnf || "$FAMILY" == zypper ]] && fd_pkg=fd-find

  # ----------------------------------------------------------------------------
  # 基础现代命令行工具集：仅在未安装时通过包管理器部署
  # ----------------------------------------------------------------------------
  optional_package fzf fzf || true
  optional_package fd "$fd_pkg" || true
  optional_package bat bat || true
  for pkg in eza zoxide yazi fastfetch; do
    optional_package "$pkg" "$pkg" || true
  done
  optional_package nvim neovim || true
  optional_package tv television || true
  optional_package tre tre-command || true
  agrep_pkg=tre
  [[ "$FAMILY" == apt ]] && agrep_pkg=tre-agrep
  optional_package agrep "$agrep_pkg" || true

  # ============================================================================
  # Yazi 现代多媒体预览套件（依照 Yazi 官方指南要求，已有任意工具则自动跳过）
  # 参见：https://yazi-rs.github.io/docs/installation/
  # ============================================================================

  # 1. 文本搜索与 JSON 语法格式化预览
  optional_package rg ripgrep || true
  optional_package jq jq || true

  # 2. 视频与多媒体缩略图提取核心依赖
  optional_package ffmpeg ffmpeg || true

  # 3. 归档文件（zip/tar/7z/rar/iso 等）解压与目录树内联预览
  # 检查 7z 或 7zz 命令是否存在；缺失时按发行版优先级尝试安装
  if ! command -v 7z >/dev/null 2>&1 && ! command -v 7zz >/dev/null 2>&1; then
    case "$FAMILY" in
      brew)
        optional_package 7z sevenzip || true
        ;;
      apt)
        # Debian/Ubuntu 优先安装新版 7zip，若无此包则自动回退安装 p7zip-full
        if ! optional_package 7z 7zip; then
          if optional_package 7z p7zip-full; then
            remove_skipped 7zip
          fi
        fi
        ;;
      dnf)
        # Fedora/RHEL 优先 7zip，次选 p7zip
        if ! optional_package 7z 7zip; then
          if optional_package 7z p7zip; then
            remove_skipped 7zip
          fi
        fi
        ;;
      pacman)
        optional_package 7z 7zip || true
        ;;
      zypper)
        if ! optional_package 7z 7zip; then
          if optional_package 7z p7zip; then
            remove_skipped 7zip
          fi
        fi
        ;;
    esac
  fi

  # 4. Poppler (pdftoppm)：支持 PDF 文档封面高分辨率抽取与预览
  if ! command -v pdftoppm >/dev/null 2>&1; then
    case "$FAMILY" in
      brew)
        optional_package pdftoppm poppler || true
        ;;
      apt|dnf)
        optional_package pdftoppm poppler-utils || true
        ;;
      pacman)
        optional_package pdftoppm poppler || true
        ;;
      zypper)
        if ! optional_package pdftoppm poppler-tools; then
          if optional_package pdftoppm poppler-utils; then
            remove_skipped poppler-tools
          fi
        fi
        ;;
    esac
  fi

  # 5. ImageMagick (magick/convert)：支持字体文件预览、HEIC 苹果照片及 JPEG XL 高级格式
  if ! command -v magick >/dev/null 2>&1 && ! command -v convert >/dev/null 2>&1; then
    case "$FAMILY" in
      brew)
        optional_package magick imagemagick-full || optional_package magick imagemagick || true
        ;;
      apt|pacman)
        optional_package magick imagemagick || true
        ;;
      dnf|zypper)
        optional_package magick ImageMagick || true
        ;;
    esac
  fi

  # 6. resvg：支持 SVG 矢量图形终端栅格化预览
  optional_package resvg resvg || true

  # 7. Linux 终端剪贴板支持（实现 Yazi 文件复制/剪切与系统剪贴板互通）
  if [[ "$FAMILY" == apt || "$FAMILY" == dnf || "$FAMILY" == pacman || "$FAMILY" == zypper ]]; then
    if ! command -v wl-copy >/dev/null 2>&1 && ! command -v xclip >/dev/null 2>&1 && ! command -v xsel >/dev/null 2>&1; then
      info "$(msg "检测到缺少 Linux 剪贴板工具，正在安装 xclip / wl-clipboard..." "Clipboard tool missing on Linux; installing xclip / wl-clipboard...")"
      # 根据当前显示服务（Wayland 或 X11）动态优先选用对应的剪贴板后端
      if [[ "${XDG_SESSION_TYPE:-}" == wayland || -n "${WAYLAND_DISPLAY:-}" ]]; then
        optional_package wl-copy wl-clipboard || optional_package xclip xclip || optional_package xsel xsel || true
      else
        optional_package xclip xclip || optional_package wl-copy wl-clipboard || optional_package xsel xsel || true
      fi
    fi
  fi

  # 8. 图标字体检测与自动部署 (Nerd Fonts)：已有任意 Nerd Font 则立即跳过
  if ! has_nerd_font; then
    if [[ "$FAMILY" == pacman ]]; then
      sudo pacman -S --needed --noconfirm ttf-nerd-fonts-symbols 2>/dev/null || sudo pacman -S --needed --noconfirm ttf-nerd-fonts-symbols-mono 2>/dev/null || true
    elif [[ "$FAMILY" != brew ]]; then
      info "$(msg "未检测到 Nerd Font 图标字体，正在自动安装 Symbols Nerd Font 至 ~/.local/share/fonts/..." "No Nerd Font detected; installing Symbols Nerd Font to ~/.local/share/fonts/...")"
      font_dest="$HOME/.local/share/fonts/NerdFonts"
      mkdir -p "$font_dest"
      if curl -fsSL --connect-timeout 10 -m 60 "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/NerdFontsSymbolsOnly.zip" -o "$font_dest/symbols.zip" 2>/dev/null; then
        if command -v unzip >/dev/null 2>&1; then
          unzip -qo "$font_dest/symbols.zip" -d "$font_dest" 2>/dev/null || true
        elif command -v python3 >/dev/null 2>&1; then
          python3 -c "import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" "$font_dest/symbols.zip" "$font_dest" 2>/dev/null || true
        fi
        rm -f "$font_dest/symbols.zip"
        if command -v fc-cache >/dev/null 2>&1; then
          fc-cache -f "$font_dest" 2>/dev/null || true
        fi
        success "$(msg "Symbols Nerd Font 图标字体安装成功" "Symbols Nerd Font installed successfully")"
      elif curl -fsSL --connect-timeout 10 -m 30 "https://github.com/ryanoasis/nerd-fonts/raw/HEAD/patched-fonts/NerdFontsSymbolsOnly/SymbolsNerdFont-Regular.ttf" -o "$font_dest/SymbolsNerdFont-Regular.ttf" 2>/dev/null; then
        if command -v fc-cache >/dev/null 2>&1; then
          fc-cache -f "$font_dest" 2>/dev/null || true
        fi
        success "$(msg "Symbols Nerd Font 图标字体安装成功" "Symbols Nerd Font installed successfully")"
      fi
    fi
  fi

  # 架构匹配定义
  ARCH_UNAME=$(uname -m 2>/dev/null || echo "$ARCH")
  EZA_ARCH=""
  FF_ARCH=""
  YAZI_ARCH=""
  NVIM_ARCH=""
  TV_ARCH=""
  TRE_ARCH=""
  case "$ARCH_UNAME" in
    x86_64|amd64)
      EZA_ARCH="x86_64"
      FF_ARCH="amd64"
      YAZI_ARCH="x86_64"
      NVIM_ARCH="x86_64"
      TV_ARCH="x86_64"
      TRE_ARCH="x86_64"
      ;;
    aarch64|arm64)
      EZA_ARCH="aarch64"
      FF_ARCH="aarch64"
      YAZI_ARCH="aarch64"
      NVIM_ARCH="arm64"
      TV_ARCH="aarch64"
      TRE_ARCH="aarch64"
      ;;
  esac

  # --- FZF 现代版本保障（针对 Debian 12 等自带旧版 0.38 或残留旧版不支持 fzf --zsh）---
  if ! command -v fzf >/dev/null 2>&1 || ! fzf --zsh >/dev/null 2>&1; then
    if [[ "$FAMILY" == brew ]]; then
      info "$(msg "检测到现有 FZF 缺失或版本过旧，正在通过 Homebrew 安装现代版本..." "FZF missing or outdated; installing modern version via Homebrew...")"
      HOMEBREW_NO_AUTO_UPDATE=1 brew install fzf || HOMEBREW_NO_AUTO_UPDATE=1 brew upgrade fzf || true
      hash -r 2>/dev/null || true
      if command -v fzf >/dev/null 2>&1 && fzf --zsh >/dev/null 2>&1; then
        remove_skipped fzf
      fi
    fi
  fi
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

  # --- EZA 官方预编译二进制自动回退（针对无包管理器或仓库无此包）---
  if ! command -v eza >/dev/null 2>&1 && [[ -n "$EZA_ARCH" ]]; then
    info "$(msg "系统仓库无 eza，正在从 GitHub Release 下载官方预编译二进制至 ~/.local/bin..." "eza not in repo; downloading official binary...")"
    eza_stage=$(mktemp -d "$HOME/.eza-tmp-XXXXXX")
    if [[ "$OS" == Darwin ]]; then
      eza_url="https://github.com/eza-community/eza/releases/latest/download/eza_${EZA_ARCH}-apple-darwin.tar.gz"
    else
      eza_url="https://github.com/eza-community/eza/releases/latest/download/eza_${EZA_ARCH}-unknown-linux-gnu.tar.gz"
    fi
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

  # --- FASTFETCH 官方发布版自动回退（针对无包管理器或仓库无此包）---
  if ! command -v fastfetch >/dev/null 2>&1 && [[ -n "$FF_ARCH" ]]; then
    info "$(msg "系统仓库无 fastfetch，正在从 GitHub Release 下载官方发布版..." "fastfetch not in repo; downloading official release...")"
    ff_stage=$(mktemp -d "$HOME/.ff-tmp-XXXXXX")
    if [[ "$OS" == Darwin ]]; then
      ff_url="https://github.com/fastfetch-cli/fastfetch/releases/latest/download/fastfetch-macos-universal.zip"
      if curl -fsSL --connect-timeout 10 -m 60 "$ff_url" -o "$ff_stage/fastfetch.zip" 2>/dev/null; then
        if command -v unzip >/dev/null 2>&1; then
          unzip -q "$ff_stage/fastfetch.zip" -d "$ff_stage" 2>/dev/null || true
        fi
        ff_bin=$(find "$ff_stage" -type f -name fastfetch -perm -111 2>/dev/null | head -n 1)
        if [[ -n "$ff_bin" && -x "$ff_bin" ]]; then
          mkdir -p "$HOME/.local/bin"
          install -m 755 "$ff_bin" "$HOME/.local/bin/fastfetch"
          success "$(msg "fastfetch 安装成功（位于 ~/.local/bin/fastfetch）" "fastfetch installed successfully (in ~/.local/bin/fastfetch)")"
          remove_skipped fastfetch
        fi
      fi
    else
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
    fi
    rm -rf "$ff_stage"
  fi

  # --- YAZI 官方预编译发布包自动回退（Linux 使用 musl 静态编译版，macOS 使用 darwin 版）---
  if (! command -v yazi >/dev/null 2>&1 || ! yazi --version >/dev/null 2>&1) && [[ -n "$YAZI_ARCH" ]]; then
    info "$(msg "正在从 GitHub Release 下载官方发布版至 ~/.local/bin..." "Downloading official release to ~/.local/bin...")"
    yazi_stage=$(mktemp -d "$HOME/.yazi-tmp-XXXXXX")
    if [[ "$OS" == Darwin ]]; then
      yazi_url="https://github.com/sxyazi/yazi/releases/latest/download/yazi-${YAZI_ARCH}-apple-darwin.zip"
    else
      yazi_url="https://github.com/sxyazi/yazi/releases/latest/download/yazi-${YAZI_ARCH}-unknown-linux-musl.zip"
    fi
    if curl -fsSL --connect-timeout 10 -m 60 "$yazi_url" -o "$yazi_stage/yazi.zip" 2>/dev/null; then
      if command -v unzip >/dev/null 2>&1; then
        unzip -q "$yazi_stage/yazi.zip" -d "$yazi_stage" 2>/dev/null || true
      elif command -v python3 >/dev/null 2>&1; then
        python3 -c "import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" "$yazi_stage/yazi.zip" "$yazi_stage" 2>/dev/null || true
      fi
      yazi_bin=$(find "$yazi_stage" -type f -name yazi -perm -111 2>/dev/null | head -n 1)
      if [[ -n "$yazi_bin" && -x "$yazi_bin" ]]; then
        mkdir -p "$HOME/.local/bin"
        install -m 755 "$yazi_bin" "$HOME/.local/bin/yazi"
        success "$(msg "yazi 安装成功（位于 ~/.local/bin/yazi）" "yazi installed successfully (in ~/.local/bin/yazi)")"
        remove_skipped yazi
      fi
    fi
    rm -rf "$yazi_stage"
  fi

  # --- TELEVISION 官方预编译发布包自动回退 ---
  if ! command -v tv >/dev/null 2>&1 && [[ -n "$TV_ARCH" ]]; then
    info "$(msg "系统仓库无 television，正在从 GitHub Release 下载官方发布版至 ~/.local/bin..." "television not in repo; downloading official release to ~/.local/bin...")"
    tv_stage=$(mktemp -d "$HOME/.tv-tmp-XXXXXX")
    tv_url=$(curl -fsSL --connect-timeout 10 --max-time 30 -o /dev/null -w '%{url_effective}' https://github.com/alexpasmantier/television/releases/latest 2>/dev/null) || true
    tv_tag=${tv_url##*/}
    tv_version=${tv_tag#v}
    if [[ "$tv_tag" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      if [[ "$OS" == Darwin ]]; then
        tv_asset_url="https://github.com/alexpasmantier/television/releases/download/${tv_tag}/tv-${tv_version}-${TV_ARCH}-apple-darwin.tar.gz"
      else
        tv_asset_url="https://github.com/alexpasmantier/television/releases/download/${tv_tag}/tv-${tv_version}-${TV_ARCH}-unknown-linux-musl.tar.gz"
      fi
      if curl -fsSL --connect-timeout 10 -m 60 "$tv_asset_url" -o "$tv_stage/tv.tar.gz" 2>/dev/null || \
         ([[ "$OS" != Darwin ]] && curl -fsSL --connect-timeout 10 -m 60 "https://github.com/alexpasmantier/television/releases/download/${tv_tag}/tv-${tv_version}-${TV_ARCH}-unknown-linux-gnu.tar.gz" -o "$tv_stage/tv.tar.gz" 2>/dev/null); then
        tar -xzf "$tv_stage/tv.tar.gz" -C "$tv_stage" 2>/dev/null || true
        tv_bin=$(find "$tv_stage" -type f -name tv -perm -111 2>/dev/null | head -n 1)
        if [[ -n "$tv_bin" && -x "$tv_bin" ]]; then
          mkdir -p "$HOME/.local/bin"
          install -m 755 "$tv_bin" "$HOME/.local/bin/tv"
          success "$(msg "television (tv) 安装成功（位于 ~/.local/bin/tv）" "television (tv) installed successfully (in ~/.local/bin/tv)")"
          remove_skipped television
          remove_skipped tv
        fi
      fi
    fi
    rm -rf "$tv_stage"
  fi

  # --- TRE (tre-command) 官方预编译发布包自动回退 ---
  if ! command -v tre >/dev/null 2>&1 && [[ -n "$TRE_ARCH" ]]; then
    info "$(msg "系统仓库无 tre-command，正在从 GitHub Release 下载官方发布版至 ~/.local/bin..." "tre-command not in repo; downloading official release to ~/.local/bin...")"
    tre_stage=$(mktemp -d "$HOME/.tre-tmp-XXXXXX")
    tre_url=$(curl -fsSL --connect-timeout 10 --max-time 30 -o /dev/null -w '%{url_effective}' https://github.com/dduan/tre/releases/latest 2>/dev/null) || true
    tre_tag=${tre_url##*/}
    tre_version=${tre_tag#v}
    if [[ "$tre_tag" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      if [[ "$OS" == Darwin ]]; then
        tre_asset_url="https://github.com/dduan/tre/releases/download/${tre_tag}/tre-v${tre_version}-${TRE_ARCH}-apple-darwin.tar.gz"
      else
        tre_asset_url="https://github.com/dduan/tre/releases/download/${tre_tag}/tre-v${tre_version}-${TRE_ARCH}-unknown-linux-musl.tar.gz"
      fi
      if curl -fsSL --connect-timeout 10 -m 60 "$tre_asset_url" -o "$tre_stage/tre.tar.gz" 2>/dev/null; then
        tar -xzf "$tre_stage/tre.tar.gz" -C "$tre_stage" 2>/dev/null || true
        tre_bin=$(find "$tre_stage" -type f -name tre -perm -111 2>/dev/null | head -n 1)
        if [[ -n "$tre_bin" && -x "$tre_bin" ]]; then
          mkdir -p "$HOME/.local/bin"
          install -m 755 "$tre_bin" "$HOME/.local/bin/tre"
          success "$(msg "tre 安装成功（位于 ~/.local/bin/tre）" "tre installed successfully (in ~/.local/bin/tre)")"
          remove_skipped tre-command
          remove_skipped tre
        fi
      fi
    fi
    rm -rf "$tre_stage"
  fi

  # --- NEOVIM 现代版本保障与官方预编译包自动拉取（解决 Debian 12 等官方仓库版本过旧仅为 0.7 的问题）---
  need_nvim_download=0
  if ((WITH_LATEST_NVIM)); then
    need_nvim_download=1
  elif ! command -v nvim >/dev/null 2>&1; then
    need_nvim_download=1
  else
    nvim_v_str=$(nvim --version 2>/dev/null | head -n 1)
    nvim_v_num=$(echo "$nvim_v_str" | grep -oE '[0-9]+\.[0-9]+' | head -n 1 || echo "0.0")
    nvim_major=$(echo "$nvim_v_num" | cut -d. -f1)
    nvim_minor=$(echo "$nvim_v_num" | cut -d. -f2)
    # 若系统现有 Neovim 版本小于 0.10（如 Debian 12 自带的 0.7.2），无法适配现代插件生态，自动从官方升级
    if (( nvim_major == 0 && nvim_minor < 10 )); then
      info "$(msg "检测到系统 Neovim 版本过旧 ($nvim_v_str)，现代 Lua 生态（LazyVim/Treesitter等）通常需要 >= 0.10.0。" "Detected outdated Neovim ($nvim_v_str); modern Lua plugins require >= 0.10.0.")"
      need_nvim_download=1
    fi
  fi

  if (( need_nvim_download )) && [[ -n "$NVIM_ARCH" ]] && [[ "$FAMILY" != brew ]]; then
    info "$(msg "正在从 GitHub Release 下载 Neovim 官方最新稳定版至 ~/.local/opt/nvim..." "Downloading latest official Neovim release from GitHub to ~/.local/opt/nvim...")"
    nvim_stage=$(mktemp -d "$HOME/.nvim-tmp-XXXXXX")
    if [[ "$OS" == Darwin ]]; then
      nvim_url="https://github.com/neovim/neovim/releases/latest/download/nvim-macos-${NVIM_ARCH}.tar.gz"
    else
      nvim_url="https://github.com/neovim/neovim/releases/latest/download/nvim-linux-${NVIM_ARCH}.tar.gz"
    fi
    if curl -fsSL --connect-timeout 10 -m 90 "$nvim_url" -o "$nvim_stage/nvim.tar.gz" 2>/dev/null; then
      if tar -xzf "$nvim_stage/nvim.tar.gz" -C "$nvim_stage" 2>/dev/null; then
        extracted_dir=$(find "$nvim_stage" -mindepth 1 -maxdepth 1 -type d \( -name "nvim-linux*" -o -name "nvim-macos*" \) 2>/dev/null | head -n 1)
        if [[ -n "$extracted_dir" && -x "$extracted_dir/bin/nvim" ]]; then
          if install_nvim_tree "$extracted_dir"; then
            success 'Neovim 新版本已验证并安装。'
            remove_skipped neovim
            remove_skipped nvim
          else
            warn 'Neovim 更新失败；旧版本已保留或恢复，请查看暂存目录与日志。'
          fi
        fi
      fi
    fi
    rm -rf "$nvim_stage"
  fi
fi

# vfox 可选版本管理安装（优先包管理器，缺失时尝试官方用户态脚本）
if ((WITH_VFOX)) && ! command -v vfox >/dev/null 2>&1; then
  optional_package vfox vfox || true
  if ! command -v vfox >/dev/null 2>&1; then
    info "$(msg "系统仓库无 vfox，正在尝试通过官方脚本安装至用户目录..." "vfox not in repo; attempting official install script...")"
    vfox_stage=$(mktemp -d "$HOME/.vfox-tmp-XXXXXX")
    if curl -fsSL --connect-timeout 10 -m 60 "https://raw.githubusercontent.com/version-fox/vfox/main/install.sh" -o "$vfox_stage/install.sh" 2>/dev/null; then
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
  optional_package lazydocker lazydocker || true
  if ! command -v lazydocker >/dev/null 2>&1; then
    info "$(msg "系统仓库无 lazydocker，正在尝试下载官方独立二进制至 ~/.local/bin..." "lazydocker not in repo; downloading official binary...")"
    lzd_arch="x86_64"
    [[ "$ARCH" == arm64 || "$ARCH" == aarch64 ]] && lzd_arch="arm64"
    lzd_os="Linux"
    [[ "$OS" == Darwin ]] && lzd_os="Darwin"
    lzd_stage=$(mktemp -d "$HOME/.lzd-tmp-XXXXXX")
    # 动态获取最新 Release 标签与版本号，拼接符合官方规范的资产文件名
    lzd_latest_url=$(curl -fsSL --connect-timeout 10 --max-time 30 -o /dev/null -w '%{url_effective}' https://github.com/jesseduffield/lazydocker/releases/latest 2>/dev/null) || true
    lzd_tag=${lzd_latest_url##*/}
    lzd_version=${lzd_tag#v}
    if [[ "$lzd_tag" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      lzd_url="https://github.com/jesseduffield/lazydocker/releases/download/${lzd_tag}/lazydocker_${lzd_version}_${lzd_os}_${lzd_arch}.tar.gz"
      if curl -fsSL --connect-timeout 10 -m 90 "$lzd_url" -o "$lzd_stage/lzd.tar.gz" 2>/dev/null; then
        if tar -xzf "$lzd_stage/lzd.tar.gz" -C "$lzd_stage" lazydocker 2>/dev/null && [[ -x "$lzd_stage/lazydocker" ]]; then
          mkdir -p "$HOME/.local/bin"
          install -m 755 "$lzd_stage/lazydocker" "$HOME/.local/bin/lazydocker"
          success "$(msg "lazydocker 安装成功（位于 ~/.local/bin/lazydocker）" "lazydocker installed successfully (in ~/.local/bin/lazydocker)")"
          remove_skipped lazydocker
        fi
      fi
    fi
    rm -rf "$lzd_stage"
  fi
fi

# lazygit Git 终端面板安装（优先包管理器，缺失时尝试官方独立预编译二进制）
if ((WITH_LAZYGIT)) && ! command -v lazygit >/dev/null 2>&1; then
  optional_package lazygit lazygit || true
  if ! command -v lazygit >/dev/null 2>&1; then
    info "$(msg "系统仓库无 lazygit，正在尝试下载官方独立二进制至 ~/.local/bin..." "lazygit not in repo; downloading official binary...")"
    lg_arch="x86_64"
    [[ "$ARCH" == arm64 || "$ARCH" == aarch64 ]] && lg_arch="arm64"
    lg_os="Linux"
    [[ "$OS" == Darwin ]] && lg_os="Darwin"
    lg_stage=$(mktemp -d "$HOME/.lg-tmp-XXXXXX")
    lg_url=$(curl -fsSL --connect-timeout 10 --max-time 30 -o /dev/null -w '%{url_effective}' https://github.com/jesseduffield/lazygit/releases/latest 2>/dev/null) || true
    lg_tag=${lg_url##*/}
    lg_version=${lg_tag#v}
    if [[ "$lg_tag" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      lg_download_url="https://github.com/jesseduffield/lazygit/releases/download/${lg_tag}/lazygit_${lg_version}_${lg_os}_${lg_arch}.tar.gz"
      if curl -fsSL --connect-timeout 10 -m 90 "$lg_download_url" -o "$lg_stage/lg.tar.gz" 2>/dev/null; then
        if tar -xzf "$lg_stage/lg.tar.gz" -C "$lg_stage" lazygit 2>/dev/null && [[ -x "$lg_stage/lazygit" ]]; then
          mkdir -p "$HOME/.local/bin"
          install -m 755 "$lg_stage/lazygit" "$HOME/.local/bin/lazygit"
          success "$(msg "lazygit 安装成功（位于 ~/.local/bin/lazygit）" "lazygit installed successfully (in ~/.local/bin/lazygit)")"
          remove_skipped lazygit
        fi
      fi
    fi
    rm -rf "$lg_stage"
  fi
fi

if ((WITH_TMUX)); then
  info "$(msg "正在安装 tmux 及终端剪贴板依赖..." "Installing tmux and clipboard dependencies...")"
  optional_package tmux tmux || true
  if [[ "$FAMILY" == apt || "$FAMILY" == dnf || "$FAMILY" == pacman || "$FAMILY" == zypper ]]; then
    optional_package xclip xclip || true
    optional_package wl-copy wl-clipboard || true
    [[ "$FAMILY" == apt ]] && { optional_package "" ncurses-term || true; }
  fi
fi

# 命令名软链接映射（兼容各发行版的 fdfind / batcat / tre-agrep）
mkdir -p "$HOME/.local/bin"
if ! command -v fd >/dev/null 2>&1 && command -v fdfind >/dev/null 2>&1; then
  [[ ! -e "$HOME/.local/bin/fd" ]] && ln -s "$(command -v fdfind)" "$HOME/.local/bin/fd" 2>/dev/null || true
fi
if ! command -v bat >/dev/null 2>&1 && command -v batcat >/dev/null 2>&1; then
  [[ ! -e "$HOME/.local/bin/bat" ]] && ln -s "$(command -v batcat)" "$HOME/.local/bin/bat" 2>/dev/null || true
fi
if ! command -v agrep >/dev/null 2>&1 && command -v tre-agrep >/dev/null 2>&1; then
  [[ ! -e "$HOME/.local/bin/agrep" ]] && ln -s "$(command -v tre-agrep)" "$HOME/.local/bin/agrep" 2>/dev/null || true
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
      cp "$HOME/powerlevel10k/config/p10k-rainbow.zsh" "$BACKUP/new.p10k.zsh"
      success "$(msg "已生成 Powerlevel10k 经典彩虹主题配置 (~/.p10k.zsh)" "Generated Powerlevel10k rainbow theme config (~/.p10k.zsh)")"
    fi
    ;;
  lean)
    if [[ -f "$HOME/powerlevel10k/config/p10k-lean.zsh" ]]; then
      cp "$HOME/powerlevel10k/config/p10k-lean.zsh" "$BACKUP/new.p10k.zsh"
      success "$(msg "已生成 Powerlevel10k 现代极简主题配置 (~/.p10k.zsh)" "Generated Powerlevel10k lean theme config (~/.p10k.zsh)")"
    fi
    ;;
  classic)
    if [[ -f "$HOME/powerlevel10k/config/p10k-classic.zsh" ]]; then
      cp "$HOME/powerlevel10k/config/p10k-classic.zsh" "$BACKUP/new.p10k.zsh"
      success "$(msg "已生成 Powerlevel10k 经典传统主题配置 (~/.p10k.zsh)" "Generated Powerlevel10k classic theme config (~/.p10k.zsh)")"
    fi
    ;;
  wizard)
    # 已纳入统一备份；让显式向导修改配置，不提前删除用户原文件。
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
    command rm -f "$HOME/.tmux.conf" 2>/dev/null || true
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

for helper in manage.sh retry_tools.sh; do
  [[ ! -f "$SCRIPT_DIR/scripts/$helper" ]] || install -m 700 "$SCRIPT_DIR/scripts/$helper" "$STATE_ROOT/scripts/$helper"
done

# 10. 部署配置文件
cp "$SCRIPT_DIR/templates/zshrc.zsh" "$BACKUP/new.zshrc"

q_script_dir=$(printf '%q' "$SCRIPT_DIR")
cat <<EOF > "$BACKUP/new.options"
# 安装器生成；1 为启用，0 为关闭。
ZSH_PROJECT_FULL=$([[ "$PROFILE" == full ]] && echo 1 || echo 0)
ZSH_PROJECT_TELEVISION=1
ZSH_PROJECT_TV_KEYBINDINGS=0
ZSH_PROJECT_TRE=1
ZSH_PROJECT_VFOX=$WITH_VFOX
ZSH_PROJECT_LAZYDOCKER=$WITH_LAZYDOCKER
ZSH_PROJECT_LAZYGIT=$WITH_LAZYGIT
ZSH_PROJECT_TMUX=$WITH_TMUX
ZSH_PROJECT_DIR=${q_script_dir}
ZSH_PROJECT_LANG="$LANG_CHOICE"
ZSH_PROJECT_AUTO_CHECK_UPDATE=1
ZSH_PROJECT_CHECK_INTERVAL_DAYS=7
ZSH_PROJECT_BANNER=1
ZSH_PROJECT_FASTFETCH=1
ZSH_PROJECT_TIMER=1
EOF

zsh -n "$BACKUP/new.zshrc"
zsh -n "$BACKUP/new.options"
if [[ -f "$BACKUP/new.p10k.zsh" ]]; then
  zsh -n "$BACKUP/new.p10k.zsh"
  command rm -f "$HOME/.p10k.zsh" 2>/dev/null || true
  install -m 600 "$BACKUP/new.p10k.zsh" "$HOME/.p10k.zsh"
fi

command rm -f "$HOME/.zsh-project-options" 2>/dev/null || true
install -m 600 "$BACKUP/new.options" "$HOME/.zsh-project-options"
command rm -f "$HOME/.zshrc" 2>/dev/null || true
install -m 600 "$BACKUP/new.zshrc" "$HOME/.zshrc"

# 清理旧的编译字节码（若存在，借鉴 zsh4humans 规范），防止 Zsh 继续读取失效旧缓存
command rm -f -- "$HOME/.zshrc.zwc" "$HOME/.zshenv.zwc" "$HOME/.zprofile.zwc" "$HOME/.p10k.zsh.zwc" 2>/dev/null || true

# 若启用 vfox，预先生成环境缓存以避免首次启动超时
if ((WITH_VFOX)) && command -v vfox >/dev/null 2>&1; then
  local_state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/zsh-project"
  mkdir -p "$local_state_dir"
  vfox activate zsh > "$local_state_dir/vfox-activate.zsh" 2>/dev/null || true
fi

deployed_files=("${target_files[@]}")
for file in "${deployed_files[@]}"; do
  if [[ -f "$HOME/$file" ]]; then
    calc_sha256 "$HOME/$file" > "$BACKUP/$file.sha256"
  else
    printf 'missing\n' > "$BACKUP/$file.sha256"
  fi
done

# 首次执行一次静默后台版本检测（生成初始缓存）
if [[ -f "$STATE_ROOT/scripts/check_updates.sh" ]]; then
  bash "$STATE_ROOT/scripts/check_updates.sh" -q --lang "$LANG_CHOICE" >/dev/null 2>&1 || true
fi

printf '\n\033[1;32m🎉 %s\033[0m\n' "$(msg 'Zsh 配置安装完成！' 'Zsh configuration installed successfully!')"
printf '%s: %s\n' "$(msg '备份目录与安装日志' 'Backup directory and install log')" "$BACKUP"
printf '%s: %s\n' "$(msg '跳过的未安装包' 'Skipped packages')" "${SKIPPED[*]:-none}"
# 独立重试读取结构化组件名称，不解析翻译后的日志。
failed_tmp=$(mktemp "$STATE_ROOT/failed-components.XXXXXXXX")
if ((${#SKIPPED[@]})); then printf '%s\n' "${SKIPPED[@]}" | sort -u > "$failed_tmp"; fi
mv "$failed_tmp" "$STATE_ROOT/failed-components"
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
current_shell="${SHELL:-}"
if [[ "$current_shell" == *zsh ]]; then
  info "$(msg "当前默认 Shell 已经是 Zsh ($current_shell)，无需修改。" "Current default shell is already Zsh ($current_shell); no change needed.")"
elif ((!ASSUME_YES)) && ask "$(msg '是否将 Zsh 设为当前用户的默认登录 Shell？' 'Set Zsh as default login shell for current user?') "; then
  zsh_bin=$(command -v zsh)
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

printf '\n%s:\n  bash %s/install.sh --rollback %q\n' \
  "$(msg '若需要回退配置，请运行' 'To rollback configuration, run')" "$SCRIPT_DIR" "$BACKUP"

# 恢复终端原始标准输出与标准错误流，确保后续向导与全新交互式 Shell 会话拥有物理 TTY 控制权
exec 1>&3 2>&4
exec 3>&- 4>&-

# 恢复原始语言环境，彻底杜绝全新的 Zsh 与 Neovim 受到 C 字符集污染产生乱码
if [[ -n "${ORIG_LC_ALL:-}" ]]; then
  export LC_ALL="$ORIG_LC_ALL"
else
  unset LC_ALL
fi

# 12. 立即启动新 Shell 会话自举（借鉴 zsh4humans 体验）
if [[ "$P10K_STYLE" == wizard ]] && [[ -t 0 ]] && command -v zsh >/dev/null 2>&1; then
  echo ""
  printf '\n\033[1;36m%s\033[0m\n' "$(msg '🛠️ 正在为您启动 Powerlevel10k 官方配置向导...' '🛠️ Launching Powerlevel10k configuration wizard...')"
  if ! zsh -ic 'p10k configure'; then warn '主题向导未成功完成，请检查现有配置。'; fi
  # 向导可能同时修改主题和 .zshrc；记录最终状态，使安装回退仍然可用。
  for file in "${deployed_files[@]}"; do
    if [[ -f "$HOME/$file" ]]; then
      calc_sha256 "$HOME/$file" > "$BACKUP/$file.sha256"
    else
      printf 'missing\n' > "$BACKUP/$file.sha256"
    fi
  done
fi
if [[ -t 0 ]] && ((!ASSUME_YES)) && command -v zsh >/dev/null 2>&1; then
  echo ""
  if ask "$(msg '是否现在立即进入全新的 Zsh 交互环境？' 'Start fresh Zsh session now?')"; then
    printf '\n\033[1;32m%s\033[0m\n' "$(msg '🚀 正在启动全新 Zsh 交互环境...' '🚀 Starting fresh Zsh environment...')"
    exec zsh -l
  fi
fi
