#!/usr/bin/env bash
# 配置管理：不卸载插件或应用，不读取/执行用户选项文件中的代码。
set -Eeuo pipefail
export LC_ALL=C
# 仅在非测试环境下补全常用执行路径，避免子进程缺失命令
[[ -z "${ZSH_PROJECT_TEST_MARKER:-${AUDIT_MARKER:-}}" ]] && export PATH="$HOME/.local/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:/opt/nvim:$HOME/go/bin:$HOME/.cargo/bin:$HOME/.local/share/pnpm:$HOME/.version-fox/sdks/golang/packages/bin:$PATH"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/zsh-project"
ACTION='' ARG='' SCOPE=zsh DRY=0 YES=0 LOCKED=0
# 错误退出辅助函数：向 stderr 输出格式化错误信息并终止执行
fail() { printf '错误：%s\n' "$*" >&2; exit 1; }

# 用户操作确认函数：在 --yes 参数下静默通过，否则要求物理交互 TTY 并提示 [y/N]
confirm() {
  ((YES)) && return 0
  [[ -t 0 ]] || fail '需要交互确认；自动化测试可显式使用 --yes'
  local answer
  read -r -p "$1 [y/N] " answer
  [[ "$answer" == y || "$answer" == Y ]]
}

# 每次仅接受一个管理动作；范围与确认选项由后续动作共同使用。
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

# ==============================================================================
# 核心安全与原子操作辅助函数
# ==============================================================================

# 计算文件 SHA-256 哈希值：
# 缺失文件输出固定标记 'missing'，以精准区分“原本不存在”与“内容已修改”
calc_file_hash() {
  if [[ ! -e "$1" ]]; then printf 'missing\n'
  elif command -v sha256sum >/dev/null; then sha256sum "$1" | cut -d ' ' -f1
  else shasum -a 256 "$1" | cut -d ' ' -f1; fi
}

# 普通文件安全检查：
# 严格拒绝符号链接、设备文件或套接字，防止配置写入被重定向攻击至系统关键路径
regular() { [[ ! -L "$1" && ( ! -e "$1" || -f "$1" ) ]] || fail "拒绝链接或非普通文件：$1"; }

# 进程排他锁：
# 基于 Linux/Unix mkdir 系统调用的原子性保证，阻止多进程并发执行产生配置竞争
lock() {
  mkdir -p "$STATE"
  mkdir "$STATE/manage.lock" 2>/dev/null || fail '已有管理操作运行，或上次异常留下 manage.lock，请先检查'
  LOCKED=1
}

# 进程退出自动解锁钩子：仅当本进程真正持有锁时才执行 rmdir 释放
cleanup() { if ((LOCKED)); then rmdir "$STATE/manage.lock" 2>/dev/null || true; fi; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# 创建配置快照：
# 记录操作前的文件内容、存在状态（present/absent）以及当前用户归属信息
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
    calc_file_hash "$HOME/$file" > "$SNAP/$file.sha256"
  done
}

# 登记操作后状态：记录操作完成后的文件哈希，作为后续回退时检测用户是否自行修改的基准
record() { local file; for file in "$@"; do calc_file_hash "$HOME/$file" > "$SNAP/$file.sha256"; done; printf '备份：%s\n' "$SNAP"; }

# Zsh 编译字节码退役函数：
# 将现有的 .zwc 编译缓存移至快照中，确保新写入的配置能即刻生效，避免命中旧缓存
retire_bytecode() {
  local target=$1
  if [[ -e "$target.zwc" || -L "$target.zwc" ]]; then
    regular "$target.zwc"
    mv "$target.zwc" "$SNAP/retired.${target##*/}.zwc"
  fi
}

# 原子安全写入函数：
# 在 HOME 目录下创建具备 0600 严格权限的临时文件，完成字节码退役后通过 mv 原子覆盖
atomic_copy() {
  local source=$1 target=$2 tmp
  regular "$target"
  tmp=$(mktemp "$HOME/.zsh-project-write.XXXXXXXX")
  cp "$source" "$tmp"
  chmod 600 "$tmp"
  retire_bytecode "$target"
  mv -f "$tmp" "$target"
}

# 加载并严格校验备份归属：
# 验证 manifest 确保备份目录属于当前用户，按 scope (zsh/tmux/all) 过滤有效受管文件
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

# 安全读取布尔配置选项：
# 使用严格正则表达式截取行末最后一次赋值，绝不 source 或 eval 用户选项文件
get_option() {
  local key=$1 default=$2 value=''
  if [[ -f "$HOME/.zsh-project-options" ]]; then
    value=$(sed -n "s/^${key}=\([01]\)$/\1/p" "$HOME/.zsh-project-options" | tail -n 1)
  fi
  printf '%s\n' "${value:-$default}"
}

