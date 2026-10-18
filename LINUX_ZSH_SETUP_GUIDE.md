# 安装、手动部署与迁移指南

核对日期：2026-09-13。默认配置位置为当前用户 HOME；使用自定义 ZDOTDIR 或 dotfiles 链接管理时，需要先设计适配方案，安装器不会自动覆盖其它配置目录。

首次使用建议按“环境检查 → 隔离测试 → 安装器部署 → 新会话验收”完成。手动部署是独立替代路线，不需要在安装器执行后再重复一次。参数总表见 [README](README.md)。

## 1. 检查目标环境

以下命令在目标 Linux/macOS 的 Bash 中执行：

```bash
uname -s
uname -m
id -un
printf 'HOME=%s\nSHELL=%s\nZDOTDIR=%s\n' "$HOME" "${SHELL:-}" "${ZDOTDIR:-}"
bash --version
command -v git
command -v curl
```

Linux 可读取 `/etc/os-release`；macOS 可运行 `sw_vers`。`$SHELL` 通常表示登录 Shell，不一定是当前进程。安装目标是普通用户，系统依赖安装由 sudo 或 Homebrew 完成。

当前代码识别 Linux 和 Darwin、x86_64 和 ARM64 两类架构。可选工具的包名、上游运行库和可用资产需要分别确认；当前验证范围见[测试与验收](INSTALLER_TESTING.md)，不使用未经验证的最低/最高系统版本表。

## 2. 获取项目并保留现有配置

```bash
git clone https://github.com/vicky-clair/xao_Rui_is-one-lick-configuration-script-for-ZSH.git "$HOME/.zsh-project"
cd "$HOME/.zsh-project"
```

已有目录时先检查 `git status`，使用现有仓库。不要复制 `.zhistory`、`.zsh_history`、`scratch/` 或 `*.before-fix` 到新机器。

安装器会备份受管文件；第一次迁移还可单独保存其它用户配置：

```bash
(
  set -e
  migration_backup=$(mktemp -d "$HOME/zsh-migration-backup.XXXXXXXX")
  chmod 700 "$migration_backup"
  for config_name in .zshrc .zshenv .zprofile .zlogin .p10k.zsh .tmux.conf .zsh-project-options .zshrc.local; do
    if [ -e "$HOME/$config_name" ] || [ -L "$HOME/$config_name" ]; then
      cp -Pp "$HOME/$config_name" "$migration_backup/"
    fi
  done
  printf '迁移备份：%s\n' "$migration_backup"
)
```

这是普通文件备份，不含安装器回退清单，不能直接传给 `--rollback`。`cp -Pp` 保留链接本身，链接目标内容需由原有配置管理方案另外保存。保留一个已连接的可用终端，先验证新会话再退出旧会话。

## 3. 安装器路线

先运行检查：

```bash
bash scripts/test_installer.sh
bash scripts/test_management.sh
bash install.sh --dry-run --profile basic --p10k-style skip --lang zh
```

逐条检查结果；`SKIP` 不算通过，遇到 FAIL 先停止真实部署。

```bash
# 基础配置
bash install.sh --profile basic --p10k-style skip --lang zh

# 完整工具集与彩虹主题（交互模式）
bash install.sh --profile full --p10k-style rainbow --lang zh

# 全自动无人值守安装（非交互模式，适用 CI/CD、Docker、云服务器自动化构建）
bash install.sh --profile full --p10k-style rainbow --yes --lang zh
```

`skip` 保留 `.p10k.zsh`；`rainbow`、`lean`、`classic` 会备份并替换个人主题。希望自定义可使用 `--p10k-wizard`。不要默认反复安装会保留所有开关，选项文件会根据本次选择重新生成。

可按需附加 `--with-vfox`、`--with-lazydocker`、`--with-lazygit`、`--with-tmux`。已有的这些命令会自动影响安装选项，最终计划可能包含 `.tmux.conf` 替换。在需要静默免确认执行时，可显式传入 `--yes`（或 `-y`），脚本将自动确认安装计划、跳过交互询问，并在安装完成时优雅退出（不阻塞等待 `exec zsh`）。

### 严格幂等性与零重复保障 (Idempotency)

