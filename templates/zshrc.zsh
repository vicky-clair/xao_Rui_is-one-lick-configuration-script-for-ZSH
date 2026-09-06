# zsh-project 安装模板：跨平台兼容 Linux 与 macOS，支持中英双语提示。
# 在启动新会话后生效；此文件不负责安装软件。
[[ -o interactive ]] || return
typeset -g POWERLEVEL9K_INSTANT_PROMPT=off

[[ -r "$HOME/.zsh-project-options" ]] && source "$HOME/.zsh-project-options"

# ------------------------------------------------------------------------------
# 字符编码与语言环境保障（确保 UTF-8，彻底杜绝 Neovim、Tmux 与终端符号乱码）
# ------------------------------------------------------------------------------
if [[ -z "$LANG" || "$LANG" == "C" || "$LANG" == "POSIX" ]]; then
  if locale -a 2>/dev/null | grep -qi "^C\.utf8$"; then
    export LANG="C.UTF-8"
  elif locale -a 2>/dev/null | grep -qi "en_US\.utf8"; then
    export LANG="en_US.UTF-8"
  elif locale -a 2>/dev/null | grep -qi "zh_CN\.utf8"; then
    export LANG="zh_CN.UTF-8"
  else
    export LANG="C.UTF-8"
  fi
fi
[[ "$LC_ALL" == "C" || "$LC_ALL" == "POSIX" ]] && unset LC_ALL
export LC_CTYPE="${LC_CTYPE:-$LANG}"

# 双语文本输出辅助函数
_zsh_msg() {
  if [[ "${ZSH_PROJECT_LANG:-zh}" == en ]]; then
    print -P "$2"
  else
    print -P "$1"
  fi
}

# 启动计时：使用 Zsh 内置 datetime 模块高精度计时（兼容 Linux 与 macOS）
if zmodload zsh/datetime 2>/dev/null; then
  ZSH_START_TIME=$EPOCHREALTIME
fi

# 跨平台环境变量与 PATH 去重设置
typeset -U path PATH fpath
path=(
  "$HOME/.local/bin"
  "/opt/homebrew/bin"
  "/opt/homebrew/sbin"
  "/usr/local/bin"
  "/usr/local/sbin"
  "/opt/nvim"
  "$HOME/go/bin"
  "$HOME/.cargo/bin"
  "$HOME/.local/share/pnpm"
  "$HOME/.version-fox/sdks/golang/packages/bin"
  $path
)
export PATH

# 终端窗口尺寸监听：确保 SSH / 窗格缩放时行高列宽与物理屏幕保持同步
if [[ -t 0 ]] && command -v stty >/dev/null 2>&1; then
  TRAPWINCH() {
    zle && zle reset-prompt 2>/dev/null || true
  }
fi

if [[ ${ZSH_PROJECT_FULL:-0} == 1 ]] && command -v nvim >/dev/null 2>&1; then
  export EDITOR=nvim
  export VISUAL=nvim
  nvim() {
    # 启动前自适应同步物理窗口尺寸，彻底杜绝部分终端/SSH 默认锁定 80x24 导致无法全屏
    if command -v resize >/dev/null 2>&1; then
      eval "$(resize 2>/dev/null)" || true
    fi
    command nvim "$@"
  }
  alias vim=nvim
  alias vi=nvim
  alias v=nvim
else
  export EDITOR=vi
fi

if [[ ${ZSH_PROJECT_FULL:-0} == 1 ]] && command -v bat >/dev/null 2>&1 && bat --list-themes 2>/dev/null | grep -q "tokyonight_night"; then
  export BAT_THEME="tokyonight_night"
fi

# Oh My Zsh 框架与插件初始化
export ZSH="$HOME/.oh-my-zsh"
ZSH_CUSTOM="$ZSH/custom"
ZSH_THEME=""
plugins=(git sudo extract history-substring-search colored-man-pages zsh-autosuggestions)

# 提前注册额外补全目录
[[ -d "$ZSH_CUSTOM/plugins/zsh-completions/src" ]] && fpath=("$ZSH_CUSTOM/plugins/zsh-completions/src" $fpath)