# 选项名称到内部变量映射函数：
# 限制可修改的配置项在白名单内，防止意外写入非法变量
option_key() {
  case "$1" in
    full) echo ZSH_PROJECT_FULL ;; vfox) echo ZSH_PROJECT_VFOX ;;
    lazydocker) echo ZSH_PROJECT_LAZYDOCKER ;; lazygit) echo ZSH_PROJECT_LAZYGIT ;; tmux) echo ZSH_PROJECT_TMUX ;;
    tmux-auto) echo ZSH_PROJECT_TMUX_AUTO ;;
    banner) echo ZSH_PROJECT_BANNER ;; fastfetch) echo ZSH_PROJECT_FASTFETCH ;;
    timer) echo ZSH_PROJECT_TIMER ;; auto-update) echo ZSH_PROJECT_AUTO_CHECK_UPDATE ;;
    television|tv) echo ZSH_PROJECT_TELEVISION ;;
    tv-keys|tv-keybindings) echo ZSH_PROJECT_TV_KEYBINDINGS ;;
    tre) echo ZSH_PROJECT_TRE ;;
    *) fail '可选项：full vfox lazydocker lazygit tmux tmux-auto banner fastfetch timer auto-update television tv-keys tre' ;;
  esac
}

# 设置单个功能开关：
# 先完成用户确认、排他锁加锁、快照备份，再按行替换设置并原子写回
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