安装器内部实现了严格的幂等性检查：
- **多别名智能识别**：对不同 Linux 发行版的别名（如 Debian 的 `fdfind` / `batcat`，Arch 的 `7zz`，Linux 的 `convert`，Wayland 的 `wl-copy` 等）均做了识别映射；
- **拒绝重复调用**：只要系统中已安装相应工具，安装器**直接跳过**，绝不进行耗时的包管理器索引更新或重复事务；
- **官方二进制安全降级**：若发行版官方仓库缺少对应包（如旧系统上的 eza、yazi、television、tre），安装器会自动从 GitHub Release 拉取对应架构的官方发布包，并验证可执行性后部署至 `~/.local/bin/`。

安装完成后记录备份目录。选择进入新会话前仍应检查报错与跳过包；“配置安装完成”不代表每个可选组件都安装成功。

### 安装器的包管理边界

| 环境 | 处理 |
| --- | --- |
| Debian / Ubuntu 等 APT 系统 | 刷新包索引、安装依赖；部分工具缺包时尝试 Release |
| Fedora / RHEL 等 | 基础安装优先 DNF，缺失时使用 YUM；重试脚本的支持范围更窄 |
| Arch 系列 | 基础阶段包含 `pacman -Syu`，可能升级系统包，不只是安装配置 |
| openSUSE | 通过 Zypper 安装；应用更新检测不覆盖 Zypper |
| macOS | 使用 Homebrew；缺失时可交互引导安装。先确认实际运行的 Bash 版本并运行回归 |

`--with-latest-nvim` 只在 `full` 且非 Homebrew 的下载分支生效。它请求当前上游 Release，不承诺该版本兼容所有 Neovim 插件；项目不提供 LazyVim 或完整 Neovim 插件配置。

## 4. 手动部署路线

本节适合希望自行安装依赖和审查每一步的用户。使用安装器时跳过本节。

### 4.1 安装依赖

先按目标系统准备 Zsh、Git、curl、归档工具和哈希工具。以下是对应环境的基础示例，只执行适合自己系统的一组：

```bash
# Debian / Ubuntu 基础依赖与可选 agrep
sudo apt-get update
sudo apt-get install zsh git curl ca-certificates coreutils unzip tar file tre-agrep
# 剪贴板支持（Yazi / Tmux）：sudo apt-get install xclip (X11) 或 wl-clipboard (Wayland)
# 可选完整工具与 Yazi 预览依赖：fzf, fd-find, bat, eza, zoxide, yazi, neovim, ripgrep, jq, ffmpeg, 7zip (或 p7zip-full), poppler-utils, imagemagick, resvg
# 注：television 与 tre-command 官方仓库未提供 deb 时，安装脚本会自动从 GitHub Release 下载预编译版本
```

```bash
# Fedora 基础依赖与可选 agrep
sudo dnf install zsh git curl ca-certificates coreutils unzip tar file tre
# 剪贴板支持（Yazi / Tmux）：sudo dnf install xclip (X11) 或 wl-clipboard (Wayland)
# 可选完整工具与 Yazi 预览依赖：fzf, fd-find, bat, eza, zoxide, yazi, neovim, ripgrep, jq, ffmpeg, p7zip, poppler-utils, ImageMagick
# 注：television 与 tre-command 可通过 GitHub Release 或 cargo/copr 安装
```

```bash
# Arch Linux 基础依赖、agrep 与完整工具
sudo pacman -Syu --needed zsh git curl ca-certificates coreutils unzip tar file tre
# 可选完整工具与 Yazi 预览依赖可通过 pacman 或 AUR 安装（剪贴板支持含 xclip / wl-clipboard）：
# yay -S --needed television tre-command fzf fd bat eza zoxide yazi neovim ripgrep jq ffmpeg 7zip poppler imagemagick resvg xclip wl-clipboard
```

```bash
# openSUSE 基础依赖与可选 agrep
sudo zypper install zsh git curl ca-certificates coreutils unzip tar file tre
# 剪贴板支持（Yazi / Tmux）：sudo zypper install xclip 或 wl-clipboard
# 可选完整工具与 Yazi 预览依赖：fzf, fd-find, bat, eza, zoxide, yazi, neovim, ripgrep, jq, ffmpeg, p7zip, poppler-tools, ImageMagick
```