if [[ -r "$ZSH/oh-my-zsh.sh" ]]; then
  source "$ZSH/oh-my-zsh.sh"
else
  autoload -Uz compinit
  compinit
fi

# 主题及个人外观配置加载
[[ -r "$HOME/powerlevel10k/powerlevel10k.zsh-theme" ]] && source "$HOME/powerlevel10k/powerlevel10k.zsh-theme"
[[ -r "$HOME/.p10k.zsh" ]] && source "$HOME/.p10k.zsh"
typeset -g POWERLEVEL9K_INSTANT_PROMPT=off

# ========================================
# 启动常用工具信息横幅
# ========================================
if [[ -o interactive ]]; then
  _zsh_msg "\n%F{blue}========================================%f\n%F{blue}🔧 正在加载常用工具...%f\n%F{blue}========================================%f\n" "\n%F{blue}========================================%f\n%F{blue}🔧 Loading tools...%f\n%F{blue}========================================%f\n"
fi

# ========================================
# vfox 版本管理初始化
# ========================================
if [[ ${ZSH_PROJECT_VFOX:-0} == 1 ]] && command -v vfox &>/dev/null; then
  local _vfox_cmd=""
  if command -v timeout >/dev/null 2>&1; then
    _vfox_cmd="timeout -k 1s 5s vfox activate zsh"
  elif command -v gtimeout >/dev/null 2>&1; then
    _vfox_cmd="gtimeout -k 1s 5s vfox activate zsh"
  else
    _vfox_cmd="vfox activate zsh"
  fi

  if _vfox_init=$(eval "$_vfox_cmd" 2>/dev/null); then
    if eval "$_vfox_init"; then
      chpwd_functions=("${(@)chpwd_functions:#_vfox_hook}")
      precmd_functions=("${(@)precmd_functions:#_vfox_hook}")
      _zsh_msg "%F{green}✓%f %F{cyan}vfox%f 已加载 (版本管理)" "%F{green}✓%f %F{cyan}vfox%f loaded (version manager)"
    else
      _zsh_msg "%F{yellow}⚠ vfox 初始化脚本执行失败%f" "%F{yellow}⚠ vfox init script execution failed%f"
    fi
  else
    _zsh_msg "%F{yellow}⚠ vfox 初始化失败或超时，本次已跳过%f" "%F{yellow}⚠ vfox init failed or timed out, skipped%f"
  fi
  unset _vfox_init _vfox_cmd
fi

# ========================================
# Yazi 退出后同步终端目录
# ========================================
if [[ ${ZSH_PROJECT_FULL:-0} == 1 ]] && command -v yazi &>/dev/null; then
  function y() {
    local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
    yazi "$@" --cwd-file="$tmp"
    if cwd="$(cat -- "$tmp")" && [[ -n "$cwd" && "$cwd" != "$PWD" ]]; then
      builtin cd -- "$cwd"
    fi
    rm -f -- "$tmp"
  }
  _zsh_msg "%F{green}✓%f %F{cyan}yazi%f 文件管理器已集成 (命令: %F{yellow}y%f)" "%F{green}✓%f %F{cyan}yazi%f file manager integrated (cmd: %F{yellow}y%f)"
fi

