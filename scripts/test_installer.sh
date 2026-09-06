#!/usr/bin/env bash
# 隔离回归：不安装软件、不联网、不修改真实 HOME。保留临时目录便于排查。
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/zsh-installer-tests.XXXXXXXX")
export HOME="$STAGE/home" XDG_STATE_HOME="$STAGE/state" XDG_CONFIG_HOME="$STAGE/config"
mkdir -p "$HOME" "$STAGE/bin" "$STAGE/standalone"
unset ZDOTDIR
trap 'printf "测试目录：%s\n" "$STAGE"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf 'PASS: %s\n' "$*"; }
extract_function() { sed -n "/^$1() {/,/^}/p" "$ROOT/install.sh"; }
bash -n "$ROOT/install.sh"
bash -n "$ROOT/scripts/check_updates.sh"
pass 'Bash syntax'

# 任何联网/提权调用都留证据并失败；同时验证单文件缺模板的预演。
export AUDIT_MARKER="$STAGE/forbidden-call"
for tool in curl wget git sudo brew; do
  printf '#!/usr/bin/env bash\necho "$0" >> "$AUDIT_MARKER"\nexit 1\n' > "$STAGE/bin/$tool"
  chmod +x "$STAGE/bin/$tool"
done
export PATH="$STAGE/bin:$PATH"
cp "$ROOT/install.sh" "$STAGE/standalone/install.sh"
for arg in '' --check-updates --update; do
  bash "$STAGE/standalone/install.sh" --dry-run --lang en ${arg:+"$arg"} > "$STAGE/dry.log"
done
[[ ! -e "$AUDIT_MARKER" && ! -e "$XDG_STATE_HOME" && ! -e "$XDG_CONFIG_HOME" ]] || fail 'dry run wrote state or invoked network'
pass 'all dry-run routes including missing templates'

eval "$(extract_function install_nvim_tree)"
mkdir -p "$HOME/.local/opt/nvim" "$HOME/.local/bin" "$STAGE/nvim-good/bin" "$STAGE/nvim-bad/bin"
echo original > "$HOME/.local/opt/nvim/original"
printf '#!/usr/bin/env bash\nexit 0\n' > "$STAGE/nvim-good/bin/nvim"
printf '#!/usr/bin/env bash\nexit 1\n' > "$STAGE/nvim-bad/bin/nvim"
chmod +x "$STAGE"/nvim-*/bin/nvim
if install_nvim_tree "$STAGE/nvim-bad"; then fail 'invalid nvim accepted'; fi
[[ -f "$HOME/.local/opt/nvim/original" ]] || fail 'old nvim lost during validation'
pass 'invalid binary preserves old Neovim'

# 模拟切换新目录失败，确认旧目录被恢复。
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

# 回退函数直接使用生产实现；模拟安装前后状态，包括个人主题。
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

# 三种预设只生成待部署文件；向导也不能提前删除当前个人配置。
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

# 最终目标清单必须在选项收集之后执行，拒绝交互选中的目录目标。
validate_block=$(sed -n '/^target_files=(/,/^done$/p' "$ROOT/install.sh")
mkdir -p "$HOME/.tmux.conf"
if (WITH_TMUX=1; P10K_STYLE=skip; SCRIPT_DIR=$ROOT; eval "$validate_block"); then
  fail 'tmux directory accepted after interactive selection'
fi
pass 'final tmux target validation'

# 当前状态缓存必须在断网后保持原样。
mkdir -p "$XDG_STATE_HOME/zsh-project"
echo pending > "$XDG_STATE_HOME/zsh-project/available_updates"
if bash "$ROOT/scripts/check_updates.sh" -q; then fail 'offline check returned success'; fi
grep -qx pending "$XDG_STATE_HOME/zsh-project/available_updates" || fail 'offline check erased pending updates'
pass 'offline update check preserves cache'

# 如本机提供 Zsh，执行模板语法与更新函数的真实 Zsh 回归。
if command -v zsh >/dev/null 2>&1; then
  zsh -n "$ROOT/templates/zshrc.zsh"
  mkdir -p "$XDG_STATE_HOME/zsh-project/scripts"
  printf '#!/usr/bin/env bash\necho UPDATE_CHECK_OK\n' > "$XDG_STATE_HOME/zsh-project/scripts/check_updates.sh"
  sed -n '/^function _zsh_project_check_script()/,/^unset _zsh_project_state_dir/p' "$ROOT/templates/zshrc.zsh" > "$STAGE/update-functions.zsh"
  zsh -f -c 'source "$1"; zsh-check-updates' test "$STAGE/update-functions.zsh" | grep -qx UPDATE_CHECK_OK || fail 'update helper lost script path'
  pass 'Zsh syntax and update command after temporary variables are unset'

  # 即使工具已在 PATH，关闭选项也不能激活它们或安装其别名。
  mkdir -p "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting" "$HOME/powerlevel10k"
  : > "$HOME/.oh-my-zsh/oh-my-zsh.sh"
  : > "$HOME/powerlevel10k/powerlevel10k.zsh-theme"
  : > "$HOME/.p10k.zsh"
  : > "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
  printf 'ZSH_PROJECT_FULL=0\nZSH_PROJECT_VFOX=0\nZSH_PROJECT_LAZYDOCKER=0\nZSH_PROJECT_TMUX=0\nZSH_PROJECT_AUTO_CHECK_UPDATE=0\n' > "$HOME/.zsh-project-options"
  export TOOL_MARKER="$STAGE/tools-ran"
  for tool in vfox lazydocker nvim fzf zoxide fastfetch eza yazi bat; do
    printf '#!/usr/bin/env bash\necho "$0" >> "$TOOL_MARKER"\n' > "$STAGE/bin/$tool"
    chmod +x "$STAGE/bin/$tool"
  done
  zsh -fic 'source "$1"; (( ${+aliases[lzd]} == 0 )); (( ${+functions[nvim]} == 0 ))' test "$ROOT/templates/zshrc.zsh" > "$STAGE/template.log"
  [[ ! -s "$TOOL_MARKER" ]] || fail 'disabled optional tools executed'
  pass 'disabled feature flags bypass installed optional tools'
else
  printf 'SKIP: Zsh runtime unavailable (run this suite again on Linux)\n'
fi
pass 'regression suite completed'
