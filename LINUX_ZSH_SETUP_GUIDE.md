# 主流 Linux 与 macOS 的 Zsh 从零配置到完整验收

更新日期：2026-09-06。基于本项目 `.zshrc`、README 和实际 Debian 排查记录编写。

“从 1 到 100”在本文中指完整实施流程，不是要求安装一百个插件。按顺序完成基础安装、框架、主题、插件、工具、部署、验收和维护即可。

**系统支持版本范围：**
- **macOS**：最低支持 macOS 10.15 (Catalina, Intel) / macOS 11.0 (Big Sur, Apple Silicon)；最高支持 macOS 15.x+ (Sequoia 及后续版本)。
- **Debian**：最低支持 Debian 10 (Buster)；最高支持 Debian 13 (Trixie) / Sid 滚动版（实测验证环境为 Debian 13）。
- **Ubuntu**：最低支持 Ubuntu 20.04 LTS；最高支持 Ubuntu 24.10 / 25.04+。
- **Fedora / RHEL**：最低支持 Fedora 34 / RHEL 8；最高支持 Fedora 41+ / RHEL 9.x+。
- **Arch Linux / Manjaro**：滚动更新（Rolling），始终支持最新同步稳定版。
- **openSUSE**：最低支持 Leap 15.4+；最高支持 Tumbleweed 滚动版。
- 完整技术底线指标与架构实现规范请参阅 [开发与架构设计文档](DEVELOPMENT.md)。

本次只编写教程，不会执行文中的安装、系统设置或配置替换命令。现有机器已经配置完成时，不要从头重新安装。

## 一、路线图与执行规则

| 阶段 | 目标 | 完成标志 |
| --- | --- | --- |
| 1—10 | 确认环境、备份 | 明确系统、用户和配置目录 |
| 11—25 | 安装 Zsh 与基础工具 | 能启动 `zsh -f` |
| 26—40 | 安装 OMZ、主题、插件 | 入口文件与插件主文件存在 |
| 41—60 | 配置可选工具 | 需要的工具能单独运行 |
| 61—75 | 适配并部署项目配置 | 语法检查通过，启动无错误 |
| 76—90 | 实际交互验收 | 关键功能逐项通过 |
| 91—100 | 默认 Shell、维护与回退 | 新会话正常，备份可恢复 |

- 除明确标为 **Windows PowerShell** 的部分外，命令在目标 Linux 执行。
- Linux 安装与文件准备阶段使用 Bash，避免尚未配置的 Zsh 对交互注释和语法产生不同解释。
- 一次执行一个阶段，命令报错先处理，不要继续覆盖配置。
- 保留一个已连接且可用的终端；安装软件、修改默认 Shell、字体、Docker 设置都是独立操作。
- 不复制项目里的 `.zhistory` 或 `.zsh_history` 到新机器，它们是旧命令记录。

## 二、确认环境与备份

执行：

```sh
bash
cat /etc/os-release
uname -m
id -un
printf 'HOME=%s\nSHELL=%s\nZDOTDIR=%s\n' "$HOME" "$SHELL" "${ZDOTDIR:-}"
```

`$SHELL` 是登录 Shell 的线索，不保证等于当前正在运行的 Shell。`uname -m` 用于区分 x86_64 与 aarch64 等架构，下载二进制时必须对应。

本文后续默认配置位于家目录。若使用了 `ZDOTDIR`，先理解现有配置结构，后文的 `~/.zshrc` 应替换为实际位置，不要清空已有变量来强行套用教程。

备份现有配置：

```bash
backup_dir="$HOME/zsh-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$backup_dir"
for config_name in .zshrc .zshenv .zprofile .zlogin .p10k.zsh; do
  if [ -e "$HOME/$config_name" ]; then
    cp -p "$HOME/$config_name" "$backup_dir/"
  fi
done
printf '备份目录：%s\n' "$backup_dir"
```

