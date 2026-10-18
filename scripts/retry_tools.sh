#!/usr/bin/env bash
# 独立组件重试：不部署 .zshrc、不修改主题、SDK 或 Docker 设置。
set -Eeuo pipefail
export LC_ALL=C
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/zsh-project"
[[ -z "${ZSH_PROJECT_TEST_MARKER:-${AUDIT_MARKER:-}}" ]] && export PATH="$HOME/.local/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:/opt/nvim:$HOME/go/bin:$HOME/.cargo/bin:$HOME/.local/share/pnpm:$HOME/.version-fox/sdks/golang/packages/bin:$PATH"
YES=0 DRY=0 TOOL=''
while (($#)); do
  case "$1" in --yes) YES=1 ;; --dry-run) DRY=1 ;; --*) echo '未知参数' >&2; exit 1 ;; *) [[ -z "$TOOL" ]] || exit 1; TOOL=$1 ;; esac
  shift
done
# ==============================================================================
# 组件名称规范化函数 (Component Normalization)
# ==============================================================================
# 统一各 Linux 发行版及 macOS Homebrew 下的软件包名、别名与命令名称，
# 映射到标准化的内部组件名，并拦截不在支持列表内的非法参数，防止路径遍历攻击。
normalize() {
  case "$1" in
    fd-find|fd) echo fd ;; batcat|bat) echo bat ;; neovim|nvim) echo neovim ;;
    wl-copy|wl-clipboard) echo wl-clipboard ;;
    television|tv) echo television ;;
    tre-command|tre) echo tre-command ;;
    tre-agrep|agrep) echo agrep ;;
    ripgrep|rg) echo ripgrep ;;
    jq) echo jq ;;
    ffmpeg|ffmpeg-full) echo ffmpeg ;;
    sevenzip|7zip|p7zip|p7zip-full|7z|7zz) echo 7zip ;;
    poppler|poppler-utils|poppler-tools|pdftoppm) echo poppler ;;
    imagemagick|imagemagick-full|ImageMagick|magick) echo imagemagick ;;
    resvg) echo resvg ;;
    font-symbols-only-nerd-font) echo font-symbols-only-nerd-font ;;
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
echo '使用系统包管理器；lazydocker/lazygit/television/tre 缺包时下载官方 Release。不会重写 Zsh 配置。'
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
# 测试环境下避免宿主机全局二进制泄露影响测试断言；正常执行时补全 Homebrew 路径
if [[ -z "${ZSH_PROJECT_TEST_MARKER:-${AUDIT_MARKER:-}}" ]]; then
  export PATH="$HOME/.local/bin:$HOME/.version-fox/sdks/golang/packages/bin:$PATH:/opt/homebrew/bin:/usr/local/bin"
else
  export PATH="$HOME/.local/bin:$HOME/.version-fox/sdks/golang/packages/bin:$PATH"
fi
FAMILY=''
if [[ $(uname -s) == Darwin ]]; then FAMILY=brew
elif [[ -r /etc/os-release ]]; then
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
  if [[ -z "$FAMILY" ]]; then
    if command -v apt-get >/dev/null 2>&1; then FAMILY=apt;
    elif command -v dnf >/dev/null 2>&1 || command -v yum >/dev/null 2>&1; then FAMILY=dnf;
    elif command -v pacman >/dev/null 2>&1; then FAMILY=pacman;
    elif command -v zypper >/dev/null 2>&1; then FAMILY=zypper;
    fi
  fi