# ==============================================================================
# 各管理动作分发执行分支
# ==============================================================================
case "$ACTION" in
  # --- 停用配置：备份原配置并部署安全最小空配置，保留其他应用、插件与 tmux ---
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

  # --- 恢复配置：将停用前备份的受管配置还原，校验哈希确保未被外部篡改 ---
  --enable)
    SCOPE=zsh
    [[ -f "$STATE/disabled" && ! -L "$STATE/disabled" ]] || fail '没有可恢复的停用记录'
    ARG=$(cat "$STATE/disabled"); load_backup
    [[ -f "$ARG/.zshrc.sha256" && $(calc_file_hash "$HOME/.zshrc") == "$(cat "$ARG/.zshrc.sha256")" ]] || fail '停用后的 .zshrc 已修改，拒绝覆盖'
    confirm '恢复停用前的 .zshrc？' || exit 0
    lock; snapshot .zshrc
    atomic_copy "$ARG/.zshrc" "$HOME/.zshrc"
    record .zshrc
    rm "$STATE/disabled"
    echo '已恢复，新开终端验证。'
    ;;

  # --- 命令行脚本化修改单项配置开关 ---
  --set) set_option "$ARG" ;;

  # --- 交互式终端配置菜单：列出全部支持的功能开关并接受修改 ---
  --configure)
    [[ -t 0 ]] || fail '配置菜单需要交互终端；脚本化设置请用 --set banner=0'
    echo '可选项（0=关闭，1=开启；不安装/卸载软件）：'
    for name in full vfox lazydocker lazygit tmux tmux-auto banner fastfetch timer auto-update television tv-keys tre; do
      key=$(option_key "$name"); default=0
      case "$name" in banner|fastfetch|timer|auto-update|lazygit|lazydocker|television|tre|tmux-auto) default=1 ;; esac
      printf '  %s=%s\n' "$name" "$(get_option "$key" "$default")"
    done
    read -r -p '输入一项设置，如 banner=0；直接回车取消：' choice
    [[ -z "$choice" ]] || set_option "$choice"
    ;;
  # --- 列出所有安装与配置管理历史备份记录及受管文件状态 ---
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

  # --- 比较配置差异 (--diff-backup) 或从历史备份安全还原配置 (--restore-backup) ---
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
        [[ -f "$ARG/$file.sha256" && $(calc_file_hash "$HOME/$file") == "$(cat "$ARG/$file.sha256")" ]] || fail "$file 在安装后发生变化，请手动比较后恢复"
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

  # --- 只读配置健康体检：检查配置语法、OMZ生态、23项常用CLI工具及版本 ---
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
    if [[ -f "$HOME/.tmux.conf" ]]; then
      echo "PASS: .tmux.conf"
      if [[ -d "$HOME/.tmux/plugins/tpm" ]]; then echo "PASS: .tmux/plugins/tpm"; else echo "WARN: 缺少 .tmux/plugins/tpm"; issues=$((issues+1)); fi
      if [[ -d "$HOME/.tmux/plugins/tmux-tokyo-night" ]]; then echo "PASS: .tmux/plugins/tmux-tokyo-night"; else echo "WARN: 缺少 .tmux/plugins/tmux-tokyo-night"; issues=$((issues+1)); fi
      if [[ $(uname -s) == Darwin ]]; then
        _bash_ver=$(bash -c 'echo "${BASH_VERSINFO[0]:-0}"' 2>/dev/null || echo 0)
        if (( _bash_ver < 4 )); then
          echo "WARN: macOS 当前 Bash 版本 ($_bash_ver) < 4.0，可能导致 Tmux Tokyo Night 状态栏脚本异常；建议执行 brew install bash"
          issues=$((issues+1))
        else
          echo "PASS: Bash $_bash_ver (>= 4.0, 满足 Tmux 现代化主题需求)"
        fi
      fi
    fi
    for tool in zsh git fzf fd fdfind bat batcat eza zoxide yazi nvim vfox lazydocker lazygit tmux fastfetch tv tre agrep tre-agrep rg jq ffmpeg 7z 7zz pdftoppm magick convert resvg; do
      if location=$(command -v "$tool"); then printf 'FOUND: %s -> %s\n' "$tool" "$location"; else printf 'INFO: 未在当前 PATH 中找到 %s（可选组件不一定需要）\n' "$tool"; fi
    done
    limiter=$(command -v timeout || command -v gtimeout || true)
    if [[ -n "$limiter" ]]; then
      for tool in zsh git fzf fd bat eza zoxide yazi nvim vfox lazydocker lazygit tmux fastfetch tv tre agrep rg jq ffmpeg 7z 7zz pdftoppm magick resvg; do
        command -v "$tool" >/dev/null || continue
        version=""
        # 查询各命令行工具版本：不同工具对版本参数有严格要求
        # - ffmpeg: 必须使用单短横线 `-version`，且指定 `-nostdin </dev/null` 避免监听键盘交互导致体检阻塞
        # - 7z/7zz: 不支持 `--version`（会以退出码 7 失败），且 `-v` 是分卷压缩参数；查看版本输出最安全的是帮助参数 `-h`
        # - pdftoppm: Poppler 工具集只接受 `-v`（传入 `--version` 会被当做未知选项）
        case "$tool" in
          tmux)
            version=$("$limiter" -k 1s 2s tmux -V </dev/null 2>&1 || true)
            ;;
          ffmpeg)
            version=$("$limiter" -k 1s 2s ffmpeg -nostdin -version </dev/null 2>&1 || true)
            ;;
          7z|7zz)
            version=$("$limiter" -k 1s 2s "$tool" -h </dev/null 2>&1 || "$limiter" -k 1s 2s "$tool" </dev/null 2>&1 || true)
            ;;
          pdftoppm)
            version=$("$limiter" -k 1s 2s pdftoppm -v </dev/null 2>&1 || true)
            ;;
          yazi)
            # yazi 采用大写 -V 输出版本；通过 setsid/--foreground 隔离终端控制权并设置超时，避免无 TTY 下触发 SIGTTOU 挂死
            if command -v setsid >/dev/null 2>&1; then
              version=$(setsid yazi -V </dev/null 2>&1 || true)
            elif "$limiter" --help 2>&1 | grep -q -- --foreground; then
              version=$("$limiter" --foreground -k 1s 2s yazi -V </dev/null 2>&1 || true)
            else
              version=$("$limiter" -k 1s 2s yazi -V </dev/null 2>&1 || true)
            fi
            # 去除终端图形协议探测序列（如 Gi=31...;AAAA）保留标准版本文本
            version=$(printf "%s\n" "$version" | sed -e 's/^.*\(Yazi [0-9]\)/\1/' || true)
            ;;
          *)
            version=$("$limiter" -k 1s 2s "$tool" --version </dev/null 2>&1 || "$limiter" -k 1s 2s "$tool" -version </dev/null 2>&1 || "$limiter" -k 1s 2s "$tool" -V </dev/null 2>&1 || "$limiter" -k 1s 2s "$tool" -v </dev/null 2>&1 || true)
            ;;
        esac
        first_line=$(printf '%s\n' "$version" | grep -v '^[[:space:]]*$' | head -n 1 || true)
        if [[ -n "$first_line" ]]; then
          printf 'VERSION: %s: %s\n' "$tool" "$first_line"
        else
          printf 'INFO: %s 已安装但未返回标准版本输出\n' "$tool"
        fi
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
  # --- 会话冷启动耗时剖析：通过 zsh/zprof 对当前配置进行微秒级函数与初始化耗时分析 ---
  --profile-startup)
    command -v zsh >/dev/null || fail '缺少 Zsh'
    timer=$(command -v timeout || command -v gtimeout || true)
    [[ -n "$timer" ]] || fail '缺少 timeout/gtimeout，拒绝运行可能阻塞的初始化'
    confirm '将真实执行一次当前 .zshrc 和目录钩子，可能触发工具正常缓存写入；最多约 32 秒。继续？' || exit 0
    # timeout 创建独立进程组；禁用 Zsh 作业控制，避免子 Shell 在执行配置前争抢前台 TTY。
    # 保留 -i 以加载交互配置，空输入避免诊断读取按键；仍由 timeout 清理整个进程组。
    # shellcheck disable=SC2016
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

  # --- 重试失败组件：读取记录或指定组件名称，仅通过包管理器/Release下载安装，不改写配置 ---
  --retry-failed)
    args=(); [[ -z "$ARG" ]] || args+=("$ARG")
    ((YES == 0)) || args+=(--yes)
    bash "$ROOT/scripts/retry_tools.sh" ${args[@]+"${args[@]}"}
    ;;
esac
