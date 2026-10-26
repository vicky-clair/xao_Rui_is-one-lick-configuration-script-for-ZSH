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
# ------------------------------------------------------------------------------
# 1. 管理入口 Dry-Run 预演路由隔离测试：
# 验证所有管理操作在 --dry-run 模式下均不写状态文件、不调用网络或包管理工具
# ------------------------------------------------------------------------------
for action in --disable --enable --doctor --configure --profile-startup --retry-failed --list-backups; do
  bash "$ROOT/install.sh" "$action" --dry-run > "$STAGE/dry.log"
done
[[ ! -e "$XDG_STATE_HOME" ]] || fail 'management dry run wrote state'
[[ ! -e "$AUDIT_MARKER" ]] || fail 'management dry run invoked network or package tools'
for action in --set --diff-backup --restore-backup; do
  bash "$ROOT/install.sh" "$action" fixture --dry-run > "$STAGE/dry.log"
done
pass 'management dry-run dispatch has no state writes'

# ------------------------------------------------------------------------------
# 2. 停用与恢复完整闭环测试：
# 验证停用/恢复幂等性、.zwc 字节码退役，以及用户在停用期间编辑配置后的覆盖保护
# ------------------------------------------------------------------------------
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

# ------------------------------------------------------------------------------
# 3. 布尔选项编辑安全性与防注入测试：
# 验证 --set 仅通过纯文本处理更新键值，保留未修改行与注释，严防代码注入执行
# ------------------------------------------------------------------------------
printf '# keep comment\nZSH_PROJECT_BANNER=1\nprintf MALICIOUS > "$HOME/executed-options"\n' > "$HOME/.zsh-project-options"
manage --set banner=0 --yes
grep -qx ZSH_PROJECT_BANNER=0 "$HOME/.zsh-project-options" || fail 'option not set'
manage --set television=0 --yes
grep -qx ZSH_PROJECT_TELEVISION=0 "$HOME/.zsh-project-options" || fail 'television option not set'
manage --set tv-keys=1 --yes
grep -qx ZSH_PROJECT_TV_KEYBINDINGS=1 "$HOME/.zsh-project-options" || fail 'tv-keys option not set'
manage --set tre=0 --yes
grep -qx ZSH_PROJECT_TRE=0 "$HOME/.zsh-project-options" || fail 'tre option not set'
manage --set tmux-auto=0 --yes
grep -qx ZSH_PROJECT_TMUX_AUTO=0 "$HOME/.zsh-project-options" || fail 'tmux-auto option not set'
grep -qx '# keep comment' "$HOME/.zsh-project-options" || fail 'comment lost'
[[ ! -f "$HOME/executed-options" ]] || fail 'manager executed options'
if manage --set 'banner=$(touch bad)' --yes; then fail 'invalid option accepted'; fi
pass 'option editing preserves unknown content without evaluating it'

# ------------------------------------------------------------------------------
# 4. 差异对比与基于作用域 (scope) 的快照恢复测试：
# 仅恢复指定 scope（如 zsh 不触碰 tmux），比对操作后校验和防范误覆盖
# ------------------------------------------------------------------------------
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

# ------------------------------------------------------------------------------
# 5. 恢复原本不存在的文件（absent 状态）：
# 清理部署后生成的文件及其 .zwc 编译字节码缓存
# ------------------------------------------------------------------------------
echo absent > "$backup/.zshrc.state"
echo compiled > "$HOME/.zshrc.zwc"
if command -v sha256sum >/dev/null; then sha256sum "$HOME/.zshrc" | cut -d ' ' -f1 > "$backup/.zshrc.sha256"
else shasum -a 256 "$HOME/.zshrc" | cut -d ' ' -f1 > "$backup/.zshrc.sha256"; fi
manage --restore-backup "$backup" --scope zsh --yes
[[ ! -e "$HOME/.zshrc" && ! -e "$HOME/.zshrc.zwc" ]] || fail 'absent restore left source or bytecode'
echo '# zsh-project' > "$HOME/.zshrc"
pass 'absent restore retires compiled configuration'