```bash
# 已配置 Homebrew 的 macOS，普通用户执行（含完整新工具与 Yazi 官方多媒体依赖）
brew install zsh git curl coreutils unzip tar file television tre-command tre
# 参考 Yazi 官方指南 (https://yazi-rs.github.io/docs/installation/) 完整安装与链接：
brew install yazi ffmpeg-full sevenzip jq poppler fd ripgrep fzf zoxide resvg imagemagick-full font-symbols-only-nerd-font
brew link ffmpeg-full imagemagick-full -f --overwrite
```

> **提示**：自动化安装脚本具备严格的**幂等性判断**机制——如果本机已经安装了相应程序或发行版等效别名（如 `fdfind`、`batcat`、`tre-agrep`、`7zz`、`convert`、`wl-copy`/`xclip`、已安装的 Nerd Fonts 图标字体等），脚本会自动识别并跳过，绝不会进行任何重复性安装或覆盖。

检查 `zsh --version` 和 `zsh -f -c 'print -r -- OK'`。尚未完成配置验收时，不急于设置默认登录 Shell。

### 4.2 准备框架、主题和插件

下面的 Bash 块只克隆不存在的目录；已存在但入口不完整时停止，保留现场。

```bash
(
  set -e
  clone_component() {
    local source_url=$1 target_dir=$2 entry=$3
    if [ -e "$target_dir" ] || [ -L "$target_dir" ]; then
      test -r "$target_dir/$entry" || {
        printf '组件不完整，请先检查：%s\n' "$target_dir" >&2
        return 1
      }
    else
      git clone --depth=1 "$source_url" "$target_dir"
      test -r "$target_dir/$entry"
    fi
  }
  clone_component https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh" oh-my-zsh.sh
  clone_component https://github.com/romkatv/powerlevel10k.git "$HOME/powerlevel10k" powerlevel10k.zsh-theme
  mkdir -p "$HOME/.oh-my-zsh/custom/plugins"
  for plugin in zsh-autosuggestions zsh-completions zsh-syntax-highlighting; do
    entry="$plugin.zsh"
    [ "$plugin" != zsh-completions ] || entry=README.md
    clone_component "https://github.com/zsh-users/$plugin.git" "$HOME/.oh-my-zsh/custom/plugins/$plugin" "$entry"
  done
)
```

自动建议通过 OMZ 加载；额外补全提前注册 `src` 目录；高亮在末尾加载。无需重复将补全和高亮加入 OMZ 插件列表。

### 4.3 部署模板、选项和辅助脚本

回到完整仓库根目录。先确认第 2 节备份已保存。以下命令创建暂存目录，对受管目标类型和语法进行检查，然后实际替换 Zsh 配置及辅助脚本：

```bash
(
  set -e
  test -r templates/zshrc.zsh
  for file in .zshrc .zsh-project-options; do
    test ! -L "$HOME/$file"
    test ! -e "$HOME/$file" || test -f "$HOME/$file"
  done
  manual_stage=$(mktemp -d "$HOME/.zsh-manual.XXXXXXXX")
  chmod 700 "$manual_stage"
  cp templates/zshrc.zsh "$manual_stage/zshrc"
  printf '%s\n' \
    'ZSH_PROJECT_FULL=0' \
    'ZSH_PROJECT_TELEVISION=0' \
    'ZSH_PROJECT_TV_KEYBINDINGS=0' \
    'ZSH_PROJECT_TRE=0' \
    'ZSH_PROJECT_VFOX=0' \
    'ZSH_PROJECT_LAZYDOCKER=0' \
    'ZSH_PROJECT_LAZYGIT=0' \
    'ZSH_PROJECT_TMUX=0' \
    'ZSH_PROJECT_AUTO_CHECK_UPDATE=0' \
    'ZSH_PROJECT_CHECK_INTERVAL_DAYS=7' \
    'ZSH_PROJECT_BANNER=1' \
    'ZSH_PROJECT_FASTFETCH=1' \
    'ZSH_PROJECT_TIMER=1' \
    'ZSH_PROJECT_LANG=zh' > "$manual_stage/options"
  printf 'ZSH_PROJECT_DIR=%q\n' "$PWD" >> "$manual_stage/options"
  zsh -n "$manual_stage/zshrc"
  zsh -n "$manual_stage/options"
  for helper in check_updates.sh manage.sh retry_tools.sh; do
    bash -n "scripts/$helper"
  done
  manual_state="${XDG_STATE_HOME:-$HOME/.local/state}/zsh-project"
  mkdir -p "$manual_state/scripts"
  for helper in check_updates.sh manage.sh retry_tools.sh; do
    install -m 700 "scripts/$helper" "$manual_state/scripts/$helper"
  done
  install -m 600 "$manual_stage/options" "$HOME/.zsh-project-options"
  install -m 600 "$manual_stage/zshrc" "$HOME/.zshrc"
  if [ -e "$HOME/.zshrc.zwc" ] || [ -L "$HOME/.zshrc.zwc" ]; then
    mv "$HOME/.zshrc.zwc" "$manual_stage/previous.zshrc.zwc"
  fi
  printf '手动部署暂存目录：%s\n' "$manual_stage"
)
```