# ========================================
# FZF 搜索、预览与快捷键
# ========================================
if [[ ${ZSH_PROJECT_FULL:-0} == 1 ]] && command -v fzf &>/dev/null; then
  if command -v fd &>/dev/null; then
    export FZF_DEFAULT_COMMAND='fd --hidden --strip-cwd-prefix --exclude .git'
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
    export FZF_ALT_C_COMMAND='fd --type=d --hidden --strip-cwd-prefix --exclude .git'
    _zsh_msg "%F{green}✓%f %F{cyan}fd%f 已集成到 FZF" "%F{green}✓%f %F{cyan}fd%f integrated into FZF"
  elif command -v fdfind &>/dev/null; then
    export FZF_DEFAULT_COMMAND='fdfind --hidden --strip-cwd-prefix --exclude .git'
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
    export FZF_ALT_C_COMMAND='fdfind --type=d --hidden --strip-cwd-prefix --exclude .git'
    _zsh_msg "%F{green}✓%f %F{cyan}fdfind%f 已集成到 FZF" "%F{green}✓%f %F{cyan}fdfind%f integrated into FZF"
  fi

  if command -v bat &>/dev/null && command -v eza &>/dev/null; then
    show_file_or_dir_preview='if [ -d {} ]; then eza --tree --color=always {} | head -200; else bat -n --color=always --line-range :500 {}; fi'
    export FZF_CTRL_T_OPTS="--preview '$show_file_or_dir_preview'"
    export FZF_ALT_C_OPTS="--preview 'eza --tree --color=always {} | head -200'"
    _zsh_msg "%F{green}✓%f %F{cyan}bat%f + %F{cyan}eza%f 预览集成完成" "%F{green}✓%f %F{cyan}bat%f + %F{cyan}eza%f preview integrated"
  elif command -v batcat &>/dev/null && command -v eza &>/dev/null; then
    show_file_or_dir_preview='if [ -d {} ]; then eza --tree --color=always {} | head -200; else batcat -n --color=always --line-range :500 {}; fi'
    export FZF_CTRL_T_OPTS="--preview '$show_file_or_dir_preview'"
    export FZF_ALT_C_OPTS="--preview 'eza --tree --color=always {} | head -200'"
    _zsh_msg "%F{green}✓%f %F{cyan}batcat%f + %F{cyan}eza%f 预览集成完成" "%F{green}✓%f %F{cyan}batcat%f + %F{cyan}eza%f preview integrated"
  elif command -v bat &>/dev/null; then
    export FZF_CTRL_T_OPTS="--preview 'bat -n --color=always --line-range :500 {}'"
    _zsh_msg "%F{green}✓%f %F{cyan}bat%f 预览集成完成" "%F{green}✓%f %F{cyan}bat%f preview integrated"
  elif command -v batcat &>/dev/null; then
    export FZF_CTRL_T_OPTS="--preview 'batcat -n --color=always --line-range :500 {}'"
    _zsh_msg "%F{green}✓%f %F{cyan}batcat%f 预览集成完成" "%F{green}✓%f %F{cyan}batcat%f preview integrated"
  elif command -v eza &>/dev/null; then
    export FZF_CTRL_T_OPTS="--preview 'eza --tree --color=always {} | head -200'"
    export FZF_ALT_C_OPTS="--preview 'eza --tree --color=always {} | head -200'"
    _zsh_msg "%F{green}✓%f %F{cyan}eza%f 目录预览集成完成" "%F{green}✓%f %F{cyan}eza%f directory preview integrated"
  fi

  if _zsh_fzf_init=$(fzf --zsh 2>/dev/null); then
    eval "$_zsh_fzf_init"
    _zsh_msg "%F{green}✓%f %F{cyan}fzf%f 模糊查找已加载 (%F{yellow}Ctrl+R%f / %F{yellow}Ctrl+T%f / %F{yellow}Alt+C%f)" "%F{green}✓%f %F{cyan}fzf%f fuzzy finder loaded (%F{yellow}Ctrl+R%f / %F{yellow}Ctrl+T%f / %F{yellow}Alt+C%f)"
  elif [[ -f /usr/share/doc/fzf/examples/key-bindings.zsh ]]; then
    source /usr/share/doc/fzf/examples/key-bindings.zsh
    [[ -f /usr/share/doc/fzf/examples/completion.zsh ]] && source /usr/share/doc/fzf/examples/completion.zsh
    _zsh_msg "%F{green}✓%f %F{cyan}fzf%f 模糊查找已通过系统脚本加载 (%F{yellow}Ctrl+R%f / %F{yellow}Ctrl+T%f / %F{yellow}Alt+C%f)" "%F{green}✓%f %F{cyan}fzf%f fuzzy finder loaded via system script (%F{yellow}Ctrl+R%f / %F{yellow}Ctrl+T%f / %F{yellow}Alt+C%f)"
  elif [[ -f /usr/share/fzf/key-bindings.zsh ]]; then
    source /usr/share/fzf/key-bindings.zsh
    [[ -f /usr/share/fzf/completion.zsh ]] && source /usr/share/fzf/completion.zsh
    _zsh_msg "%F{green}✓%f %F{cyan}fzf%f 模糊查找已通过系统脚本加载 (%F{yellow}Ctrl+R%f / %F{yellow}Ctrl+T%f / %F{yellow}Alt+C%f)" "%F{green}✓%f %F{cyan}fzf%f fuzzy finder loaded via system script (%F{yellow}Ctrl+R%f / %F{yellow}Ctrl+T%f / %F{yellow}Alt+C%f)"
  elif [[ -f "${HOMEBREW_PREFIX:-/opt/homebrew}/opt/fzf/shell/key-bindings.zsh" ]]; then
    source "${HOMEBREW_PREFIX:-/opt/homebrew}/opt/fzf/shell/key-bindings.zsh"
    [[ -f "${HOMEBREW_PREFIX:-/opt/homebrew}/opt/fzf/shell/completion.zsh" ]] && source "${HOMEBREW_PREFIX:-/opt/homebrew}/opt/fzf/shell/completion.zsh"
    _zsh_msg "%F{green}✓%f %F{cyan}fzf%f 模糊查找已通过 Homebrew 脚本加载 (%F{yellow}Ctrl+R%f / %F{yellow}Ctrl+T%f / %F{yellow}Alt+C%f)" "%F{green}✓%f %F{cyan}fzf%f fuzzy finder loaded via Homebrew script (%F{yellow}Ctrl+R%f / %F{yellow}Ctrl+T%f / %F{yellow}Alt+C%f)"
  elif [[ -f "/usr/local/opt/fzf/shell/key-bindings.zsh" ]]; then
    source "/usr/local/opt/fzf/shell/key-bindings.zsh"
    [[ -f "/usr/local/opt/fzf/shell/completion.zsh" ]] && source "/usr/local/opt/fzf/shell/completion.zsh"
    _zsh_msg "%F{green}✓%f %F{cyan}fzf%f 模糊查找已通过 Homebrew 脚本加载 (%F{yellow}Ctrl+R%f / %F{yellow}Ctrl+T%f / %F{yellow}Alt+C%f)" "%F{green}✓%f %F{cyan}fzf%f fuzzy finder loaded via Homebrew script (%F{yellow}Ctrl+R%f / %F{yellow}Ctrl+T%f / %F{yellow}Alt+C%f)"
  elif [[ -f "$HOME/.fzf.zsh" ]]; then
    source "$HOME/.fzf.zsh"
    _zsh_msg "%F{green}✓%f %F{cyan}fzf%f 模糊查找已通过用户配置加载 (%F{yellow}Ctrl+R%f / %F{yellow}Ctrl+T%f / %F{yellow}Alt+C%f)" "%F{green}✓%f %F{cyan}fzf%f fuzzy finder loaded via user config (%F{yellow}Ctrl+R%f / %F{yellow}Ctrl+T%f / %F{yellow}Alt+C%f)"
  else
    _zsh_msg "%F{yellow}⚠ FZF 版本过低不支持 --zsh，请运行 bash install.sh 升级 FZF%f" "%F{yellow}⚠ FZF version too old, please run bash install.sh to upgrade FZF%f"
  fi
  unset _zsh_fzf_init