# ------------------------------------------------------------------------------
# 6. 独立失败组件重试与隔离保护：
# 只针对失败清单中指定的组件进行重试，不重写 Zsh 配置，安全保留未重试的失败项，
# 拦截非法组件参数（如路径遍历 ../../bad）
# ------------------------------------------------------------------------------
printf '#!/usr/bin/env bash\necho Darwin\n' > "$STAGE/bin/uname"
printf '#!/usr/bin/env bash\nexit 0\n' > "$STAGE/bin/fzf"
for tool in brew sudo curl; do printf '#!/usr/bin/env bash\nexit 1\n' > "$STAGE/bin/$tool"; done
chmod +x "$STAGE/bin/"*
# 各环境统一隔离 PATH，避免宿主机全局/用户目录安装的外部工具（如 cargo/vfox/local bin）泄漏干扰断言
export PATH="$STAGE/bin:/usr/local/bin:/usr/bin:/bin"
printf 'fzf\nlazydocker\n' > "$XDG_STATE_HOME/zsh-project/failed-components"
cp "$HOME/.zshrc" "$STAGE/pre-retry"
manage --retry-failed fzf --yes
grep -qx lazydocker "$XDG_STATE_HOME/zsh-project/failed-components" || fail 'retry erased unrelated failure'
cmp "$HOME/.zshrc" "$STAGE/pre-retry" || fail 'retry redeployed config'
printf 'fzf\n' > "$XDG_STATE_HOME/zsh-project/failed-components"
manage --retry-failed --yes
[[ ! -s "$XDG_STATE_HOME/zsh-project/failed-components" ]] || fail 'single item retry did not clear failed-components'
if manage --retry-failed '../../bad' --yes; then fail 'invalid component accepted'; fi
if bash "$ROOT/scripts/retry_tools.sh" '../../bad' --dry-run; then fail 'invalid retry dry run accepted'; fi
printf 'fzf\nlazydocker\n' > "$XDG_STATE_HOME/zsh-project/failed-components"
if manage --retry-failed lazydocker --yes; then fail 'failed package/download retry reported success'; fi
grep -qx lazydocker "$XDG_STATE_HOME/zsh-project/failed-components" || fail 'failed retry lost component'
grep -qx fzf "$XDG_STATE_HOME/zsh-project/failed-components" || fail 'failed retry erased unrelated component'
cmp "$HOME/.zshrc" "$STAGE/pre-retry" || fail 'failed retry modified configuration'
pass 'component retry leaves configuration and unrelated failures intact'

# ------------------------------------------------------------------------------
# 7. Zsh 运行期开关、本地扩展加载顺序与启动耗时诊断验证
# ------------------------------------------------------------------------------
if command -v zsh >/dev/null 2>&1; then
  # 环境缺少 timeout/gtimeout 命令时构建微型透传兼容替身
  if ! command -v timeout >/dev/null 2>&1 && ! command -v gtimeout >/dev/null 2>&1; then
    cat <<'EOF' > "$STAGE/bin/timeout"
#!/usr/bin/env bash
while (($#)); do
  case "$1" in
    -k) shift 2 ;;
    [0-9]*s|[0-9]*) shift; break ;;
    *) break ;;
  esac
done
exec "$@"
EOF
    chmod +x "$STAGE/bin/timeout"
  fi
  mkdir -p "$HOME/powerlevel10k" "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"
  : > "$HOME/.oh-my-zsh/oh-my-zsh.sh"
  : > "$HOME/powerlevel10k/powerlevel10k.zsh-theme"
  # 验证本地扩展 ~/.zshrc.local 先于语法高亮加载，确保别名在语法高亮阶段已被识别
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

  # ------------------------------------------------------------------------------
  # 8. 启动耗时分析 (--profile-startup) 阶段耗时输出验证
  # ------------------------------------------------------------------------------
  if manage --profile-startup --yes > "$STAGE/profile.log" 2> "$STAGE/profile.stderr"; then :
  else
    profile_status=$?
    cat "$STAGE/profile.stderr" "$STAGE/profile.log" >&2
    fail "startup profiling failed (exit $profile_status)"
  fi
  [[ ! -s "$STAGE/profile.stderr" ]] || { cat "$STAGE/profile.stderr"; fail 'profile startup errors'; }
  grep -q '\[PROFILE\].*Fastfetch' "$STAGE/profile.log" || fail 'profile stage missing'

  # ------------------------------------------------------------------------------
  # 9. 真实伪终端 (PTY) 环境下的控制终端诊断测试（覆盖 SSH/终端真实运行路径）
  # ------------------------------------------------------------------------------
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
  elif [[ ${OSTYPE:-} == darwin* ]] && command -v script >/dev/null; then
    # macOS 原生 BSD script 进程伪装支持（参数语法与 Linux util-linux 不同）
    export PROFILE_MANAGER="$ROOT/scripts/manage.sh"
    if script -q "$STAGE/profile.tty.log" bash "$PROFILE_MANAGER" --profile-startup --yes </dev/null > "$STAGE/profile.tty.stdout" 2> "$STAGE/profile.tty.stderr"; then :
    else
      profile_status=$?
      cat "$STAGE/profile.tty.stderr" "$STAGE/profile.tty.stdout" >&2
      fail "startup profiling under PTY failed (exit $profile_status)"
    fi
    grep -q -- '--- zprof ---' "$STAGE/profile.tty.stdout" || fail 'PTY profiling did not reach zprof'
    pass 'startup profiling with a controlling terminal'
  else
    echo 'SKIP: Linux/macOS script unavailable; PTY profiling test not run'
  fi
  pass 'Zsh switches, local extension ordering and opt-in profiling'
else
  echo 'SKIP: Zsh runtime unavailable; Linux CI runs flag/local/profile tests'
fi
pass 'management suite completed'