该路线初始关闭可选集成和后台检查，保留 `.p10k.zsh`、`.tmux.conf` 及 `.zshenv`。不会生成 `install-*` 回退清单，也不安装软件；失败后依据暂存目录和第 2 节备份比较恢复。根目录 `.zshenv` 为空，不需要为本项目覆盖原来的环境配置。

主题外观可在新 Zsh 中运行 `p10k configure` 调整。主题向导可能修改 `.zshrc`，执行前另存当前文件；本项目保留启动输出，检查向导是否插入了 Instant Prompt 缓存加载段。

## 5. 可选工具和机器差异

先使工具本身可运行，再用管理命令启用其集成：

```bash
bash install.sh --set full=1
bash install.sh --set lazygit=1
```

`--set` 不安装软件。包名和命令名可能不同：Debian 常见 `fd-find` 提供 fdfind、bat 提供 batcat。模板支持部分替代命令，安装器也会尝试建立用户目录链接。需要手动建链接时，不覆盖已有文件或悬空链接。

| 工具或设置 | 迁移时检查 |
| --- | --- |
| FZF | `fzf --zsh` 是否支持；模板有系统脚本回退，不要重复 source 多套集成 |
| television | 模糊查找器（`tv`）；默认提供独立小部件 `Ctrl+P`，可通过 `tv-keys=1` 切换接管 `Ctrl+R`/`Ctrl+T` |
| tre | 现代化目录树（`tre`）；包装函数默认追加 `-e` 编号并加载快捷别名文件 `/tmp/tre_aliases_$USER` |
| agrep | TRE 近似正则匹配工具（`agrep` / `tre-agrep`）；Debian/Ubuntu 包名为 `tre-agrep`，安装脚本与模板自动提供映射与别名 |
| bat | 模板只在主题存在时设置 `tokyonight_night`；自定义 BAT_THEME 需自行确认 |
| Fastfetch | 有 `~/.config/fastfetch/config.jsonc` 时使用该文件，否则运行默认配置；项目未提供个人配置 |
| vfox | 安装后还需 SDK 配置；模板移除 `_vfox_hook` 自动目录/提示符钩子 |
| lazydocker | 可执行文件位置和 Docker 连接分别验证，不以补 PATH 代替服务权限排查 |
| Neovim | 检查实际命令路径、运行库和自己的编辑器配置；项目仅配置命令集成 |
| PATH | 含 `~/.local/bin`、Homebrew、Cargo、Go 和旧 vfox Go 目录；按实际工具位置评估 |
| 图标字体 | 在显示终端的一端配置字体；SSH 服务端有字体不代表客户端能显示 |

vfox 激活只有在 timeout/gtimeout 可用时受到生成阶段的超时保护，返回脚本的执行不受该保护。若无 SDK 切换需求，可保持关闭。

## 6. tmux 单独部署与验收

使用安装器可选择 `--with-tmux`，它会把 `.tmux.conf` 加入备份与部署。手动部署时，先保存原配置，再复制 `templates/tmux.conf`；不要把它当成单纯的静态文本加载——配置会执行 TPM 命令，TPM 缺失时会尝试联网克隆。

原样模板需 tmux 3.2 或更高版本，并满足插件自身要求。具体按键见 [README](README.md)。首轮验证包括左右/上下分屏、继承目录、复制模式、tmux 缓冲区粘贴和宿主机剪贴板。

鼠标复制保留复制模式，键盘 y 复制后退出。OSC 52 依赖客户端及中间层配置，不保证跨任意 SSH/tmux 层数都可用；遇到问题参考[故障排查](ZSH_TROUBLESHOOTING.md)。

## 7. 新会话验收与默认 Shell

先执行语法检查，再启动子 Shell：

```bash
zsh -n "$HOME/.zshrc"
zsh
```

