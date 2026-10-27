#!/usr/bin/env bash
# 隔离回归：不安装软件、不联网、不修改真实 HOME。保留临时目录便于排查。
set -Eeuo pipefail
case ${OSTYPE:-} in msys*|cygwin*) export PATH="/usr/bin:$PATH" ;; esac
ROOT=$(cd "$(dirname "$0")/.." && pwd)
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/zsh-installer-tests.XXXXXXXX")
export HOME="$STAGE/home" XDG_STATE_HOME="$STAGE/state" XDG_CONFIG_HOME="$STAGE/config"
mkdir -p "$HOME" "$STAGE/bin" "$STAGE/standalone"
unset ZDOTDIR
trap 'printf "测试目录：%s\n" "$STAGE"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf 'PASS: %s\n' "$*"; }
extract_function() { sed -n "/^$1() {/,/^}/p" "$ROOT/install.sh"; }
# ------------------------------------------------------------------------------
# 1. 语法检查与模板一致性：验证主安装器、更新检测脚本语法及 .tmux.conf 同步状态
# ------------------------------------------------------------------------------
bash -n "$ROOT/install.sh"
bash -n "$ROOT/scripts/check_updates.sh"
cmp -s "$ROOT/.tmux.conf" "$ROOT/templates/tmux.conf" || fail '.tmux.conf and templates/tmux.conf are out of sync'
pass 'Bash syntax and tmux template sync'

# ------------------------------------------------------------------------------
# 2. Dry-Run 预演路由隔离测试：
# 确保在任意模式（普通、更新检测、升级、自动化）及缺少模板情况下，
# --dry-run 均不写任何状态文件、不触发真实网络请求、不调用外部包管理或 sudo 提权
# ------------------------------------------------------------------------------
export AUDIT_MARKER="$STAGE/forbidden-call"
for tool in curl wget git sudo brew; do
  printf '#!/usr/bin/env bash\necho "$0" >> "$AUDIT_MARKER"\nexit 1\n' > "$STAGE/bin/$tool"
  chmod +x "$STAGE/bin/$tool"
done
export PATH="$STAGE/bin:$PATH"
cp "$ROOT/install.sh" "$STAGE/standalone/install.sh"
for arg in '' --check-updates --update --yes; do
  bash "$STAGE/standalone/install.sh" --dry-run --lang en ${arg:+"$arg"} > "$STAGE/dry.log"
done
[[ ! -e "$AUDIT_MARKER" && ! -e "$XDG_STATE_HOME" && ! -e "$XDG_CONFIG_HOME" ]] || fail 'dry run wrote state or invoked network'
pass 'all dry-run routes including missing templates'

# ------------------------------------------------------------------------------
# 3. Neovim 树形切换原子性：
# 校验新下载的二进制可执行性；若校验失败立即阻断，确保旧版本不被破坏
# ------------------------------------------------------------------------------
eval "$(extract_function install_nvim_tree)"
mkdir -p "$HOME/.local/opt/nvim" "$HOME/.local/bin" "$STAGE/nvim-good/bin" "$STAGE/nvim-bad/bin"
echo original > "$HOME/.local/opt/nvim/original"
printf '#!/usr/bin/env bash\nexit 0\n' > "$STAGE/nvim-good/bin/nvim"
printf '#!/usr/bin/env bash\nexit 1\n' > "$STAGE/nvim-bad/bin/nvim"
chmod +x "$STAGE"/nvim-*/bin/nvim
if install_nvim_tree "$STAGE/nvim-bad"; then fail 'invalid nvim accepted'; fi
[[ -f "$HOME/.local/opt/nvim/original" ]] || fail 'old nvim lost during validation'
pass 'invalid binary preserves old Neovim'

# ------------------------------------------------------------------------------
# 4. 目录切换故障原子回退：
# 模拟重命名或目录切换失败，验证旧版 Neovim 目录与软链接能够完好恢复
# ------------------------------------------------------------------------------
if ln -s "$STAGE/nonexistent-target" "$STAGE/symlink-probe" 2>/dev/null; then
mv() {
  if [[ "$1" == */new && "$2" == "$HOME/.local/opt/nvim" ]]; then return 1; fi
  command mv "$@"
}
if install_nvim_tree "$STAGE/nvim-good"; then fail 'failed swap accepted'; fi
unset -f mv
[[ -f "$HOME/.local/opt/nvim/original" ]] || fail 'old nvim not restored after failed swap'
pass 'failed swap restores old Neovim'
install_nvim_tree "$STAGE/nvim-good"
[[ -x "$HOME/.local/bin/nvim" ]] || fail 'new Neovim unavailable'
find "$HOME/.local/opt" -path '*/previous/original' | grep -q . || fail 'old Neovim backup missing'
pass 'successful swap retains previous version'
else
  printf 'SKIP: native dangling symlinks unavailable; run Neovim swap cases on Linux\n'
