#!/usr/bin/env bash
# 配置管理隔离回归：使用临时 HOME 与命令替身，退出后保留现场供排查。
set -Eeuo pipefail
case ${OSTYPE:-} in msys*|cygwin*) export PATH="/usr/bin:$PATH" ;; esac
ROOT=$(cd "$(dirname "$0")/.." && pwd)
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/zsh-management-tests.XXXXXXXX")
export HOME="$STAGE/home" XDG_STATE_HOME="$STAGE/state" XDG_CONFIG_HOME="$STAGE/config"
unset ZDOTDIR
mkdir -p "$HOME" "$STAGE/bin"
export AUDIT_MARKER="$STAGE/forbidden-call"
# 联网、提权和安装命令一旦被调用便留下标记并失败，防止测试触及真实系统。
for tool in curl wget git sudo brew apt-get dnf pacman zypper; do
  printf '#!/usr/bin/env bash\necho "$0" >> "$AUDIT_MARKER"\nexit 1\n' > "$STAGE/bin/$tool"
  chmod +x "$STAGE/bin/$tool"
done
export PATH="$STAGE/bin:$PATH"
trap 'printf "管理测试目录：%s\n" "$STAGE"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }
manage() { bash "$ROOT/scripts/manage.sh" "$@"; }
bash -n "$ROOT/scripts/manage.sh"
bash -n "$ROOT/scripts/retry_tools.sh"
# 验证安装入口能够分发管理预演，且不会创建状态或调用外部安装工具。
for action in --disable --enable --doctor --configure --profile-startup --retry-failed --list-backups; do
  bash "$ROOT/install.sh" "$action" --dry-run > "$STAGE/dry.log"
done
[[ ! -e "$XDG_STATE_HOME" ]] || fail 'management dry run wrote state'
[[ ! -e "$AUDIT_MARKER" ]] || fail 'management dry run invoked network or package tools'
for action in --set --diff-backup --restore-backup; do
  bash "$ROOT/install.sh" "$action" fixture --dry-run > "$STAGE/dry.log"
done
pass 'management dry-run dispatch has no state writes'

# 验证停用/恢复的幂等性、字节码退役，以及对用户后续修改的覆盖保护。
printf '# zsh-project\necho ORIGINAL\n' > "$HOME/.zshrc"
echo TMUX > "$HOME/.tmux.conf"
echo ENV > "$HOME/.zshenv"
echo bytecode > "$HOME/.zshrc.zwc"
mkdir -p "$HOME/.oh-my-zsh/custom/plugins"
echo PLUGIN > "$HOME/.oh-my-zsh/custom/plugins/keep"
cp "$HOME/.zshrc" "$STAGE/original"
manage --disable --yes
grep -q 'zsh-project: disabled' "$HOME/.zshrc" || fail 'disable failed'
[[ ! -f "$HOME/.zshrc.zwc" ]] || fail 'old bytecode still active'
count=$(find "$XDG_STATE_HOME" -name manifest | wc -l)
manage --disable --yes
[[ $(find "$XDG_STATE_HOME" -name manifest | wc -l) == "$count" ]] || fail 'disable not idempotent'
if bash "$ROOT/install.sh" --rollback "$STAGE/nonexistent" --lang en > "$STAGE/rollback.log" 2>&1; then fail 'rollback allowed while disabled'; fi
grep -q -- '--enable' "$STAGE/rollback.log" || fail 'rollback bypassed disabled guard'
cp "$HOME/.zshrc" "$STAGE/disabled"
echo USER_EDIT >> "$HOME/.zshrc"
if manage --enable --yes; then fail 'enable overwrote user edit'; fi
cp "$STAGE/disabled" "$HOME/.zshrc"
manage --enable --yes
cmp "$HOME/.zshrc" "$STAGE/original" || fail 'enable did not restore original'
grep -qx TMUX "$HOME/.tmux.conf" || fail 'tmux modified'
grep -qx ENV "$HOME/.zshenv" || fail 'zshenv modified'
grep -qx PLUGIN "$HOME/.oh-my-zsh/custom/plugins/keep" || fail 'plugin removed'
pass 'disable/enable, repeated disable and modification protection'