在新的 Zsh 中检查：

```zsh
print -r -- "$ZSH_VERSION"
print -r -- "$POWERLEVEL9K_INSTANT_PROMPT"
whence -v p10k compdef _zsh_highlight _zsh_autosuggest_start
```

根据启用组件测试 Tab、右键接受建议、FZF 快捷键、Yazi 目录联动、共享历史等。实际测试表和记录模板见[测试与验收](INSTALLER_TESTING.md)。只通过语法或看到工具提示不等于完整功能通过。

确认稳定后，如需更改登录 Shell：

```bash
command -v zsh
cat /etc/shells
```

确认实际 Zsh 路径在允许列表内，再运行 `chsh -s "$(command -v zsh)"`，重新登录验证。受管理员策略限制时保留手动启动方式。配置回退不会恢复默认登录 Shell。

## 8. 日常维护和迁移

- 个人别名、按键放入 `~/.zshrc.local`，参考 `templates/zshrc.local.example`；该文件不在自动备份范围内。
- 调整初始化开关使用 `--set`，不要在末尾扩展里修改已经执行过的初始化选项。
- 项目代码同步后，需要重新部署才会影响 HOME 配置和状态目录脚本副本；`--update` 只更新第三方组件。
- 重装可能调用包管理器、更新旧工具并重写选项，先检查差异和最终计划，不以固定耗时作为成功标准。
- 换机器不要直接搬运带旧 HOME 的安装备份；manifest 归属校验会拒绝自动恢复。迁移个人设置时逐项比较。
- Windows 向目标机传输时使用自己的连接信息，例如在 PowerShell 中设置 `$remoteTarget = 'user@example-host'`，再通过 SCP 传完整仓库或暂存文件；不要复用历史文档中的私人主机地址。

回退命令、管理范围与冲突处理见[配置管理](CONFIGURATION_MANAGEMENT.md)。遇到启动异常时先保留可用会话，通过 `bash --noprofile --norc` 或 `zsh -f` 排查，再决定恢复哪份配置。

## 9. 推荐现代终端模拟器安装指南（macOS 与主流 Linux 发行版）

为了充分发挥本项目的 **Powerlevel10k 彩虹流线主题**、**Yazi 终端多媒体图片/PDF 预览** 与 **FZF / tmux 快捷键** 的全部效能，强烈推荐使用支持 GPU 硬件加速与现代图形协议的终端模拟器。

### 9.1 终端选型速查

| 终端 | 开发语言 | 核心特性 | 最佳场景 |
| :--- | :--- | :--- | :--- |
| **WezTerm** | **Rust** (Metal / OpenGL) | 功能最全、自带分屏与标签页，原生支持 Kitty 图像协议与富文本 | **首选推荐**：开箱即用，高颜值与 Yazi 终端内图片/PDF/视频预览 |
| **Alacritty** | **Rust** (Metal / OpenGL) | 极简哲学、极致吞吐量与极低输入延迟 | **极客首选**：追求极致速度，配合本项目 `--with-tmux` 分屏配置 |
| **Ghostty** | **Zig** + Metal / GTK4 | 现象级跨界新作，macOS 原生毛玻璃背景，支持 Kitty 图像协议 | **现代颜值**：原生 macOS / Linux 桌面整合体验 |

---

### 9.2 macOS 安装指南

#### (1) WezTerm 与 Ghostty (Homebrew Cask 快速安装)

```bash
# 推荐终端与 Nerd Font 字体一键安装：
brew install --cask wezterm ghostty font-jetbrains-mono-nerd-font font-meslo-for-powerlevel10k

# 或按需单独安装：
brew install --cask wezterm    # WezTerm (Rust, 功能最全，Yazi 多媒体预览首选)
brew install --cask ghostty    # Ghostty (Zig, 高颜值原生毛玻璃)

# 必备配套 Nerd Font 字体（确保图标与 Powerlevel10k 提示符 100% 正常显示）：
brew install --cask font-jetbrains-mono-nerd-font font-meslo-for-powerlevel10k
```

<a id="alacritty-macos-install"></a>
#### (2) Alacritty macOS 独立安装

