# zsh-project 安装模板：跨平台兼容 Linux 与 macOS，支持中英双语提示。
# 在启动新会话后生效；此文件不负责安装软件。
[[ -o interactive ]] || return
typeset -g POWERLEVEL9K_INSTANT_PROMPT=off

[[ -r "$HOME/.zsh-project-options" ]] && source "$HOME/.zsh-project-options"

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
  precmd() {
    local end_time=$EPOCHREALTIME
    local elapsed=$(( int((end_time - ZSH_START_TIME) * 1000) ))
    if [[ "${ZSH_PROJECT_LANG:-zh}" == en ]]; then
      print -P "%F{green}⚡ Zsh startup completed in %F{yellow}${elapsed}ms%f"
    else
      print -P "%F{green}⚡ Zsh 启动完成，用时 %F{yellow}${elapsed}ms%f"
    fi
    unset -f precmd
  }
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

if command -v nvim >/dev/null 2>&1; then
  export EDITOR=nvim
else
  export EDITOR=vi
fi

if command -v bat >/dev/null 2>&1 && bat --list-themes 2>/dev/null | grep -q "tokyonight_night"; then
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

_zsh_msg '\n%F{blue}🔧 正在加载 Zsh 工具...%f' '\n%F{blue}🔧 Loading Zsh tools...%f'

# vfox 可选版本管理：安全超时防护（兼容 Linux timeout 与 macOS gtimeout）
if [[ ${ZSH_PROJECT_VFOX:-0} == 1 ]] && command -v vfox >/dev/null 2>&1; then
  local _vfox_cmd=""
  if command -v timeout >/dev/null 2>&1; then
    _vfox_cmd="timeout -k 1s 5s vfox activate zsh"
  elif command -v gtimeout >/dev/null 2>&1; then
    _vfox_cmd="gtimeout -k 1s 5s vfox activate zsh"
  else
    _vfox_cmd="vfox activate zsh"
  fi
  if _zsh_vfox_init=$(eval "$_vfox_cmd" 2>/dev/null); then
    eval "$_zsh_vfox_init"
    chpwd_functions=("${(@)chpwd_functions:#_vfox_hook}")
    precmd_functions=("${(@)precmd_functions:#_vfox_hook}")
    _zsh_msg '%F{green}✓%f %F{cyan}vfox%f 已加载' '%F{green}✓%f %F{cyan}vfox%f loaded'
  else
    _zsh_msg '%F{yellow}vfox 初始化失败或超时，已跳过。%f' '%F{yellow}vfox init failed or timed out, skipped.%f'
  fi
  unset _zsh_vfox_init _vfox_cmd
fi

# 完整模式工具集成（兼容 Debian 的 fdfind / batcat 与 macOS / Arch 的原生名称）
if [[ ${ZSH_PROJECT_FULL:-0} == 1 ]]; then
  if command -v fzf >/dev/null 2>&1; then
    if command -v fd >/dev/null 2>&1; then
      export FZF_DEFAULT_COMMAND='fd --hidden --strip-cwd-prefix --exclude .git'
      export FZF_ALT_C_COMMAND='fd --type=d --hidden --strip-cwd-prefix --exclude .git'
    elif command -v fdfind >/dev/null 2>&1; then
      export FZF_DEFAULT_COMMAND='fdfind --hidden --strip-cwd-prefix --exclude .git'
      export FZF_ALT_C_COMMAND='fdfind --type=d --hidden --strip-cwd-prefix --exclude .git'
    fi
    [[ -n ${FZF_DEFAULT_COMMAND:-} ]] && export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"

    if command -v bat >/dev/null 2>&1; then
      export FZF_CTRL_T_OPTS="--preview 'bat --color=always --line-range :200 {}'"
    elif command -v batcat >/dev/null 2>&1; then
      export FZF_CTRL_T_OPTS="--preview 'batcat --color=always --line-range :200 {}'"
    fi

    if command -v eza >/dev/null 2>&1; then
      export FZF_ALT_C_OPTS="--preview 'eza --tree --color=always {} | head -200'"
    fi

    if _zsh_fzf_init=$(fzf --zsh 2>/dev/null); then
      eval "$_zsh_fzf_init"
    else
      _zsh_msg '%F{yellow}FZF 不支持 --zsh，请升级后再启用快捷键。%f' '%F{yellow}FZF does not support --zsh; please upgrade.%f'
    fi
    unset _zsh_fzf_init
  fi

  if command -v eza >/dev/null 2>&1; then
    alias ls='eza --icons=always'
    alias ll='eza -lh --icons=always'
    alias la='eza -lah --icons=always'
  fi

  if command -v yazi >/dev/null 2>&1; then
    function y() {
      local tmp cwd
      tmp=$(mktemp -t yazi-cwd.XXXXXX) || return
      yazi "$@" --cwd-file="$tmp"
      if cwd=$(cat -- "$tmp") && [[ -n "$cwd" && "$cwd" != "$PWD" ]]; then
        builtin cd -- "$cwd"
      fi
      rm -f -- "$tmp"
    }
  fi

  command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init zsh)"

  if command -v fastfetch >/dev/null 2>&1; then
    if [[ -r "$HOME/.config/fastfetch/config.jsonc" ]]; then
      fastfetch -c "$HOME/.config/fastfetch/config.jsonc"
    else
      fastfetch
    fi
  fi
fi

if [[ ${ZSH_PROJECT_LAZYDOCKER:-0} == 1 ]] && command -v lazydocker >/dev/null 2>&1; then
  alias lzd=lazydocker
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
function zsh-update() {
  local installer=""
  if [[ -n "${ZSH_PROJECT_DIR:-}" && -f "$ZSH_PROJECT_DIR/install.sh" ]]; then
    installer="$ZSH_PROJECT_DIR/install.sh"
  elif [[ -f "$HOME/.zsh-project/install.sh" ]]; then
    installer="$HOME/.zsh-project/install.sh"
  fi
  if [[ -n "$installer" ]]; then
    bash "$installer" --update --lang "${ZSH_PROJECT_LANG:-zh}"
  elif [[ -f "$_zsh_check_script" ]]; then
    bash "$_zsh_check_script" --lang "${ZSH_PROJECT_LANG:-zh}"
  else
    _zsh_msg "%F{red}未找到安装器或更新脚本。%f" "%F{red}Installer or update script not found.%f"
  fi
}

function zsh-check-updates() {
  if [[ -f "$_zsh_check_script" ]]; then
    bash "$_zsh_check_script" --lang "${ZSH_PROJECT_LANG:-zh}"
  else
    _zsh_msg "%F{red}未找到更新检测脚本。%f" "%F{red}Update check script not found.%f"
  fi
}

unset _zsh_project_state_dir _zsh_updates_file _zsh_last_check_file _zsh_check_script

_zsh_msg '%F{green}✓ Zsh 配置加载完成%f' '%F{green}✓ Zsh configuration loaded successfully%f'

# 语法高亮：在所有组件加载完成后置底加载
[[ -r "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]] && source "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