printf '# keep comment\nZSH_PROJECT_BANNER=1\nprintf MALICIOUS > "$HOME/executed-options"\n' > "$HOME/.zsh-project-options"
manage --set banner=0 --yes
grep -qx ZSH_PROJECT_BANNER=0 "$HOME/.zsh-project-options" || fail 'option not set'
grep -qx '# keep comment' "$HOME/.zsh-project-options" || fail 'comment lost'
[[ ! -f "$HOME/executed-options" ]] || fail 'manager executed options'
if manage --set 'banner=$(touch bad)' --yes; then fail 'invalid option accepted'; fi
pass 'option editing preserves unknown content without evaluating it'

backup="$STAGE/restore-fixture"
mkdir -p "$backup"
printf '%s\n' "$HOME" > "$backup/manifest"
for file in .zshrc .tmux.conf; do
  echo "OLD $file" > "$backup/$file"
  echo present > "$backup/$file.state"
  echo "NEW $file" > "$HOME/$file"
  if command -v sha256sum >/dev/null; then sha256sum "$HOME/$file" | cut -d ' ' -f1 > "$backup/$file.sha256"
  else shasum -a 256 "$HOME/$file" | cut -d ' ' -f1 > "$backup/$file.sha256"; fi
done
manage --diff-backup "$backup" --scope zsh > "$STAGE/diff.log"
grep -q 'OLD .zshrc' "$STAGE/diff.log" || fail 'backup diff absent'
manage --restore-backup "$backup" --scope zsh --yes
grep -qx 'OLD .zshrc' "$HOME/.zshrc" || fail 'zsh restore failed'
grep -qx 'NEW .tmux.conf' "$HOME/.tmux.conf" || fail 'zsh-only restore touched tmux'
manage --list-backups > "$STAGE/backups.log"
grep -q manage- "$STAGE/backups.log" || fail 'backups not listed'
pass 'backup diff, listing and scoped restore'

# 恢复安装前不存在的配置时，旧字节码也必须退出生效路径。
echo absent > "$backup/.zshrc.state"
echo compiled > "$HOME/.zshrc.zwc"
if command -v sha256sum >/dev/null; then sha256sum "$HOME/.zshrc" | cut -d ' ' -f1 > "$backup/.zshrc.sha256"
else shasum -a 256 "$HOME/.zshrc" | cut -d ' ' -f1 > "$backup/.zshrc.sha256"; fi
manage --restore-backup "$backup" --scope zsh --yes
[[ ! -e "$HOME/.zshrc" && ! -e "$HOME/.zshrc.zwc" ]] || fail 'absent restore left source or bytecode'
echo '# zsh-project' > "$HOME/.zshrc"
pass 'absent restore retires compiled configuration'

# 重试只操作失败清单中的指定组件；所有包管理器和网络命令使用桩。
printf '#!/usr/bin/env bash\necho Darwin\n' > "$STAGE/bin/uname"
printf '#!/usr/bin/env bash\nexit 0\n' > "$STAGE/bin/fzf"
for tool in brew sudo curl; do printf '#!/usr/bin/env bash\nexit 1\n' > "$STAGE/bin/$tool"; done
chmod +x "$STAGE/bin/"*
case ${OSTYPE:-} in msys*|cygwin*) export PATH="$STAGE/bin:/usr/bin:/bin" ;; *) export PATH="$STAGE/bin:$PATH" ;; esac
printf 'fzf\nlazydocker\n' > "$XDG_STATE_HOME/zsh-project/failed-components"
cp "$HOME/.zshrc" "$STAGE/pre-retry"
manage --retry-failed fzf --yes
grep -qx lazydocker "$XDG_STATE_HOME/zsh-project/failed-components" || fail 'retry erased unrelated failure'
cmp "$HOME/.zshrc" "$STAGE/pre-retry" || fail 'retry redeployed config'
if manage --retry-failed '../../bad' --yes; then fail 'invalid component accepted'; fi
if bash "$ROOT/scripts/retry_tools.sh" '../../bad' --dry-run; then fail 'invalid retry dry run accepted'; fi
printf 'fzf\nlazydocker\n' > "$XDG_STATE_HOME/zsh-project/failed-components"
if manage --retry-failed lazydocker --yes; then fail 'failed package/download retry reported success'; fi
grep -qx lazydocker "$XDG_STATE_HOME/zsh-project/failed-components" || fail 'failed retry lost component'
grep -qx fzf "$XDG_STATE_HOME/zsh-project/failed-components" || fail 'failed retry erased unrelated component'
cmp "$HOME/.zshrc" "$STAGE/pre-retry" || fail 'failed retry modified configuration'
pass 'component retry leaves configuration and unrelated failures intact'