> [!WARNING] macOS 下 Alacritty Cask 说明
> Homebrew 官方在 2026-09-01 将 `alacritty` Cask 暂时禁用（因未通过 macOS Gatekeeper 公证安全检测）。若直接执行 `brew install --cask alacritty` 会报错中断。
> **推荐通过官方 DMG 快速安装**（自动移除 Gatekeeper 隔离属性并建立终端命令软链接）：
> ```bash
> # 下载官方 DMG（以 v0.17.0 为例）并挂载安装
> curl -fLo /tmp/Alacritty.dmg https://github.com/alacritty/alacritty/releases/download/v0.17.0/Alacritty-v0.17.0.dmg
> hdiutil attach /tmp/Alacritty.dmg -nobrowse -mountpoint /tmp/alacritty_mount
> cp -R /tmp/alacritty_mount/Alacritty.app /Applications/
> hdiutil detach /tmp/alacritty_mount
> # 移除 Gatekeeper 隔离属性，避免提示损坏或拦截
> xattr -r -d com.apple.quarantine /Applications/Alacritty.app
> # 建立命令行软链接 (确保可在终端输入 alacritty 启动)
> mkdir -p ~/.local/bin && ln -sf /Applications/Alacritty.app/Contents/MacOS/alacritty ~/.local/bin/alacritty
> rm -f /tmp/Alacritty.dmg
> ```
> *亦可通过 Rust 官方工具链直接编译安装*：`cargo install alacritty`。

各终端配置文件位置：
* **WezTerm**：`~/.wezterm.lua`
* **Alacritty**：`~/.config/alacritty/alacritty.toml`
* **Ghostty**：`~/.config/ghostty/config`

---

### 9.3 主流 Linux 发行版安装指南

#### (1) WezTerm (Rust 全能终端) 安装

* **Debian / Ubuntu / Linux Mint**：
  ```bash
  curl -fsSL https://apt.fury.io/wez/gpg.key | sudo gpg --yes --dearmor -o /etc/apt/keyrings/wezterm-fury.gpg
  echo 'deb [signed-by=/etc/apt/keyrings/wezterm-fury.gpg] https://apt.fury.io/wez/ * *' | sudo tee /etc/apt/sources.list.d/wezterm.list
  sudo apt-get update && sudo apt-get install -y wezterm
  ```
* **Fedora / RHEL / CentOS**：
  ```bash
  sudo dnf copr enable -y wezfurlong/wezterm-nightly
  sudo dnf install -y wezterm
  ```
* **Arch Linux / Manjaro**：
  ```bash
  sudo pacman -S --needed wezterm
  ```
* **openSUSE**：
  ```bash
  sudo zypper install wezterm
  ```
* **通用 Linux (Flatpak)**：
  ```bash
  flatpak install flathub org.wezfurlong.wezterm
  ```

#### (2) Alacritty (Rust 极简极速终端) 安装

* **Debian 12+ / Ubuntu 22.04+**：
  ```bash
  sudo apt-get update && sudo apt-get install -y alacritty
  ```
* **Fedora**：
  ```bash
  sudo dnf install -y alacritty
  ```
* **Arch Linux**：
  ```bash
  sudo pacman -S --needed alacritty
  ```
* **openSUSE**：
  ```bash
  sudo zypper install alacritty
  ```

#### (3) Ghostty (现代高性能终端) 安装

* **Arch Linux**：
  ```bash
  sudo pacman -S --needed ghostty
  ```
* **Fedora**：
  ```bash
  sudo dnf copr enable -y pgdev/ghostty
  sudo dnf install -y ghostty
  ```
* **Ubuntu / 通用 Linux (Snap)**：
  ```bash
  sudo snap install ghostty --classic
  ```

#### (4) Linux 图标字体配置 (Nerd Fonts)

终端图标依赖 Nerd Fonts 字体，若系统未自带，可通过以下命令快速补充：

* **Debian / Ubuntu / Linux Mint**：
  ```bash
  mkdir -p ~/.local/share/fonts
  curl -fsSL https://github.com/ryanoasis/nerd-fonts/releases/latest/download/NerdFontsSymbolsOnly.zip -o /tmp/symbols.zip
  unzip -qo /tmp/symbols.zip -d ~/.local/share/fonts/
  fc-cache -fv ~/.local/share/fonts
  ```
* **Arch Linux**：
  ```bash
  sudo pacman -S --needed ttf-jetbrains-mono-nerd ttf-meslo-nerd ttf-nerd-fonts-symbols
  ```
* **Fedora**：
  ```bash
  sudo dnf install -y jetbrains-mono-fonts-all
  ```