fi

# ========================================
# 命令别名与工具集成
# ========================================
# 全平台剪贴板互通别名（兼容 macOS pbcopy / Linux X11 xclip / Wayland wl-copy / WSL clip.exe）
if [[ ${ZSH_PROJECT_TMUX:-0} == 1 ]]; then
if command -v pbcopy &>/dev/null; then
  alias clipcopy="pbcopy"
  alias clippaste="pbpaste"
elif command -v wl-copy &>/dev/null; then
  alias clipcopy="wl-copy"
  alias clippaste="wl-paste"
elif command -v xclip &>/dev/null; then
  alias clipcopy="xclip -selection clipboard"
  alias clippaste="xclip -selection clipboard -o"
elif command -v clip.exe &>/dev/null; then
  alias clipcopy="clip.exe"
fi
fi

if [[ ${ZSH_PROJECT_FULL:-0} == 1 ]] && command -v eza &>/dev/null; then
  alias ls="eza --icons=always"
  alias ll="eza -lh --icons=always"
  alias la="eza -lah --icons=always"
  _zsh_msg "%F{green}✓%f %F{cyan}eza%f 现代化 ls 已启用 (别名: %F{yellow}ls%f, %F{yellow}ll%f, %F{yellow}la%f)" "%F{green}✓%f %F{cyan}eza%f modern ls enabled (aliases: %F{yellow}ls%f, %F{yellow}ll%f, %F{yellow}la%f)"
