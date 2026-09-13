#!/usr/bin/env bash
# 独立组件重试：不部署 .zshrc、不修改主题、SDK 或 Docker 设置。
set -Eeuo pipefail
export LC_ALL=C
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/zsh-project"
YES=0 DRY=0 TOOL=''
while (($#)); do
  case "$1" in --yes) YES=1 ;; --dry-run) DRY=1 ;; --*) echo '未知参数' >&2; exit 1 ;; *) [[ -z "$TOOL" ]] || exit 1; TOOL=$1 ;; esac
  shift
done
# 统一发行版包名与命令别名，并拒绝不在支持列表中的组件。
normalize() {
  case "$1" in
    fd-find|fd) echo fd ;; batcat|bat) echo bat ;; neovim|nvim) echo neovim ;;
    wl-copy|wl-clipboard) echo wl-clipboard ;;
    fzf|eza|zoxide|yazi|fastfetch|lazydocker|lazygit|vfox|tmux|xclip|ncurses-term) echo "$1" ;;
    *) printf '不支持的组件：%s\n' "$1" >&2; return 1 ;;
  esac
}
# 显式指定组件时只重试该项，否则读取上次安装留下的失败清单。
REQUESTED=()
if [[ -n "$TOOL" ]]; then
  component=$(normalize "$TOOL") || exit 1
  REQUESTED+=("$component")
elif [[ -f "$STATE/failed-components" ]]; then
  while IFS= read -r component || [[ -n "$component" ]]; do
    [[ -n "$component" ]] || continue
    component=$(normalize "$component") || exit 1
    REQUESTED+=("$component")
  done < "$STATE/failed-components"
fi
if ((${#REQUESTED[@]} == 0)); then echo '没有失败项记录；旧安装可指定 --retry-failed lazydocker 或 lazygit。'; exit 0; fi
printf '仅重试组件：%s\n' "${REQUESTED[*]}"
echo '使用系统包管理器；lazydocker/lazygit 缺包时下载官方 Release。不会重写 Zsh 配置。'
((DRY == 0)) || exit 0
if ((YES == 0)); then
  [[ -t 0 ]] || { echo '请交互确认，或显式使用 --yes'; exit 1; }
  read -r -p '继续安装以上组件？[y/N] ' answer
  [[ "$answer" == y || "$answer" == Y ]] || exit 0
fi
# 确认后才创建状态目录与互斥锁；每次运行保留独立日志便于排查。
mkdir -p "$STATE"
mkdir "$STATE/retry.lock" 2>/dev/null || { echo '已有重试正在运行，请先检查 retry.lock'; exit 1; }
trap 'rmdir "$STATE/retry.lock" 2>/dev/null || true' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
RUN=$(mktemp -d "$STATE/retry-XXXXXXXX")
chmod 700 "$RUN"
export PATH="$HOME/.local/bin:$HOME/.version-fox/sdks/golang/packages/bin:$PATH"
FAMILY=''
if [[ $(uname -s) == Darwin ]]; then FAMILY=brew
elif [[ -r /etc/os-release ]]; then
  . /etc/os-release
  case "${ID:-} ${ID_LIKE:-}" in *debian*|*ubuntu*) FAMILY=apt ;; *fedora*|*rhel*) FAMILY=dnf ;; *arch*) FAMILY=pacman ;; *suse*) FAMILY=zypper ;; esac