如果这些文件是符号链接或由 dotfiles 工具管理，应沿用原有管理方式。备份目录只保存原状态，不代表原配置一定正确。

## 三、安装 Zsh 与基础工具

只执行所属发行版的一组命令。下列软件安装使用系统包管理器；没有 sudo 权限时交给管理员处理，不修改系统目录权限。

### Debian / Ubuntu

```bash
sudo apt update
sudo apt install zsh git curl ca-certificates coreutils man-db
sudo apt install fzf fd-find bat neovim
```

### Fedora

```bash
sudo dnf install zsh git curl ca-certificates coreutils man-db
sudo dnf install fzf fd-find bat neovim
```

### Arch Linux

使用完整同步升级方式，避免只刷新包数据库而不升级系统：

```bash
sudo pacman -Syu zsh git curl ca-certificates coreutils man-db fzf fd bat neovim
```

### macOS (Homebrew)

macOS 推荐通过 Homebrew 安装与管理工具（以普通用户身份运行，无需 sudo）：

```bash
brew install zsh git curl coreutils
brew install fzf fd bat neovim
```

Zsh 安装方法参考 [OMZ 的发行版安装说明](https://github.com/ohmyzsh/ohmyzsh/wiki/Installing-ZSH)；Fedora 的 fd 包名为 `fd-find`，参见 [Fedora 软件包页](https://packages.fedoraproject.org/pkgs/rust-fd-find/fd-find/)。

检查：

```bash
zsh --version
git --version
command -v timeout
zsh -f -c 'print -r -- "Zsh 可以运行"'
```

此时先不执行 `chsh`，等新配置验收后再决定是否切换默认 Shell。

## 四、处理 Debian / Ubuntu 的命令名差异

部分 Debian / Ubuntu 软件包提供的是 `fdfind` 和 `batcat`，而本项目调用 `fd` 和 `bat`。仅设置交互别名无法保证 FZF 子进程也能找到它们，使用用户目录中的链接更合适。[fd 安装说明](https://github.com/sharkdp/fd#installation)、[bat 安装说明](https://github.com/sharkdp/bat#installation)

在 Bash 中执行，不覆盖已有文件或链接：

```bash
mkdir -p "$HOME/.local/bin"
if ! command -v fd >/dev/null 2>&1 && command -v fdfind >/dev/null 2>&1; then
  if [ ! -e "$HOME/.local/bin/fd" ] && [ ! -L "$HOME/.local/bin/fd" ]; then
    ln -s "$(command -v fdfind)" "$HOME/.local/bin/fd"
  fi
fi
if ! command -v bat >/dev/null 2>&1 && command -v batcat >/dev/null 2>&1; then
  if [ ! -e "$HOME/.local/bin/bat" ] && [ ! -L "$HOME/.local/bin/bat" ]; then
    ln -s "$(command -v batcat)" "$HOME/.local/bin/bat"
  fi
fi
export PATH="$HOME/.local/bin:$PATH"
fd --version
bat --version
```

如果仍找不到命令，检查已有链接，不要通过 `ln -sf` 盲目覆盖。

## 五、安装完整的 Oh My Zsh

本教程直接克隆仓库，避免安装脚本自动替换 `.zshrc` 或切换默认 Shell。OMZ 是框架，不能代替 Zsh 本体。[OMZ 官方项目](https://github.com/ohmyzsh/ohmyzsh)

先检查：

```bash
test -r "$HOME/.oh-my-zsh/oh-my-zsh.sh" && echo 'OMZ 主程序已存在'
ls -ld "$HOME/.oh-my-zsh" 2>/dev/null
```

**全新机器、目录不存在时**：

```bash
git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh"
test -r "$HOME/.oh-my-zsh/oh-my-zsh.sh" && echo 'OMZ 安装完成'
```

**已有完整 OMZ 时**直接跳过安装。**只有 custom 目录时**不要删掉重装，也不要继续当作安装完成；这是本项目曾发生的真实故障。

需要保留残留目录时，可在已备份配置的前提下，用以下 Bash 分支恢复。它会暂存旧目录，在新仓库准备好后保留旧 custom：

```bash
(
  set -e
  target="$HOME/.oh-my-zsh"
  if [ -r "$target/oh-my-zsh.sh" ]; then
    echo 'OMZ 已完整，跳过恢复。'
    exit 0
  fi
  stage=$(mktemp -d "$HOME/.omz-install.XXXXXX")
  git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git "$stage/repo"
  zsh -n "$stage/repo/oh-my-zsh.sh"
  if [ -d "$target/custom" ]; then
    cp -a "$target/custom/." "$stage/repo/custom/"
  fi
  if [ -e "$target" ] || [ -L "$target" ]; then
    mv "$target" "$stage/previous-oh-my-zsh"
  fi
  mv "$stage/repo" "$target"
  printf '恢复完成；原目录与暂存文件保留在：%s\n' "$stage"
)
```

该恢复流程面向本项目默认路径。若自定义了 OMZ 或 `ZSH_CUSTOM` 路径，需要先适配，不应照搬。

## 六、安装主题与三个外部插件

以下命令只用于目标目录尚不存在时。目录已经存在就先检查主文件，缺失时查清原因，不覆盖现有修改。

```bash
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$HOME/powerlevel10k"
mkdir -p "$HOME/.oh-my-zsh/custom/plugins"
git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions.git "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions"
git clone --depth=1 https://github.com/zsh-users/zsh-completions.git "$HOME/.oh-my-zsh/custom/plugins/zsh-completions"
git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"
```

本项目的接入方式：自动建议交给 OMZ；额外补全只把 `src` 加入 `fpath`；高亮只在末尾手动加载。不要再照其它教程把后两项重复加入插件列表。[自动建议安装说明](https://github.com/zsh-users/zsh-autosuggestions/blob/master/INSTALL.md)、[补全项目说明](https://github.com/zsh-users/zsh-completions)、[高亮安装说明](https://github.com/zsh-users/zsh-syntax-highlighting/blob/master/INSTALL.md)

### 字体与首次主题配置

图标由显示终端的字体决定。使用 Windows Terminal 连接 Linux 时，应在 Windows 端安装并选择合适的 Nerd Font，而不是只在服务器安装字体。本项目采用 Powerlevel10k；主题向导和字体说明见 [Powerlevel10k 官方文档](https://github.com/romkatv/powerlevel10k)。

部署后用 `p10k configure` 生成自己的 `~/.p10k.zsh`。本项目没有附带用户的个人主题文件，不能保证新机器复制 `.zshrc` 后立刻得到完全相同的外观。

## 七、逐步安装可选工具

先完成基础 Shell，再按需求增加。不存在的工具通常会被 `.zshrc` 跳过；“完整配置”不等于必须安装所有 SDK 或 Docker。

### 7.1 先查询仓库，再安装

Debian / Ubuntu：

```bash
apt-cache policy eza zoxide fastfetch yazi
```

Fedora：

```bash
dnf info eza zoxide fastfetch yazi
```

Arch：

```bash
pacman -Si eza zoxide fastfetch yazi
```

对查询确认可用的软件，使用对应 `apt install`、`dnf install` 或 `pacman -S` 安装。查询可能部分失败，各包分别处理；不同发行版版本不能保证都包含这些包。不因缺包直接添加未知仓库。

仓库没有包时，使用官方安装页面或官方 Release 中对应架构的二进制，检查该项目提供的校验资料，安装到 `~/.local/bin`。解包结构以下载内容为准，不使用猜测的文件名。

| 工具 | 用途 | 官方安装入口 |
| --- | --- | --- |
| eza | `ls` 列表及目录预览 | [安装说明](https://github.com/eza-community/eza/blob/main/INSTALL.md) |
| zoxide | 按访问记录跳转目录 | [安装说明](https://github.com/ajeetdsouza/zoxide#installation) |
| Fastfetch | 启动系统信息 | [安装说明](https://github.com/fastfetch-cli/fastfetch#installation) |
| Yazi | 文件管理和目录联动 | [安装说明](https://yazi-rs.github.io/docs/installation/) |

Yazi 的图片、视频、PDF 等预览需要额外依赖，基础目录浏览正常不等于所有预览都已配置。按需遵循官方依赖列表，不为测试目录联动而一次安装全部预览工具。

### 7.2 检查 FZF 接口兼容性

本项目使用 `fzf --zsh` 输出集成脚本。包管理器安装成功后仍要确认该选项存在：[FZF 官方文档](https://github.com/junegunn/fzf)

```bash
fzf --version
fzf --zsh >/dev/null
```

如果提示未知选项，先升级 FZF。仓库版本不支持时，可选择官方 Git 安装路线，避免额外安装脚本自动写入 Shell 配置：

```bash
git clone --depth=1 https://github.com/junegunn/fzf.git "$HOME/.fzf"
"$HOME/.fzf/install" --bin
```

此命令适用于 `~/.fzf` 不存在的首次安装。成功后在待部署 `.zshrc` 的 PATH 区域加入：

```zsh
export PATH="$HOME/.fzf/bin:$PATH"
```

保留项目现有的 `eval "$(fzf --zsh)"`，不要再重复 source 另一套 FZF 初始化脚本。

### 7.3 vfox：按需安装

vfox 用于 SDK 管理。没有多版本需求可以不装。官方提供安装脚本；先下载检查，再运行，而不是直接向 `.zshrc` 添加远程安装命令。[vfox 快速开始](https://vfox.dev/guides/quick-start.html)

```bash
vfox_stage=$(mktemp -d "$HOME/.vfox-install.XXXXXX")
curl -fsSL https://raw.githubusercontent.com/version-fox/vfox/main/install.sh -o "$vfox_stage/install.sh"
less "$vfox_stage/install.sh"
```

确认脚本内容和安装位置适合当前环境后，按官方提供的用户安装方式执行：

```bash
bash "$vfox_stage/install.sh" --user
```

以安装器输出确认可执行文件路径；若不在 PATH 中，将实际目录加入 `.zshrc`，不要猜测。然后检查：

```bash
vfox --version
vfox list
timeout -k 1s 5s vfox activate zsh
```

最后一条只输出激活脚本。项目已实现带超时的激活逻辑，不要再追加第二次无保护的初始化。安装 SDK 应根据实际开发需求另行进行，不照抄旧机器的整份 SDK 列表。

### 7.4 lazydocker：有 Docker 需求再安装

从 [lazydocker 官方安装说明](https://github.com/jesseduffield/lazydocker#installation) 选择对应发行版或二进制安装方式。如果已经具备官方要求的 Go 环境，也可使用其源码安装路线：

```bash
docker_tool_stage=$(mktemp -d "$HOME/.lazydocker-build.XXXXXX")
git clone --depth=1 https://github.com/jesseduffield/lazydocker.git "$docker_tool_stage/lazydocker"
(cd "$docker_tool_stage/lazydocker" && go install)
go env GOBIN GOPATH
```

安装位置由 GOBIN / GOPATH 决定，不保证等于旧机器目录。本项目保留了旧环境的 `~/.version-fox/sdks/golang/packages/bin`，新机器应检查实际安装位置后调整。

能显示 `lazydocker --version` 只证明程序可以运行；`lzd` 打不开 Docker 时，先查看连接错误，不自动启动服务、改 socket 权限或把用户加入 docker 组。这些属于独立系统管理操作。

## 八、适配项目中的机器专用设置

先把项目 `.zshrc` 复制为目标机器的 `~/.zshrc.new`，**在临时配置上编辑**，不要边阅读边改正在使用的配置。

| 设置 | 当前项目内容 | 新机器处理 |
| --- | --- | --- |
| Neovim PATH | `/opt/nvim` | 包管理器安装到 `/usr/bin` 时通常无需该路径 |
| Go 工具 PATH | `~/.version-fox/sdks/golang/packages/bin` | 按 lazydocker / Go 的实际安装位置调整 |
| pnpm PATH | `~/.local/share/pnpm` | 不使用时可移除该 PATH 项 |
| 编辑器 | `EDITOR=nvim` | 未装 Neovim 时改为已安装的编辑器 |
| bat 主题 | `tokyonight_night` | 本项目未提供主题文件，先查是否存在 |
| Fastfetch 配置 | `~/.config/fastfetch/config.jsonc` | 本项目未提供此文件，应使用默认展示或迁移自己已有配置 |
| `.p10k.zsh` | 从家目录读取 | 首次安装用主题向导生成 |
| `.zshenv` | 可读时加载 Cargo | 新机器无需为了 Zsh 专门安装 Rust |

### bat 主题检查

```bash
bat --list-themes | grep -F tokyonight_night
```

没有结果时，在 `.zshrc.new` 删除那一行 `export BAT_THEME="tokyonight_night"`，或换成 `bat --list-themes` 中存在的名称。不要把主题不存在误认为 FZF 失效。

### Fastfetch 配置缺失时

新机器建议把原来的自动运行块改为：

```zsh
if command -v fastfetch &>/dev/null; then
  print -P '%F{green}✓%f fastfetch 系统信息工具已启动\n'
  if [[ -r "$HOME/.config/fastfetch/config.jsonc" ]]; then
    fastfetch -c "$HOME/.config/fastfetch/config.jsonc"
  else
    fastfetch
  fi
fi
```

这是新环境适配示例，本文没有自动改动当前项目脚本。

### 保留加载顺序

不要重复添加 `compinit`、主题 `source` 或高亮插件。当前顺序详见 [README](README.md)。个人主题加载后应保留：

```zsh
typeset -g POWERLEVEL9K_INSTANT_PROMPT=off
```

本项目保留启动输出，因此不加载 Instant Prompt 缓存。运行 `p10k configure` 后检查它是否重新向 `.zshrc` 加入缓存加载段；若加入，按项目的展示策略移除该段。[Instant Prompt 说明](https://github.com/romkatv/powerlevel10k#instant-prompt)

## 九、传输、语法检查和首次启动

### 从当前 Windows 项目传输

在 Windows PowerShell 中，将主机变量改成实际 SSH 连接信息：

```powershell
$linuxTarget = "hailan20251015@192.168.9.165"
scp "C:\XMWJJ\ZSH\.zshrc" "${linuxTarget}:.zshrc.new"
```

在 Linux 上完成上一节的适配后检查：

```bash
zsh -n "$HOME/.zshrc.new"
wc -l "$HOME/.zshrc.new"
tail -n 8 "$HOME/.zshrc.new"
```

语法检查无输出且退出码为 0 才算通过。行数随注释变化，不以固定行数判断完整性；文件末尾应包含完整高亮加载块及 `fi`。

### 安装待验证配置

首次安装允许原来没有 `.zshrc`：

```bash
(
  set -e
  zsh -n "$HOME/.zshrc.new"
  if [ -e "$HOME/.zshrc" ]; then
    cp -p "$HOME/.zshrc" "$HOME/.zshrc.before-deploy-$(date +%Y%m%d-%H%M%S)"
  fi
  mv "$HOME/.zshrc.new" "$HOME/.zshrc"
)
```

只有显示无错误后才执行：

```bash
zsh
```

首次测试使用子 Shell，出现问题可以退出回到原来的 Bash。首次主题向导按自己的显示效果选择；需要重新配置时执行 `p10k configure`，然后再检查 Instant Prompt 设置。

`.zshenv` 不应整体覆盖有其它用途的旧文件。如果需要 Cargo 环境，在阅读已有内容后合并本项目的可读检查段即可。不要把 Fastfetch、横幅或交互工具初始化放进 `.zshenv`。

## 十、分轮验收

以下命令在新的 Zsh 中执行。代码块没有注释行，避免交互注释未开启时报 `command not found: #`。

### 第一轮：语法与加载

```zsh
zsh -n ~/.zshrc
print -r -- "Zsh=$ZSH_VERSION"
print -r -- "Instant Prompt=$POWERLEVEL9K_INSTANT_PROMPT"
whence -v p10k compdef _zsh_highlight _zsh_autosuggest_start
print -r -- "共享=${options[sharehistory]} 增量=${options[incappendhistory]}"
```

预期：函数可用；Instant Prompt 为 off；共享为 on，增量为 off。没有安装可选插件时，其函数不存在应记录为“未安装”，不要误标为通过。

### 第二轮：交互与快捷键

| 测试 | 操作 | 通过标准 |
| --- | --- | --- |
| 自动建议 | 执行 `echo ZSH_GUIDE_TEST_123`，再手打 `echo ZSH_GUIDE_` | 灰色建议出现，右方向键接受 |
| 高亮 | 输入存在与不存在的命令，不回车 | 颜色能区分 |
| 路径补全 | 输入 `ls /usr/bi` 后按 Tab | 补全 `/usr/bin/` |
| Ctrl+R | 搜索 `ZSH_GUIDE_TEST_123` | 找到测试命令 |
| Ctrl+T | 打开列表后按 Esc | 文件列表可用 |
| Alt+C | 选目录，再执行 `pwd` | 跳转成功 |
| 双 Esc | 输入 `echo hello` 后连按两次 Esc，不执行 | sudo 前缀出现 |

每项完成后按 Ctrl+C 清空未执行的命令。中文输入法或终端自身快捷键可能截获按键，先记录现象再调整。

### 第三轮：工具集成

| 测试 | 命令或操作 | 通过标准 |
| --- | --- | --- |
| Yazi | `y`，进入目录再按 q | 终端跟随目录 |
| 编辑器 | `nvim`，用 `:q!` 退出 | 正常进入退出 |
| eza | `ll`、`la` | 列表正常 |
| zoxide | 访问 `/usr/share`，回家目录，再 `z share` | 能匹配访问过的目录 |
| Git | `gst` | 实际调用 Git，非仓库提示可接受 |
| vfox | `vfox --version`、`vfox list` | 正常返回 |
| lazydocker | `lazydocker --version`、`lzd` | 版本正常、可连接 Docker |
| 手册 | `man ls`，按 q 退出 | 正常打开 |
| Fastfetch | 查看启动展示 | 正常显示，无配置文件错误 |

### 第四轮：共享历史

两个独立终端连接同一个 Linux 用户。在终端 A 执行：

```zsh
echo ZSH_SHARED_GUIDE_TEST_123
```

等 A 出现新提示符。在 B 执行一次 `pwd`，再打开 Ctrl+R 搜索标记。找不到时先检查：

```zsh
print -r -- "$HISTFILE"
command grep -F 'echo ZSH_SHARED_GUIDE_TEST_123' "$HISTFILE"
fc -l -15
```

命令同时出现在历史文件和 B 的历史列表时，说明同步已完成。FZF 可能同时匹配包含关键词的检查命令，不要只看当前选中行。

### 第五轮：可选项目

- `extract` 解压测试需要临时文件；本项目实际测试中用户选择跳过，不能写成已通过。
- 历史子串搜索插件已加载，但项目上下键为前缀搜索。若希望子串搜索，应另行改绑定并测试，不属于本教程默认行为。
- Yazi 媒体预览、Git 仓库写操作、SDK 安装切换、Docker 管理操作属于扩展功能，不从基础启动测试推断它们全部正常。

## 十一、通过验收后再切换默认 Shell

先确认路径在允许列表中：

```zsh
command -v zsh
cat /etc/shells
```

确认 `command -v zsh` 的路径已经列在 `/etc/shells` 后，为当前用户执行：

```zsh
chsh -s "$(command -v zsh)"
```

重新登录或新开 SSH 会话验证。若该命令受目录服务或管理员策略限制，保留显式运行 `zsh` 的方式，不修改认证配置。此操作改变登录 Shell，单纯使用 Zsh 不必须执行。[Zsh 安装与默认 Shell 说明](https://github.com/ohmyzsh/ohmyzsh/wiki/Installing-ZSH)

## 十二、更新、回退与故障排查

### 更新原则与自动检测

- 修改前保留已知可用的配置备份。
- 系统包按发行版包管理器更新；自行克隆的主题和插件先检查 `git status`，有本地修改先处理。
- 不对所有目录执行一键 `git reset --hard`，不在每次 Shell 启动时联网安装或更新。
- **自动更新检测机制**：本项目内置非阻塞后台轮询（默认每 7 天检测一次），若发现 OMZ、Powerlevel10k、插件或系统工具有新版本，会在新打开的终端顶部给出高亮提醒。
- **一键交互更新**：在终端直接运行 `zsh-update` 或 `bash install.sh --update`，确认后安全拉取并重新校验配置语法。
- **手动检查更新**：随时在终端运行 `zsh-check-updates` 或 `bash install.sh --check-updates` 查看详细对比。
- 更新后新开会话测试，而不是反复 `source ~/.zshrc` 堆叠初始化。
- 记录版本、现象和改动内容，避免只保留一张启动截图。

### 回退与救援

Shell 无法正常启动时，保留原终端，尝试运行 `bash` 或 `zsh -f`。选择自己记录的备份路径，先对备份执行 `zsh -n`，再复制回 `.zshrc`。不要关闭最后一个能工作的连接。

| 现象 | 优先检查 |
| --- | --- |
| `parse error near '\n'` | 文件是否复制截断，检查末尾与报错附近的引号、fi、括号 |
| 自动建议函数不存在 | OMZ 主入口是否存在，不能只检查 custom 目录 |
| 初始化输出警告 | 是否又加载了 Instant Prompt 缓存 |
| 标题后卡住 | 对工具激活过程跟踪，重点检查 vfox |
| lazydocker 文件存在但命令找不到 | PATH 是否包含实际 Go 工具目录 |
| FZF 无法使用 `--zsh` | 本机版本接口是否支持 |
| 图标是方框 | 显示终端的字体，不是首先重装主题 |
| bat 预览报主题错误 | 是否迁移了不存在的 `BAT_THEME` |

需要定位卡住位置时，在备用 Zsh 中运行：

```zsh
PS4='+%N:%i> ' timeout -k 2s 20s zsh -xic 'exit'
print -r -- "退出码=$?"
```

这会实际执行初始化；跟踪输出可能包含私密变量，分享前检查。完整案例见 [问题与修复记录](ZSH_TROUBLESHOOTING.md)。

## 十三、完成清单

- [ ] 备份完成，知道如何回退。
- [ ] Zsh、OMZ 主入口、主题与所选插件完整。
- [ ] 已适配 fd / bat 命令名、PATH、bat 主题和 Fastfetch 配置。
- [ ] 文件使用 UTF-8、LF 换行，完整传输并通过语法检查。
- [ ] 新会话启动无警告、无长时间卡住。
- [ ] 自动建议、高亮、补全、FZF、历史共享实际通过。
- [ ] 所需工具单独运行及集成测试通过，未安装项目明确标注。
- [ ] 解压等未执行测试标为跳过，而不是全部通过。
- [ ] 如需默认 Zsh，已重新登录验证。
- [ ] 已保存机器差异、版本和最后一次验证结果。

达到这一步即可作为日常配置使用。后续新增功能逐项引入、逐项测试，不再同时叠加多个插件后一起排查。