fi

# ------------------------------------------------------------------------------
# 5. Bash 3.2 set -u (nounset) 空数组展开安全性验证：
# 确保在 remove_skipped 清空数组后，不会因 Bash 3.2 限制触发 unbound variable 崩溃
# ------------------------------------------------------------------------------
eval "$(extract_function remove_skipped)"
SKIPPED=()
remove_skipped fzf
SKIPPED=(fzf)
remove_skipped fzf
((${#SKIPPED[@]} == 0)) || fail 'remove_skipped did not clear single item'
pass 'remove_skipped handles empty arrays under nounset'

# ------------------------------------------------------------------------------
# 6. optional_package 幂等性与多别名自动检测：
# 命令或发行版别名（如 fdfind, batcat, 7zz, convert, ripgrep, wl-copy）存在时，
# 绝不重复调用包管理器；若包缺失则安全记录到 SKIPPED
# ------------------------------------------------------------------------------
eval "$(extract_function optional_package)"
FAMILY=apt
for fake_cmd in fd bat 7zz convert ripgrep wl-copy; do
  printf '#!/usr/bin/env bash\nexit 0\n' > "$STAGE/bin/$fake_cmd"
  chmod +x "$STAGE/bin/$fake_cmd"
done
optional_package fd fd-find || fail 'optional_package fd failed'
optional_package bat batcat || fail 'optional_package bat failed'
optional_package 7z 7zip || fail 'optional_package 7z (via 7zz) failed'
optional_package magick imagemagick || fail 'optional_package magick (via convert) failed'
optional_package rg ripgrep || fail 'optional_package rg (via ripgrep) failed'
optional_package xclip xclip || fail 'optional_package xclip (via wl-copy) failed'
[[ ! -e "$AUDIT_MARKER" ]] || fail 'optional_package invoked package manager despite existing binaries/aliases'
if optional_package missing_command definitely_missing_pkg 2>/dev/null; then
  fail 'optional_package should return non-zero when package is missing'
fi
((${#SKIPPED[@]} > 0)) || fail 'optional_package did not record missing package to SKIPPED'
pass 'optional_package idempotency, alias detection, and missing package handling'

# ------------------------------------------------------------------------------
# 6b. optional_package 与 retry_tools.sh normalize() 白名单一致性校验：
# 确保 install.sh 中所有可能写入 SKIPPED / failed-components 的包名均被 normalize() 支持
# ------------------------------------------------------------------------------
eval "$(sed -n '/^normalize() {/,/^}/p' "$ROOT/scripts/retry_tools.sh")"
for candidate_pkg in \
  fzf fd fd-find bat batcat eza zoxide yazi fastfetch neovim television tre-command \
  tre tre-agrep ripgrep jq ffmpeg sevenzip 7zip p7zip-full p7zip poppler poppler-utils \
  poppler-tools imagemagick ImageMagick resvg wl-clipboard xclip xsel tmux ncurses-term \
  font-symbols-only-nerd-font lazydocker lazygit vfox; do
  normalize "$candidate_pkg" >/dev/null || fail "retry_tools.sh normalize() rejected package: $candidate_pkg"
done
# 扫描 install.sh 中所有字面量 optional_package 调用的第二参数
while IFS= read -r literal_pkg; do
  [[ -n "$literal_pkg" ]] || continue
  normalize "$literal_pkg" >/dev/null || fail "install.sh optional_package '$literal_pkg' not in retry_tools.sh normalize()"
done < <(awk '$1 == "optional_package" && $3 !~ /^["$]/ {gsub(/[;|]/, "", $3); print $3}' "$ROOT/install.sh" | sort -u)
pass 'all optional_package names are recognized by retry_tools.sh normalize()'

# ------------------------------------------------------------------------------
# 6c. Tmux >= 3.2 版本号解析器边界测试：
# 覆盖 3.2a、next-3.6、3.10、openbsd-7.5（通过）与 3.1c、2.8（拦截）
# ------------------------------------------------------------------------------
check_tmux_ver() {
  local _tmux_ver_raw="$1" _tmux_ver_num _tmux_maj _tmux_min
  _tmux_ver_num=$(printf '%s\n' "$_tmux_ver_raw" | grep -oE '[0-9]+\.[0-9]+' | head -n 1 || true)
  [[ -n "$_tmux_ver_num" ]] || return 1
  _tmux_maj="${_tmux_ver_num%%.*}"
  _tmux_min="${_tmux_ver_num#*.}"
  if (( 10#${_tmux_maj:-0} < 3 || (10#${_tmux_maj:-0} == 3 && 10#${_tmux_min:-0} < 2) )); then
    return 1
  fi
  return 0
}
for valid_ver in "tmux 3.2" "tmux 3.2a" "tmux 3.5a" "tmux next-3.6" "tmux 3.10" "tmux openbsd-7.5"; do
  check_tmux_ver "$valid_ver" || fail "valid tmux version rejected: $valid_ver"
done
for invalid_ver in "tmux 3.1c" "tmux 3.0a" "tmux 2.8" "tmux 1.9"; do
  if check_tmux_ver "$invalid_ver"; then fail "outdated tmux version accepted: $invalid_ver"; fi
done
pass 'tmux >= 3.2 version parser handles release, next-*, multi-digit minor, and openbsd strings'

# ------------------------------------------------------------------------------
# 7. Nerd Font 图标字体检测幂等性测试：
# 验证系统字体库与自定义目录的探测逻辑
# ------------------------------------------------------------------------------
eval "$(extract_function has_nerd_font)"
font_mock_dir="$HOME/.local/share/fonts/NerdFonts"
rm -rf "$font_mock_dir"
has_nerd_font && fail 'has_nerd_font reported positive on clean state'
mkdir -p "$font_mock_dir"
touch "$font_mock_dir/SymbolsNerdFont-Regular.ttf"
has_nerd_font || fail 'has_nerd_font failed to detect installed Nerd Font'
pass 'has_nerd_font detection'

# ------------------------------------------------------------------------------
# 8. 配置回退与用户二次修改防护测试：
# 若安装后用户手动修改了主题或配置，校验和不符时拒绝回退，防止意外丢失用户修改
# ------------------------------------------------------------------------------
eval "$(extract_function calc_sha256)"
eval "$(extract_function restore)"
msg() { printf '%s' "$1"; }
die() { printf '%s\n' "$*" >&2; exit 1; }
success() { :; }
ask() { return 0; }
DRY_RUN=0
backup="$STAGE/backup"
mkdir -p "$backup"
printf '%s\n' "$HOME" > "$backup/manifest"
for file in .zshrc .zsh-project-options .p10k.zsh; do
  printf 'original %s\n' "$file" > "$backup/$file"
  printf 'present\n' > "$backup/$file.state"
  printf 'installed %s\n' "$file" > "$HOME/$file"
  calc_sha256 "$HOME/$file" > "$backup/$file.sha256"
done
echo modified >> "$HOME/.p10k.zsh"
if (restore "$backup"); then fail 'modified theme was overwritten by rollback'; fi
grep -q installed "$HOME/.zshrc" || fail 'rollback partially modified configs before rejecting theme'
printf 'installed .p10k.zsh\n' > "$HOME/.p10k.zsh"
restore "$backup"
for file in .zshrc .zsh-project-options .p10k.zsh; do cmp "$HOME/$file" "$backup/$file" || fail 'rollback mismatch'; done
pass 'theme rollback and post-install edit protection'

# ------------------------------------------------------------------------------
# 9. 主题预设暂存与向导保护：
# 三种内置主题预设只写入暂存文件；向导模式绝不提前删除已有配置
# ------------------------------------------------------------------------------
theme_block=$(sed -n '/^# 部署 Powerlevel10k/,/^esac$/p' "$ROOT/install.sh")
BACKUP="$STAGE/theme-stage"
mkdir -p "$BACKUP" "$HOME/powerlevel10k/config"
info() { :; }
for style in rainbow lean classic; do
  printf '%s\n' "$style" > "$HOME/powerlevel10k/config/p10k-$style.zsh"
  P10K_STYLE=$style
  eval "$theme_block"
  grep -qx "$style" "$BACKUP/new.p10k.zsh" || fail 'theme staging failed'
  cmp "$HOME/.p10k.zsh" "$backup/.p10k.zsh" || fail 'preset overwrote theme before validation'
done
P10K_STYLE=wizard
eval "$theme_block"
cmp "$HOME/.p10k.zsh" "$backup/.p10k.zsh" || fail 'wizard deleted existing theme'
pass 'presets stage changes and wizard preserves current theme'

# ------------------------------------------------------------------------------
# 10. 目标文件类型合法性校验：
# 严防非法软链接或目录覆盖，确保目标为普通文件
# ------------------------------------------------------------------------------
validate_block=$(sed -n '/^target_files=(/,/^done$/p' "$ROOT/install.sh")
mkdir -p "$HOME/.tmux.conf"
if (WITH_TMUX=1; P10K_STYLE=skip; SCRIPT_DIR=$ROOT; eval "$validate_block"); then
  fail 'tmux directory accepted after interactive selection'
fi
pass 'final tmux target validation'

# ------------------------------------------------------------------------------
# 11. 离线更新检测缓存保护：
# 网络不通或探测超时时，保留现有更新缓存，绝不静默覆盖为空
# ------------------------------------------------------------------------------
mkdir -p "$XDG_STATE_HOME/zsh-project"
echo pending > "$XDG_STATE_HOME/zsh-project/available_updates"
if bash "$ROOT/scripts/check_updates.sh" -q; then fail 'offline check returned success'; fi
grep -qx pending "$XDG_STATE_HOME/zsh-project/available_updates" || fail 'offline check erased pending updates'
pass 'offline update check preserves cache'

# ------------------------------------------------------------------------------
# 12. Zsh 模板语法与更新检测辅助函数集成验证
# ------------------------------------------------------------------------------
if command -v zsh >/dev/null 2>&1; then
  zsh -n "$ROOT/templates/zshrc.zsh"
  mkdir -p "$XDG_STATE_HOME/zsh-project/scripts"
  printf '#!/usr/bin/env bash\necho UPDATE_CHECK_OK\n' > "$XDG_STATE_HOME/zsh-project/scripts/check_updates.sh"
  sed -n '/^function _zsh_project_check_script()/,/^unset _zsh_project_state_dir/p' "$ROOT/templates/zshrc.zsh" > "$STAGE/update-functions.zsh"
  zsh -f -c 'source "$1"; zsh-check-updates' test "$STAGE/update-functions.zsh" | grep -qx UPDATE_CHECK_OK || fail 'update helper lost script path'
  pass 'Zsh syntax and update command after temporary variables are unset'

  # ------------------------------------------------------------------------------
  # 13. 功能开关有效性防穿透测试：
  # 即使相关 CLI 工具已在 PATH 中，选项关闭时绝不加载其别名或函数
  # ------------------------------------------------------------------------------
  mkdir -p "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting" "$HOME/powerlevel10k"
  : > "$HOME/.oh-my-zsh/oh-my-zsh.sh"
  : > "$HOME/powerlevel10k/powerlevel10k.zsh-theme"
  : > "$HOME/.p10k.zsh"
  : > "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
  printf 'ZSH_PROJECT_FULL=0\nZSH_PROJECT_VFOX=0\nZSH_PROJECT_LAZYDOCKER=0\nZSH_PROJECT_LAZYGIT=0\nZSH_PROJECT_TMUX=0\nZSH_PROJECT_AUTO_CHECK_UPDATE=0\n' > "$HOME/.zsh-project-options"
  export TOOL_MARKER="$STAGE/tools-ran"
  for tool in vfox lazydocker lazygit nvim fzf zoxide fastfetch eza yazi bat tv tre agrep; do
    printf '#!/usr/bin/env bash\necho "$0" >> "$TOOL_MARKER"\n' > "$STAGE/bin/$tool"
    chmod +x "$STAGE/bin/$tool"
  done
  if ! zsh -fic 'source "$1" || exit 1; (( ${+aliases[lzd]} == 0 )) || exit 1; (( ${+aliases[lg]} == 0 )) || exit 1; (( ${+functions[nvim]} == 0 )) || exit 1; (( ${+functions[television-widget]} == 0 )) || exit 1; (( ${+functions[tre]} == 0 )) || exit 1' test "$ROOT/templates/zshrc.zsh" > "$STAGE/template.log" 2> "$STAGE/template.stderr"; then
    cat "$STAGE/template.stderr" >&2
    fail 'template execution or disabled feature assertions failed'
  fi
  if [[ -s "$STAGE/template.stderr" ]]; then
    cat "$STAGE/template.stderr" >&2
    fail 'template emitted startup errors or warnings'
  fi
  grep -Eq '[0-9]+ms' "$STAGE/template.log" || fail 'startup timer did not render milliseconds'
  [[ ! -s "$TOOL_MARKER" ]] || fail 'disabled optional tools executed'
  pass 'disabled feature flags bypass installed optional tools'
else
  printf 'SKIP: Zsh runtime unavailable (run this suite again on Linux)\n'
fi
pass 'regression suite completed'