fi
[[ -n "$FAMILY" ]] || { echo '不支持此发行版的自动重试'; exit 1; }
# 按实际命令判断可用性；ncurses-term 是终端数据包，交由包管理器确认。
available() {
  local component=$1 cmd=$1
  case "$component" in neovim) cmd=nvim ;; wl-clipboard) cmd=wl-copy ;; ncurses-term) return 1 ;; esac
  command -v "$cmd" >/dev/null && return 0
  if [[ "$component" == fd ]] && command -v fdfind >/dev/null; then return 0; fi
  if [[ "$component" == bat ]] && command -v batcat >/dev/null; then return 0; fi
  return 1
}
# 将统一组件名转换为对应发行版的包名，优先使用系统包管理器。
package_install() {
  local component=$1 package=$1
  if [[ "$component" == fd && ( "$FAMILY" == apt || "$FAMILY" == dnf || "$FAMILY" == zypper ) ]]; then package=fd-find; fi
  case "$FAMILY" in
    apt) sudo apt-get install -y "$package" ;;
    dnf) sudo dnf install -y "$package" ;;
    pacman) sudo pacman -S --needed --noconfirm "$package" ;;
    zypper) sudo zypper install -y "$package" ;;
    brew) brew install "$package" ;;
  esac
}
# 包管理器安装失败时下载官方二进制；验证可执行性后才写入用户命令目录。
lazydocker_release() {
  local url tag version arch os asset stage
  command -v curl >/dev/null || return 1
  arch=$(uname -m); os=$(uname -s)
  case "$arch" in x86_64) ;; aarch64|arm64) arch=arm64 ;; *) return 1 ;; esac
  [[ "$os" == Linux || "$os" == Darwin ]] || return 1
  # 官方资产名称包含版本号，不能使用 lazydocker_Linux_x86_64.tar.gz。
  url=$(curl -fsSL --connect-timeout 10 --max-time 30 -o /dev/null -w '%{url_effective}' https://github.com/jesseduffield/lazydocker/releases/latest) || return 1
  tag=${url##*/}
  [[ "$tag" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  version=${tag#v}
  asset="lazydocker_${version}_${os}_${arch}.tar.gz"
  stage="$RUN/lazydocker"
  mkdir -p "$stage" "$HOME/.local/bin"
  [[ ! -e "$HOME/.local/bin/lazydocker" && ! -L "$HOME/.local/bin/lazydocker" ]] || return 1
  curl -fSL --connect-timeout 10 --max-time 90 "https://github.com/jesseduffield/lazydocker/releases/download/$tag/$asset" -o "$stage/archive.tar.gz" || return 1
  tar -xzf "$stage/archive.tar.gz" -C "$stage" lazydocker || return 1
  [[ -f "$stage/lazydocker" && ! -L "$stage/lazydocker" && -x "$stage/lazydocker" ]] || return 1
  "$stage/lazydocker" --version || return 1
  install -m 755 "$stage/lazydocker" "$HOME/.local/bin/lazydocker"
}
# 根据版本、系统和架构拼接官方资产名；已有目标文件时拒绝覆盖。
lazygit_release() {
  local url tag version arch os asset stage
  command -v curl >/dev/null || return 1
  arch=$(uname -m); os=$(uname -s)
  case "$arch" in x86_64) ;; aarch64|arm64) arch=arm64 ;; *) return 1 ;; esac
  [[ "$os" == Linux || "$os" == Darwin ]] || return 1
  url=$(curl -fsSL --connect-timeout 10 --max-time 30 -o /dev/null -w '%{url_effective}' https://github.com/jesseduffield/lazygit/releases/latest) || return 1
  tag=${url##*/}
  [[ "$tag" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  version=${tag#v}
  asset="lazygit_${version}_${os}_${arch}.tar.gz"
  stage="$RUN/lazygit"
  mkdir -p "$stage" "$HOME/.local/bin"
  [[ ! -e "$HOME/.local/bin/lazygit" && ! -L "$HOME/.local/bin/lazygit" ]] || return 1
  curl -fSL --connect-timeout 10 --max-time 90 "https://github.com/jesseduffield/lazygit/releases/download/$tag/$asset" -o "$stage/archive.tar.gz" || return 1
  tar -xzf "$stage/archive.tar.gz" -C "$stage" lazygit || return 1
  [[ -f "$stage/lazygit" && ! -L "$stage/lazygit" && -x "$stage/lazygit" ]] || return 1
  "$stage/lazygit" --version || return 1
  install -m 755 "$stage/lazygit" "$HOME/.local/bin/lazygit"
}

# 保留未参与本次重试的失败项，仅根据本次结果更新对应组件。
PENDING=()
if [[ -f "$STATE/failed-components" ]]; then
  while IFS= read -r component || [[ -n "$component" ]]; do
    [[ -n "$component" ]] || continue
    component=$(normalize "$component") || exit 1
    PENDING+=("$component")
  done < "$STATE/failed-components"
fi
failed=0
for component in "${REQUESTED[@]}"; do
  ok=0
  if available "$component"; then ok=1
  elif package_install "$component" > "$RUN/$component.log" 2>&1; then
    if [[ "$component" == ncurses-term ]] || available "$component"; then ok=1; fi
  fi
  if ((ok == 0)) && [[ "$component" == lazydocker ]]; then
    if lazydocker_release >> "$RUN/$component.log" 2>&1; then ok=1; fi
  fi
  if ((ok == 0)) && [[ "$component" == lazygit ]]; then
    if lazygit_release >> "$RUN/$component.log" 2>&1; then ok=1; fi
  fi
  next=()
  for previous in "${PENDING[@]}"; do [[ "$previous" == "$component" ]] || next+=("$previous"); done
  PENDING=("${next[@]}")
  if ((ok)); then printf 'PASS: %s 可用\n' "$component"
  else PENDING+=("$component"); failed=1; printf 'FAIL: %s；查看 %s/%s.log\n' "$component" "$RUN" "$component"; fi
done
# 先写去重后的完整清单再替换旧文件；全部成功时写入空清单。
tmp=$(mktemp "$STATE/failed-components.XXXXXXXX")
if ((${#PENDING[@]})); then printf '%s\n' "${PENDING[@]}" | sort -u > "$tmp"; fi
mv "$tmp" "$STATE/failed-components"
echo '仅完成软件重试；需要新开终端让别名生效。'
exit "$failed"