fi
[[ -n "$FAMILY" ]] || { echo '不支持此发行版的自动重试'; exit 1; }
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
# 命令可用性与别名存在性检测函数 (Availability Check)
# ==============================================================================
# 遵循幂等性：若系统中已有可用命令或其发行版等价别名，返回 0 跳过重复安装
# - neovim -> nvim
# - wl-clipboard -> wl-copy
# - ripgrep -> rg
# - poppler -> pdftoppm (PDF 渲染器)
# - 7zip -> 7z 或 7zz
# - imagemagick -> magick 或 convert
# - font-symbols-only-nerd-font -> has_nerd_font 字体库与字体目录扫描
# - fd -> fd 或 fdfind
# - bat -> bat 或 batcat
# - xclip/wl-clipboard -> 只要系统中具备任一有效剪贴板后端 (wl-copy, xclip, xsel) 即判为满足
available() {
  local component=$1 cmd=$1
  case "$component" in
    neovim) cmd=nvim ;;
    wl-clipboard) cmd=wl-copy ;;
    ncurses-term) return 1 ;;
    television) cmd=tv ;;
    tre-command) cmd=tre ;;
    agrep)
      command -v agrep >/dev/null && return 0
      command -v tre-agrep >/dev/null && return 0
      return 1
      ;;
    ripgrep) cmd=rg ;;
    poppler) cmd=pdftoppm ;;
    7zip)
      command -v 7z >/dev/null && return 0
      command -v 7zz >/dev/null && return 0
      return 1
      ;;
    imagemagick)
      command -v magick >/dev/null && return 0
      command -v convert >/dev/null && return 0
      return 1
      ;;
    font-symbols-only-nerd-font)
      has_nerd_font && return 0
      return 1
      ;;
  esac
  command -v "$cmd" >/dev/null && return 0
  if [[ "$component" == fd ]] && command -v fdfind >/dev/null 2>&1; then return 0; fi
  if [[ "$component" == bat ]] && command -v batcat >/dev/null 2>&1; then return 0; fi
  if [[ "$component" == xclip || "$component" == wl-clipboard ]] && (command -v wl-copy >/dev/null 2>&1 || command -v xclip >/dev/null 2>&1 || command -v xsel >/dev/null 2>&1); then return 0; fi
  return 1
}
# 将统一组件名转换为对应发行版的包名，优先使用系统包管理器。
package_install() {
  local component=$1 package=$1
  if [[ "$component" == fd && ( "$FAMILY" == apt || "$FAMILY" == dnf || "$FAMILY" == zypper ) ]]; then package=fd-find; fi
  if [[ "$component" == agrep && "$FAMILY" == apt ]]; then package=tre-agrep; fi
  if [[ "$component" == agrep && "$FAMILY" != apt ]]; then package=tre; fi
  if [[ "$component" == poppler && ( "$FAMILY" == apt || "$FAMILY" == dnf ) ]]; then package=poppler-utils; fi
  if [[ "$component" == poppler && "$FAMILY" == zypper ]]; then package=poppler-tools; fi
  if [[ "$component" == imagemagick && ( "$FAMILY" == dnf || "$FAMILY" == zypper ) ]]; then package=ImageMagick; fi
  if [[ "$component" == 7zip ]]; then
    case "$FAMILY" in
      brew) package=sevenzip ;;
      apt) package=7zip ;;
      dnf|zypper) package=p7zip ;;
      pacman) package=7zip ;;
    esac
  fi
  case "$FAMILY" in
    apt|dnf|zypper)
      if [[ "$component" == font-symbols-only-nerd-font ]]; then
        local font_dest="$HOME/.local/share/fonts/NerdFonts"
        mkdir -p "$font_dest"
        if curl -fsSL --connect-timeout 10 -m 60 "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/NerdFontsSymbolsOnly.zip" -o "$font_dest/symbols.zip" 2>/dev/null; then
          if command -v unzip >/dev/null 2>&1; then
            unzip -qo "$font_dest/symbols.zip" -d "$font_dest" 2>/dev/null || true
          elif command -v python3 >/dev/null 2>&1; then
            python3 -c "import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" "$font_dest/symbols.zip" "$font_dest" 2>/dev/null || true
          fi
          rm -f "$font_dest/symbols.zip"
        elif curl -fsSL --connect-timeout 10 -m 30 "https://github.com/ryanoasis/nerd-fonts/raw/HEAD/patched-fonts/NerdFontsSymbolsOnly/SymbolsNerdFont-Regular.ttf" -o "$font_dest/SymbolsNerdFont-Regular.ttf" 2>/dev/null; then
          :
        fi
        if command -v fc-cache >/dev/null 2>&1; then fc-cache -f "$font_dest" 2>/dev/null || true; fi
      elif [[ "$FAMILY" == apt ]]; then
        sudo apt-get install -y "$package" 2>/dev/null || {
          if [[ "$component" == 7zip ]]; then sudo apt-get install -y p7zip-full; fi
        }
      elif [[ "$FAMILY" == dnf ]]; then
        sudo dnf install -y "$package" 2>/dev/null || {
          if [[ "$component" == 7zip ]]; then sudo dnf install -y 7zip; fi
        }
      elif [[ "$FAMILY" == zypper ]]; then
        sudo zypper install -y "$package"
      fi
      ;;
    pacman)
      if [[ "$component" == font-symbols-only-nerd-font ]]; then
        sudo pacman -S --needed --noconfirm ttf-nerd-fonts-symbols 2>/dev/null || sudo pacman -S --needed --noconfirm ttf-nerd-fonts-symbols-mono
      else
        sudo pacman -S --needed --noconfirm "$package"
      fi
      ;;
    brew)
      if [[ "$component" == ffmpeg ]]; then
        HOMEBREW_NO_AUTO_UPDATE=1 brew install ffmpeg-full 2>/dev/null || HOMEBREW_NO_AUTO_UPDATE=1 brew install ffmpeg
        HOMEBREW_NO_AUTO_UPDATE=1 brew link ffmpeg-full -f --overwrite 2>/dev/null || true
      elif [[ "$component" == imagemagick ]]; then
        HOMEBREW_NO_AUTO_UPDATE=1 brew install imagemagick-full 2>/dev/null || HOMEBREW_NO_AUTO_UPDATE=1 brew install imagemagick
        HOMEBREW_NO_AUTO_UPDATE=1 brew link imagemagick-full -f --overwrite 2>/dev/null || true
      elif [[ "$component" == font-symbols-only-nerd-font ]]; then
        HOMEBREW_NO_AUTO_UPDATE=1 brew install font-symbols-only-nerd-font 2>/dev/null || HOMEBREW_NO_AUTO_UPDATE=1 brew install --cask font-symbols-only-nerd-font
      else
        HOMEBREW_NO_AUTO_UPDATE=1 brew install "$package"
      fi
      ;;
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
# television 官方 Release 自动下载：支持 macOS 与 Linux (musl/gnu 降级)，验证后部署至 ~/.local/bin/tv。
television_release() {
  local url tag version arch os asset stage bin
  command -v curl >/dev/null || return 1
  arch=$(uname -m); os=$(uname -s)
  case "$arch" in x86_64) ;; aarch64|arm64) arch=aarch64 ;; *) return 1 ;; esac
  [[ "$os" == Linux || "$os" == Darwin ]] || return 1
  url=$(curl -fsSL --connect-timeout 10 --max-time 30 -o /dev/null -w '%{url_effective}' https://github.com/alexpasmantier/television/releases/latest) || return 1
  tag=${url##*/}
  [[ "$tag" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  version=${tag#v}
  if [[ "$os" == Darwin ]]; then
    asset="tv-${version}-${arch}-apple-darwin.tar.gz"
  else
    asset="tv-${version}-${arch}-unknown-linux-musl.tar.gz"
  fi
  stage="$RUN/television"
  mkdir -p "$stage" "$HOME/.local/bin"
  [[ ! -e "$HOME/.local/bin/tv" && ! -L "$HOME/.local/bin/tv" ]] || return 1
  if ! curl -fSL --connect-timeout 10 --max-time 90 "https://github.com/alexpasmantier/television/releases/download/$tag/$asset" -o "$stage/archive.tar.gz" 2>/dev/null; then
    if [[ "$os" == Linux ]]; then
      asset="tv-${version}-${arch}-unknown-linux-gnu.tar.gz"
      curl -fSL --connect-timeout 10 --max-time 90 "https://github.com/alexpasmantier/television/releases/download/$tag/$asset" -o "$stage/archive.tar.gz" || return 1
    else
      return 1
    fi
  fi
  tar -xzf "$stage/archive.tar.gz" -C "$stage" tv 2>/dev/null || tar -xzf "$stage/archive.tar.gz" -C "$stage" 2>/dev/null || return 1
  bin=$(find "$stage" -type f -name tv -perm -111 2>/dev/null | head -n 1)
  [[ -n "$bin" && -x "$bin" ]] || return 1
  "$bin" --version || return 1
  install -m 755 "$bin" "$HOME/.local/bin/tv"
}
# tre-command 官方 Release 自动下载：获取最新版本并根据系统与架构解压验证，部署至 ~/.local/bin/tre。
tre_release() {
  local url tag version arch os asset stage bin
  command -v curl >/dev/null || return 1
  arch=$(uname -m); os=$(uname -s)
  case "$arch" in x86_64) ;; aarch64|arm64) arch=aarch64 ;; *) return 1 ;; esac
  [[ "$os" == Linux || "$os" == Darwin ]] || return 1
  url=$(curl -fsSL --connect-timeout 10 --max-time 30 -o /dev/null -w '%{url_effective}' https://github.com/dduan/tre/releases/latest) || return 1
  tag=${url##*/}
  [[ "$tag" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  version=${tag#v}
  if [[ "$os" == Darwin ]]; then
    asset="tre-v${version}-${arch}-apple-darwin.tar.gz"
  else
    asset="tre-v${version}-${arch}-unknown-linux-musl.tar.gz"
  fi
  stage="$RUN/tre"
  mkdir -p "$stage" "$HOME/.local/bin"
  [[ ! -e "$HOME/.local/bin/tre" && ! -L "$HOME/.local/bin/tre" ]] || return 1
  curl -fSL --connect-timeout 10 --max-time 90 "https://github.com/dduan/tre/releases/download/$tag/$asset" -o "$stage/archive.tar.gz" || return 1
  tar -xzf "$stage/archive.tar.gz" -C "$stage" tre 2>/dev/null || tar -xzf "$stage/archive.tar.gz" -C "$stage" 2>/dev/null || return 1
  bin=$(find "$stage" -type f -name tre -perm -111 2>/dev/null | head -n 1)
  [[ -n "$bin" && -x "$bin" ]] || return 1
  "$bin" --version || return 1
  install -m 755 "$bin" "$HOME/.local/bin/tre"
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
    if [[ "$component" == agrep ]] && ! command -v agrep >/dev/null 2>&1 && command -v tre-agrep >/dev/null 2>&1; then
      mkdir -p "$HOME/.local/bin"
      [[ ! -e "$HOME/.local/bin/agrep" ]] && ln -s "$(command -v tre-agrep)" "$HOME/.local/bin/agrep" 2>/dev/null || true
    fi
    if [[ "$component" == ncurses-term ]] || available "$component"; then ok=1; fi
  fi
  if ((ok == 0)) && [[ "$component" == lazydocker ]]; then
    if lazydocker_release >> "$RUN/$component.log" 2>&1; then ok=1; fi
  fi
  if ((ok == 0)) && [[ "$component" == lazygit ]]; then
    if lazygit_release >> "$RUN/$component.log" 2>&1; then ok=1; fi
  fi
  if ((ok == 0)) && [[ "$component" == television ]]; then
    if television_release >> "$RUN/$component.log" 2>&1; then ok=1; fi
  fi
  if ((ok == 0)) && [[ "$component" == tre-command ]]; then
    if tre_release >> "$RUN/$component.log" 2>&1; then ok=1; fi
  fi
  next=()
  for previous in ${PENDING[@]+"${PENDING[@]}"}; do [[ "$previous" == "$component" ]] || next+=("$previous"); done
  PENDING=(${next[@]+"${next[@]}"})
  if ((ok)); then printf 'PASS: %s 可用\n' "$component"
  else PENDING+=("$component"); failed=1; printf 'FAIL: %s；查看 %s/%s.log\n' "$component" "$RUN" "$component"; fi
done
# 先写去重后的完整清单再替换旧文件；全部成功时写入空清单。
tmp=$(mktemp "$STATE/failed-components.XXXXXXXX")
if ((${#PENDING[@]})); then printf '%s\n' "${PENDING[@]}" | sort -u > "$tmp"; fi
mv "$tmp" "$STATE/failed-components"
echo '仅完成软件重试；需要新开终端让别名生效。'
exit "$failed"
