#!/usr/bin/env bash
# 配置管理：不卸载插件或应用，不读取/执行用户选项文件中的代码。
set -Eeuo pipefail
export LC_ALL=C
ROOT=$(cd "$(dirname "$0")/.." && pwd)
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/zsh-project"
ACTION='' ARG='' SCOPE=zsh DRY=0 YES=0 LOCKED=0
fail() { printf '错误：%s\n' "$*" >&2; exit 1; }
confirm() {
  ((YES)) && return 0
  [[ -t 0 ]] || fail '需要交互确认；自动化测试可显式使用 --yes'
  local answer
  read -r -p "$1 [y/N] " answer
  [[ "$answer" == y || "$answer" == Y ]]
}
while (($#)); do
  case "$1" in
    --disable|--enable|--doctor|--configure|--profile-startup|--list-backups)
      [[ -z "$ACTION" ]] || fail '一次只执行一个管理操作'; ACTION=$1 ;;
    --diff-backup|--restore-backup|--set)
      [[ -z "$ACTION" && $# -ge 2 ]] || fail '操作冲突或缺少参数'; ACTION=$1; ARG=$2; shift ;;
    --retry-failed)
      [[ -z "$ACTION" ]] || fail '一次只执行一个操作'; ACTION=$1
      if (($# > 1)) && [[ "$2" != --* ]]; then ARG=$2; shift; fi ;;
    --scope) (($# > 1)) || fail '缺少 scope'; SCOPE=$2; shift ;;
    --dry-run) DRY=1 ;;
    --yes) YES=1 ;;
    --lang) (($# > 1)) || fail '缺少语言'; shift ;;
    *) fail "未知管理参数：$1" ;;
  esac
  shift
done
[[ -n "$ACTION" ]] || fail '请指定管理操作'
[[ "$SCOPE" == zsh || "$SCOPE" == tmux || "$SCOPE" == all ]] || fail 'scope 必须为 zsh、tmux 或 all'
[[ -z "${ZDOTDIR:-}" || "$ZDOTDIR" == "$HOME" ]] || fail '自定义 ZDOTDIR 暂不自动管理'
[[ -d "$HOME" && "$HOME" == /* ]] || fail '无效 HOME'
if ((DRY)); then printf '[DRY RUN] %s %s scope=%s；不写文件、不联网、不执行配置。\n' "$ACTION" "$ARG" "$SCOPE"; exit 0; fi

hash() {
  if [[ ! -e "$1" ]]; then printf 'missing\n'
  elif command -v sha256sum >/dev/null; then sha256sum "$1" | cut -d ' ' -f1
  else shasum -a 256 "$1" | cut -d ' ' -f1; fi
}
regular() { [[ ! -L "$1" && ( ! -e "$1" || -f "$1" ) ]] || fail "拒绝链接或非普通文件：$1"; }
lock() {
  mkdir -p "$STATE"
  mkdir "$STATE/manage.lock" 2>/dev/null || fail '已有管理操作运行，或上次异常留下 manage.lock，请先检查'
  LOCKED=1
}
cleanup() { if ((LOCKED)); then rmdir "$STATE/manage.lock" 2>/dev/null || true; fi; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
snapshot() {
  local file
  SNAP=$(mktemp -d "$STATE/manage-XXXXXXXX")
  chmod 700 "$SNAP"
  printf '%s\n' "$HOME" > "$SNAP/manifest"
  printf '%s\n' "$ACTION" > "$SNAP/action"
  for file in "$@"; do
    regular "$HOME/$file"
    if [[ -f "$HOME/$file" ]]; then
      cp -p "$HOME/$file" "$SNAP/$file"
      echo present > "$SNAP/$file.state"
    else echo absent > "$SNAP/$file.state"; fi
    hash "$HOME/$file" > "$SNAP/$file.sha256"
  done
}
record() { local file; for file in "$@"; do hash "$HOME/$file" > "$SNAP/$file.sha256"; done; printf '备份：%s\n' "$SNAP"; }
retire_bytecode() {
  local target=$1
  if [[ -e "$target.zwc" || -L "$target.zwc" ]]; then
    regular "$target.zwc"
    mv "$target.zwc" "$SNAP/retired.${target##*/}.zwc"
  fi
}
atomic_copy() {
  local source=$1 target=$2 tmp
  regular "$target"
  tmp=$(mktemp "$HOME/.zsh-project-write.XXXXXXXX")
  cp "$source" "$tmp"
  chmod 600 "$tmp"
  retire_bytecode "$target"
  mv -f "$tmp" "$target"
}
load_backup() {
  [[ -d "$ARG" && ! -L "$ARG" && -f "$ARG/manifest" ]] || fail '无效备份目录'
  [[ $(head -n 1 "$ARG/manifest") == "$HOME" ]] || fail '备份属于其它 HOME'
  FILES=()
  local file
  for file in .zshrc .zsh-project-options .p10k.zsh .tmux.conf; do
    [[ -f "$ARG/$file.state" ]] || continue
    [[ "$SCOPE" != zsh || "$file" != .tmux.conf ]] || continue
    [[ "$SCOPE" != tmux || "$file" == .tmux.conf ]] || continue
    regular "$HOME/$file"
    regular "$HOME/$file.zwc"
    case $(cat "$ARG/$file.state") in
      present) [[ -f "$ARG/$file" && ! -L "$ARG/$file" ]] || fail '备份原文件缺失或为链接' ;;
      absent) ;;
      *) fail '无效备份状态' ;;
    esac
    FILES+=("$file")
  done
  ((${#FILES[@]})) || fail '此备份没有选定范围的文件'
}
get_option() {
  local key=$1 default=$2 value=''
  if [[ -f "$HOME/.zsh-project-options" ]]; then
    value=$(sed -n "s/^${key}=\([01]\)$/\1/p" "$HOME/.zsh-project-options" | tail -n 1)
  fi
  printf '%s\n' "${value:-$default}"
}
option_key() {
  case "$1" in
    full) echo ZSH_PROJECT_FULL ;; vfox) echo ZSH_PROJECT_VFOX ;;
    lazydocker) echo ZSH_PROJECT_LAZYDOCKER ;; tmux) echo ZSH_PROJECT_TMUX ;;
    banner) echo ZSH_PROJECT_BANNER ;; fastfetch) echo ZSH_PROJECT_FASTFETCH ;;
    timer) echo ZSH_PROJECT_TIMER ;; auto-update) echo ZSH_PROJECT_AUTO_CHECK_UPDATE ;;
    *) fail '可选项：full vfox lazydocker tmux banner fastfetch timer auto-update' ;;
  esac
}
set_option() {
  local name=${1%%=*} value=${1#*=} key tmp
  [[ "$1" == *=* && ( "$value" == 0 || "$value" == 1 ) ]] || fail '格式应为选项=0或1'
  key=$(option_key "$name")
  regular "$HOME/.zsh-project-options"
  confirm "设置 $name=$value？新 Zsh 会话生效" || return 0
  lock
  snapshot .zsh-project-options
  tmp="$SNAP/options.new"
  if [[ -f "$HOME/.zsh-project-options" ]]; then
    # 仅删除对应的赋值行，不 source 或 eval 选项文件。
    sed "/^[[:space:]]*${key}=/d" "$HOME/.zsh-project-options" > "$tmp"
  else : > "$tmp"; fi
  printf '\n%s=%s\n' "$key" "$value" >> "$tmp"
  atomic_copy "$tmp" "$HOME/.zsh-project-options"
  record .zsh-project-options
}

case "$ACTION" in
  --disable)
    [[ ! -e "$STATE/disabled" ]] || { echo '已经停用，无需重复操作。'; exit 0; }
    regular "$HOME/.zshrc"
    [[ -f "$HOME/.zshrc" ]] || fail '没有 .zshrc'
    grep -q 'zsh-project' "$HOME/.zshrc" || fail '当前配置没有项目标识，请先确认来源'
    confirm '停用项目 Zsh 配置？保留 tmux、默认 Shell、插件、应用和 .zshenv' || exit 0
    lock; snapshot .zshrc
    printf '# zsh-project: disabled\n# 用 bash install.sh --enable 恢复；保留空配置避免首次配置向导。\n' > "$SNAP/disabled.zshrc"
    atomic_copy "$SNAP/disabled.zshrc" "$HOME/.zshrc"
    record .zshrc
    printf '%s\n' "$SNAP" > "$STATE/disabled"
    echo '已停用。新开终端生效；原有会话保持原状态。'
    ;;
  --enable)
    SCOPE=zsh
    [[ -f "$STATE/disabled" && ! -L "$STATE/disabled" ]] || fail '没有可恢复的停用记录'
    ARG=$(cat "$STATE/disabled"); load_backup
    [[ -f "$ARG/.zshrc.sha256" && $(hash "$HOME/.zshrc") == "$(cat "$ARG/.zshrc.sha256")" ]] || fail '停用后的 .zshrc 已修改，拒绝覆盖'
    confirm '恢复停用前的 .zshrc？' || exit 0
    lock; snapshot .zshrc
    atomic_copy "$ARG/.zshrc" "$HOME/.zshrc"
    record .zshrc
    rm "$STATE/disabled"
    echo '已恢复，新开终端验证。'
    ;;
  --set) set_option "$ARG" ;;
  --configure)
    [[ -t 0 ]] || fail '配置菜单需要交互终端；脚本化设置请用 --set banner=0'
    echo '可选项（0=关闭，1=开启；不安装/卸载软件）：'
    for name in full vfox lazydocker tmux banner fastfetch timer auto-update; do
      key=$(option_key "$name"); default=0
      case "$name" in banner|fastfetch|timer|auto-update) default=1 ;; esac
      printf '  %s=%s\n' "$name" "$(get_option "$key" "$default")"
    done
    read -r -p '输入一项设置，如 banner=0；直接回车取消：' choice
    [[ -z "$choice" ]] || set_option "$choice"
    ;;
  --list-backups)
    for dir in "$STATE"/install-* "$STATE"/manage-*; do
      [[ -f "$dir/manifest" ]] || continue
      [[ $(head -n 1 "$dir/manifest") == "$HOME" ]] || continue
      printf '\n%s\n' "$dir"
      ls -ld "$dir"
      for file in .zshrc .zsh-project-options .p10k.zsh .tmux.conf; do
        [[ ! -f "$dir/$file.state" ]] || printf '  %s: %s\n' "$file" "$(cat "$dir/$file.state")"
      done
    done
    ;;
  --diff-backup|--restore-backup)
    load_backup
    for file in "${FILES[@]}"; do
      echo "--- $file（备份原状态 -> 当前）"
      original=/dev/null; current=/dev/null
      [[ $(cat "$ARG/$file.state") != present ]] || original="$ARG/$file"
      [[ ! -f "$HOME/$file" ]] || current="$HOME/$file"
      diff -u "$original" "$current" || { status=$?; ((status == 1)) || exit "$status"; }
    done
    [[ "$ACTION" != --restore-backup ]] || {
      [[ ! -e "$STATE/disabled" ]] || fail '配置已停用，请先 enable，避免停用记录与恢复状态冲突'
      for file in "${FILES[@]}"; do
        [[ -f "$ARG/$file.sha256" && $(hash "$HOME/$file") == "$(cat "$ARG/$file.sha256")" ]] || fail "$file 在安装后发生变化，请手动比较后恢复"
      done
      confirm "仅恢复 scope=$SCOPE 的以上配置？" || exit 0
      lock; snapshot "${FILES[@]}"
      for file in "${FILES[@]}"; do
        if [[ $(cat "$ARG/$file.state") == present ]]; then atomic_copy "$ARG/$file" "$HOME/$file"
        else
          retire_bytecode "$HOME/$file"
          [[ ! -f "$HOME/$file" ]] || rm "$HOME/$file"
        fi
      done
      record "${FILES[@]}"
    }
    ;;
  --doctor)
    issues=0
    echo '只读体检：不会 source 配置，不联网，也不自动修复。'
    if [[ ! -f "$HOME/.zshrc" ]]; then echo 'WARN: 缺少 .zshrc'; issues=$((issues+1)); fi
    for file in .zshrc .zshenv .zshrc.local; do
      [[ -f "$HOME/$file" ]] || continue
      if command -v zsh >/dev/null && zsh -n "$HOME/$file"; then echo "PASS: $file 语法"
      else echo "WARN: $file 无法验证"; issues=$((issues+1)); fi
    done
    for path in .oh-my-zsh/oh-my-zsh.sh powerlevel10k/powerlevel10k.zsh-theme .oh-my-zsh/custom/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh .oh-my-zsh/custom/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh; do
      if [[ -r "$HOME/$path" ]]; then echo "PASS: $path"; else echo "WARN: 缺少 $path"; issues=$((issues+1)); fi
    done
    for tool in zsh git fzf fd fdfind bat batcat eza zoxide yazi nvim vfox lazydocker tmux fastfetch; do
      if location=$(command -v "$tool"); then printf 'FOUND: %s -> %s\n' "$tool" "$location"; else printf 'INFO: 未在当前 PATH 中找到 %s（可选组件不一定需要）\n' "$tool"; fi
    done
    limiter=$(command -v timeout || command -v gtimeout || true)
    if [[ -n "$limiter" ]]; then
      for tool in zsh git fzf fd bat eza zoxide yazi nvim vfox lazydocker fastfetch; do
        command -v "$tool" >/dev/null || continue
        if version=$("$limiter" -k 1s 2s "$tool" --version 2>&1); then
          printf 'VERSION: %s: %s\n' "$tool" "${version%%$'\n'*}"
        else printf 'WARN: %s 版本查询失败或超时\n' "$tool"; issues=$((issues+1)); fi
      done
    else echo 'INFO: 没有超时工具，跳过版本查询，避免体检卡住。'; fi
    echo '以下是配置中的钩子/初始化声明（不代表当前会话运行状态）：'
    grep -nE 'chpwd_functions|precmd_functions|vfox activate|compinit|INSTANT_PROMPT' "$HOME/.zshrc" || true
    echo '布尔选项：'
    grep -E '^ZSH_PROJECT_[A-Z_]+=[01]$' "$HOME/.zsh-project-options" 2>/dev/null || true
    echo '当前会话钩子请在 Zsh 用 typeset -p chpwd_functions precmd_functions 查看；doctor 只读取声明和查询版本。'
    printf '体检结束：%s 项需要检查。\n' "$issues"
    ((issues == 0))
    ;;
  --profile-startup)
    command -v zsh >/dev/null || fail '缺少 Zsh'
    timer=$(command -v timeout || command -v gtimeout || true)
    [[ -n "$timer" ]] || fail '缺少 timeout/gtimeout，拒绝运行可能阻塞的初始化'
    confirm '将真实执行一次当前 .zshrc 和目录钩子，可能触发工具正常缓存写入；最多约 32 秒。继续？' || exit 0
    # timeout 创建独立进程组；禁用 Zsh 作业控制，避免子 Shell 在执行配置前争抢前台 TTY。
    # 保留 -i 以加载交互配置，空输入避免诊断读取按键；仍由 timeout 清理整个进程组。
    if ZSH_PROJECT_PROFILING=1 ZSH_PROJECT_AUTO_CHECK_UPDATE=0 "$timer" -k 2s 30s zsh -f +m -i -c 'zmodload zsh/zprof; source "$HOME/.zshrc" || exit $?; print -r -- "--- chpwd hooks ---"; typeset -p chpwd_functions precmd_functions 2>/dev/null; builtin cd -- "$HOME" || exit $?; print -r -- "--- zprof ---"; zprof' </dev/null; then
      :
    else
      status=$?
      if [[ "$status" == 124 || "$status" == 137 ]]; then
        printf '启动诊断超时（退出码 %s），请检查最后一个已输出的阶段或用户初始化脚本。\n' "$status" >&2
      else
        printf '启动诊断失败（退出码 %s），请查看以上输出。\n' "$status" >&2
      fi
      exit "$status"
    fi
    ;;
  --retry-failed)
    args=(); [[ -z "$ARG" ]] || args+=("$ARG")
    ((YES == 0)) || args+=(--yes)
    bash "$ROOT/scripts/retry_tools.sh" "${args[@]}"
    ;;
esac