fi

if [[ ${ZSH_PROJECT_LAZYDOCKER:-0} == 1 ]] && command -v lazydocker &>/dev/null; then
  alias lzd="lazydocker"
  _zsh_msg "%F{green}✓%f %F{cyan}lazydocker%f 管理工具已启用 (命令: %F{yellow}lzd%f)" "%F{green}✓%f %F{cyan}lazydocker%f tool enabled (cmd: %F{yellow}lzd%f)"
fi

if [[ ${ZSH_PROJECT_TMUX:-0} == 1 ]] && command -v tmux &>/dev/null; then
  alias t="tmux"
  alias ta="tmux attach -t"
  alias tls="tmux ls"
  alias tn="tmux new -s"
fi

if [[ ${ZSH_PROJECT_FULL:-0} == 1 ]] && command -v nvim &>/dev/null; then
  _zsh_msg "%F{green}✓%f %F{cyan}neovim%f 已设置为默认编辑器" "%F{green}✓%f %F{cyan}neovim%f set as default editor"
fi

alias grep="grep --color=auto"

if [[ ${ZSH_PROJECT_FULL:-0} == 1 ]] && command -v zoxide &>/dev/null; then
  eval "$(zoxide init zsh)"
  _zsh_msg "%F{green}✓%f %F{cyan}zoxide%f 智能跳转已启用 (命令: %F{yellow}z%f)" "%F{green}✓%f %F{cyan}zoxide%f smart cd enabled (cmd: %F{yellow}z%f)"
fi

# ========================================
# 自动显示系统信息
# ========================================
if [[ ${ZSH_PROJECT_FULL:-0} == 1 ]] && command -v fastfetch &>/dev/null; then
  _zsh_msg "%F{green}✓%f %F{cyan}fastfetch%f 系统信息工具已启动\n" "%F{green}✓%f %F{cyan}fastfetch%f system info tool started\n"
  if [[ -r "$HOME/.config/fastfetch/config.jsonc" ]]; then
    fastfetch -c "$HOME/.config/fastfetch/config.jsonc"
  else
    fastfetch
  fi
fi

# 历史记录与按键设置
HISTFILE="$HOME/.zhistory"
HISTSIZE=4000
SAVEHIST=2000
setopt share_history hist_ignore_all_dups hist_verify hist_reduce_blanks
unsetopt inc_append_history inc_append_history_time
bindkey '^[[A' history-search-backward
bindkey '^[[B' history-search-forward

# ========================================
# 新版本检测与提示模块（非阻塞后台轮询）
# ========================================
_zsh_project_state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/zsh-project"
_zsh_updates_file="$_zsh_project_state_dir/available_updates"
_zsh_last_check_file="$_zsh_project_state_dir/last_update_check"
_zsh_check_script="$_zsh_project_state_dir/scripts/check_updates.sh"
[[ ! -f "$_zsh_check_script" && -n "${ZSH_PROJECT_DIR:-}" && -f "$ZSH_PROJECT_DIR/scripts/check_updates.sh" ]] && _zsh_check_script="$ZSH_PROJECT_DIR/scripts/check_updates.sh"

# 1. 终端启动时展示可用更新提示（仅读本地缓存文件，耗时 0ms）
if [[ -s "$_zsh_updates_file" ]]; then
  _zsh_msg '\n%F{yellow}💡 [Zsh 更新提示] 检测到以下插件/应用有可用更新：%f' '\n%F{yellow}💡 [Zsh Update Notice] Updates available for the following components:%f'
  while IFS= read -r _u_line; do
    [[ -n "$_u_line" ]] && print -P "  %F{cyan}•%f $_u_line"
  done < "$_zsh_updates_file"
  _zsh_msg '  %F{green}提示：%f可在终端输入 %F{yellow}zsh-update%f 执行升级\n' '  %F{green}Tip:%f Run %F{yellow}zsh-update%f in terminal to upgrade\n'
  unset _u_line