if command -v zsh >/dev/null 2>&1; then
  mkdir -p "$HOME/powerlevel10k" "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"
  : > "$HOME/.oh-my-zsh/oh-my-zsh.sh"
  : > "$HOME/powerlevel10k/powerlevel10k.zsh-theme"
  printf 'alias local_test=LOCAL_OK\n' > "$HOME/.zshrc.local"
  printf '[[ ${aliases[local_test]:-} == LOCAL_OK ]] || return 1\n' > "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
  printf 'ZSH_PROJECT_FULL=1\nZSH_PROJECT_FASTFETCH=0\nZSH_PROJECT_BANNER=0\nZSH_PROJECT_TIMER=0\nZSH_PROJECT_AUTO_CHECK_UPDATE=0\n' > "$HOME/.zsh-project-options"
  export TOOL_MARKER="$STAGE/fastfetch-ran"
  printf '#!/usr/bin/env bash\necho ran > "$TOOL_MARKER"\n' > "$STAGE/bin/fastfetch"
  chmod +x "$STAGE/bin/fastfetch"
  # 保持完整模式而只关闭 Fastfetch；其它初始化桩不调用真实工具。
  for tool in fzf zoxide; do printf '#!/usr/bin/env bash\nexit 0\n' > "$STAGE/bin/$tool"; chmod +x "$STAGE/bin/$tool"; done
  cp "$ROOT/templates/zshrc.zsh" "$HOME/.zshrc"
  zsh -n "$HOME/.zshrc"
  zsh -fic 'source "$HOME/.zshrc" || exit 1; [[ ${aliases[local_test]} == LOCAL_OK ]] || exit 1; _zsh_msg MANUAL_MESSAGE MANUAL_MESSAGE' > "$STAGE/flags.log" 2> "$STAGE/flags.stderr" || fail 'Zsh flag/local extension execution failed'
  [[ ! -s "$STAGE/flags.stderr" ]] || { cat "$STAGE/flags.stderr"; fail 'Zsh startup errors'; }
  [[ ! -e "$TOOL_MARKER" ]] || fail 'Fastfetch ran while disabled'
  grep -qx MANUAL_MESSAGE "$STAGE/flags.log" || fail 'banner flag hid manual messages'
  if grep -Eq 'ms|PROFILE|Loading tools|环境加载完成' "$STAGE/flags.log"; then fail 'disabled banner/timer or default profiling emitted output'; fi
  if manage --profile-startup --yes > "$STAGE/profile.log" 2> "$STAGE/profile.stderr"; then :
  else
    profile_status=$?
    cat "$STAGE/profile.stderr" "$STAGE/profile.log" >&2
    fail "startup profiling failed (exit $profile_status)"
  fi
  [[ ! -s "$STAGE/profile.stderr" ]] || { cat "$STAGE/profile.stderr"; fail 'profile startup errors'; }
  grep -q '\[PROFILE\].*Fastfetch' "$STAGE/profile.log" || fail 'profile stage missing'
  # CI 默认没有控制终端；另造 PTY，覆盖用户从 SSH/终端启动诊断的路径。
  if [[ ${OSTYPE:-} == linux* ]] && command -v script >/dev/null; then
    export PROFILE_MANAGER="$ROOT/scripts/manage.sh"
    if script -q -e -c 'bash "$PROFILE_MANAGER" --profile-startup --yes' "$STAGE/profile.tty.log" </dev/null > "$STAGE/profile.tty.stdout" 2> "$STAGE/profile.tty.stderr"; then :
    else
      profile_status=$?
      cat "$STAGE/profile.tty.stderr" "$STAGE/profile.tty.stdout" >&2
      fail "startup profiling under PTY failed (exit $profile_status)"
    fi
    grep -q -- '--- zprof ---' "$STAGE/profile.tty.stdout" || fail 'PTY profiling did not reach zprof'
    pass 'startup profiling with a controlling terminal'
  else
    echo 'SKIP: Linux util-linux script unavailable; PTY profiling test not run'
  fi
  pass 'Zsh switches, local extension ordering and opt-in profiling'
else
  echo 'SKIP: Zsh runtime unavailable; Linux CI runs flag/local/profile tests'
fi
pass 'management suite completed'