fi

# 2. 定期后台异步检测（默认 7 天检测一次，&! 静默脱离当前终端）
if [[ ${ZSH_PROJECT_AUTO_CHECK_UPDATE:-1} == 1 && -f "$_zsh_check_script" ]]; then
  local _now=$(date +%s 2>/dev/null || echo 0)
  local _last=0
  [[ -f "$_zsh_last_check_file" ]] && _last=$(cat "$_zsh_last_check_file" 2>/dev/null || echo 0)
  local _interval_days=${ZSH_PROJECT_CHECK_INTERVAL_DAYS:-7}
  local _interval_sec=$(( _interval_days * 86400 ))

  if (( _now - _last > _interval_sec )); then
    echo "$_now" > "$_zsh_last_check_file" 2>/dev/null || true
    ( bash "$_zsh_check_script" -q --lang "${ZSH_PROJECT_LANG:-zh}" >/dev/null 2>&1 ) &!
  fi
  unset _now _last _interval_days _interval_sec
fi

# 提供更新与检测命令
function _zsh_project_check_script() {
  local script="${XDG_STATE_HOME:-$HOME/.local/state}/zsh-project/scripts/check_updates.sh"
  if [[ -f "$script" ]]; then
    print -r -- "$script"
  elif [[ -n ${ZSH_PROJECT_DIR:-} && -f "$ZSH_PROJECT_DIR/scripts/check_updates.sh" ]]; then
    print -r -- "$ZSH_PROJECT_DIR/scripts/check_updates.sh"
  else
    return 1
  fi
}

function zsh-update() {
  local installer=""
  local check_script=""
  if [[ -n "${ZSH_PROJECT_DIR:-}" && -f "$ZSH_PROJECT_DIR/install.sh" ]]; then
    installer="$ZSH_PROJECT_DIR/install.sh"
  elif [[ -f "$HOME/.zsh-project/install.sh" ]]; then
    installer="$HOME/.zsh-project/install.sh"
  fi
  if [[ -n "$installer" ]]; then
    bash "$installer" --update --lang "${ZSH_PROJECT_LANG:-zh}"
  elif check_script=$(_zsh_project_check_script); then
    bash "$check_script" --lang "${ZSH_PROJECT_LANG:-zh}"
  else
    _zsh_msg "%F{red}未找到安装器或更新脚本。%f" "%F{red}Installer or update script not found.%f"
  fi
}

function zsh-check-updates() {
  local check_script=""
  if check_script=$(_zsh_project_check_script); then
    bash "$check_script" --lang "${ZSH_PROJECT_LANG:-zh}"
  else
    _zsh_msg "%F{red}未找到更新检测脚本。%f" "%F{red}Update check script not found.%f"
  fi
}

unset _zsh_project_state_dir _zsh_updates_file _zsh_last_check_file _zsh_check_script

if [[ -o interactive ]]; then
  local _elapsed_str_zh="" _elapsed_str_en=""
  if [[ -n "${ZSH_START_TIME:-}" ]] && zmodload zsh/datetime 2>/dev/null; then
    local _elapsed=$(( int((EPOCHREALTIME - ZSH_START_TIME) * 1000) ))
    _elapsed_str_zh=" %F{green}(用时 %F{yellow}${_elapsed}ms%F{green})%f"
    _elapsed_str_en=" %F{green}(took %F{yellow}${_elapsed}ms%F{green})%f"
  fi
  _zsh_msg "\n%F{blue}========================================%f\n%F{green}✅ ZSH 环境加载完成！${_elapsed_str_zh}%f\n%F{blue}========================================%f\n" "\n%F{blue}========================================%f\n%F{green}✅ ZSH environment loaded successfully!${_elapsed_str_en}%f\n%F{blue}========================================%f\n"
fi

# 语法高亮：在所有组件加载完成后置底加载
[[ -r "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]] && source "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
