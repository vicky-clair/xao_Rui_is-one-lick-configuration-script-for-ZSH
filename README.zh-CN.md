# Linux 与 macOS Zsh 配置与更新管理器

[English](README.md) · **简体中文** · [日本語](README.ja.md)

<p align="center">
  <img src="https://img.shields.io/badge/Platform-macOS%20%7C%20Linux-blue?style=flat-square&logo=apple&logoColor=white" alt="Platform" />
  <img src="https://img.shields.io/badge/Shell-Zsh%205.9%2B%20%7C%20Bash%203.2%2B-green?style=flat-square&logo=gnu-bash&logoColor=white" alt="Shell" />
  <img src="https://img.shields.io/badge/Verified-macOS%20M1%20%7C%20Debian%2013-success?style=flat-square" alt="Verified" />
  <img src="https://img.shields.io/badge/Tests-PASS%20100%25-brightgreen?style=flat-square" alt="Tests" />
  <img src="https://img.shields.io/badge/License-MIT-orange?style=flat-square" alt="License" />
</p>

为个人终端提供一键化开箱即用的 Oh My Zsh、Powerlevel10k 现代主题、极速补全、历史子串匹配与语法高亮，并集成全套 14+ 现代 Rust/Go 命令行生产力工具链、Tmux 剪贴板互通、配置开关管理、只读体检、无感自动更新检测与安全回退机制。

本文以当前 `install.sh`、`scripts/` 和 `templates/` 的实现为准。已在 **macOS (arm64 M1)** 与 **Debian GNU/Linux 13 (x86_64)** 双实机全量验证（冷启动低至 **143ms ~ 300ms**）。

---

## ⚡ 30 秒极速上手

> [!IMPORTANT]
> **安全运行提示**：请在目标机器的**普通用户**终端中直接运行（遇到系统包管理操作时安装器会自动按需请求 `sudo` 提权）。**切勿使用 `sudo bash install.sh` 或在 root 用户下运行**，避免导致普通用户家目录配置文件权限被 root 占用污染！
>
> 💡 **终端字体建议**：Powerlevel10k 彩虹流线提示符与 Yazi/Tmux 状态栏图标需要 **Nerd Font** 矢量图标字体支持（推荐 [JetBrainsMono Nerd Font](https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip)）。若在 SSH 远程连接或本地终端中发现图标显示为小方框乱码，只需在您本机终端软件（Windows Terminal、iTerm2、WezTerm 等）设置中将字体切换为 Nerd Font 即可瞬间完美显示！

```bash
# 1. 克隆项目仓库至用户目录
git clone https://github.com/vicky-clair/xao_Rui_is-one-lick-configuration-script-for-ZSH.git "$HOME/.zsh-project"
cd "$HOME/.zsh-project"

# 2. 挑选适合您的安装模式执行：

# 🚀 【推荐全能方案】完整版：全套现代 CLI 工具链 + P10k 经典彩虹流线主题 + Tmux 增强 + 现代终端配置
bash install.sh --profile full --p10k-style rainbow --with-tmux --with-terminals --lang zh

# ⚡ 【轻量基础方案】基础版：仅 OMZ + 3 个核心插件（极速补全/自动建议/语法高亮），保留现有个人主题
bash install.sh --profile basic --p10k-style skip --lang zh

# 🤖 【自动化免交互】CI / Docker / 云服务器无人值守全自动安装（所有提示默认确认）
bash install.sh --profile full --p10k-style rainbow --yes --lang zh
```

安装完成后，直接打开新终端或输入 `exec zsh` 即可畅享极速终端！

### 💡 核心注意事项与使用规范

1. **普通用户权限运行（切勿加 sudo）**：请始终以普通用户身份直接执行 `bash install.sh`。安装器在需要安装系统包时会自动按需请求 `sudo` 提权。直接执行 `sudo bash install.sh` 会导致用户家目录的配置文件归属权被 `root` 占用，引发后续权限问题！
2. **终端字体配置（Nerd Font）**：Powerlevel10k 彩虹流线提示符与 Yazi/Tmux 状态栏图标依赖矢量图标支持。推荐安装并选用 [JetBrainsMono Nerd Font](https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip)。若终端或 SSH 中图标显示为方框（`□`）或问号，只需在本地终端软件（Windows Terminal、iTerm2、WezTerm 等）设置中将字体选为该字体即可。
3. **个人扩展写入 `~/.zshrc.local`**：请勿直接修改受管模板。个人的环境变量、命令别名与自定义函数请写入 `~/.zshrc.local`。安装器、更新器（`zsh-update`）与配置管理器（`zsh-config`）**绝不会**创建或覆盖该文件。
4. **新会话生效原则**：调整配置开关（如 `zsh-config` 或 `install.sh --set KEY=0|1`）后，请新开终端或执行 `exec zsh` 重新加载。多次重复执行 `source ~/.zshrc` 无法彻底清理旧的别名与目录钩子。
5. **无电池设备 Tmux 状态栏优化**：在台式机、工控机或云服务器上，Linux `upower` 可能虚拟出 `0%` 空电池。可编辑 `~/.tmux.conf` 移除 `@theme_plugins` 中的 `battery`，随后按下 `Ctrl + a r` 即刻热重载生效。
6. **编码与换行符规范**：项目文件均严格采用 UTF-8 编码与 LF (`\n`) 换行符。在 Windows 编辑器中请勿将其转换为 CRLF，以免脚本在 Linux/macOS 环境下解析异常。

---

## 项目展示

下图为 Debian GNU/Linux 13、Zsh 5.9 环境中的终端启动截图。

![Zsh 项目启动截图：中文工具加载提示、Fastfetch 系统信息、插件更新提醒与启动耗时](assets/Ashampoo_Snap_12h48m48s.png)

- **顶部工具状态**：显示 Yazi、FZF、television、eza、tre、lazygit、Neovim、zoxide 等集成信息，以及常用命令和快捷键。
- **中部系统信息**：Fastfetch 展示 Debian 标识、系统、内核、桌面环境和硬件资源。
- **底部更新提醒**：展示缓存中的插件更新清单，可运行 `zsh-update` 进入更新流程。
- **加载计时**：`5441ms` 是这一次配置内计时的结果，不包括完整的终端连接过程，也不包含随后加载的用户扩展、高亮和首次提示符钩子。

图中的 `vfox 初始化失败或超时，本次已跳过` 表示该次激活未成功，其余工具继续加载。排查方法见[故障排查](ZSH_TROUBLESHOOTING.md)。截图中的机器信息、更新数量和耗时均是当时记录。

## 文档导航

| 需求 | 文档 |
| --- | --- |
| 首次安装、手动部署与新会话验收 | [安装指南](LINUX_ZSH_SETUP_GUIDE.md) |
| Tmux 生产力键位速查、剪贴板互通与实战技巧 | [Tmux 使用指南](TMUX_USAGE_GUIDE.md) |
| 开关、停用恢复、失败组件重试、备份 | [配置管理](CONFIGURATION_MANAGEMENT.md) |
| 启动报错、工具缺失、更新失败、终端显示异常 | [故障排查](ZSH_TROUBLESHOOTING.md) |
| 模块职责、加载顺序、状态文件与维护约定 | [开发文档](DEVELOPMENT.md) |
| 隔离回归、实机验收与已验证范围 | [测试与验收](INSTALLER_TESTING.md) |

## 功能与适用范围

- **基础环境**：Oh My Zsh、Powerlevel10k，以及自动建议、额外补全和语法高亮三个外部插件。
- **完整工具集**：尝试安装并集成 FZF、fd、bat、eza、zoxide、Yazi 及伴生多媒体预览工具（ripgrep、jq、ffmpeg、7-zip、poppler、ImageMagick、resvg 等）、Neovim、Fastfetch、television、tre、agrep。
- **可选组件**：vfox、lazydocker、lazygit、tmux；安装 SDK、配置 Docker 服务和权限需另外处理。
- **主题选择**：Rainbow、Lean、Classic、官方向导，或保留现有 `.p10k.zsh`。
- **日常管理**：开关设置、只读体检、显式启动诊断、停用/恢复和失败组件重试。
- **更新维护**：启动时展示本地缓存，达到间隔后启动后台检测；升级通过单独命令确认执行。
- **配置备份**：受管文件保存原内容、原存在状态和操作后哈希，恢复时检查后续修改。

### Yazi 终端文件管理器与多媒体预览套件

[Yazi](https://github.com/sxyazi/yazi) 是一款基于 Rust 开发的高性能异步终端文件管理器。在 `full` 完整配置下，安装器会自动安装并集成 Yazi 及其官方多媒体预览依赖套件：

| 伴生工具 | 对应软件包/Formula | 在 Yazi 中的核心功能 |
| :--- | :--- | :--- |
| **ripgrep** (`rg`) | `ripgrep` | 毫秒级文本与文件内容实时搜索 (`search` / `find`) |
| **fzf** (>= 0.53.0) | `fzf` | 交互式子目录快速过滤与模糊跳转 |
| **zoxide** | `zoxide` | 基于历史频次的高效目录智能跳转 |
| **jq** | `jq` | JSON 数据结构化解析与高亮预览 |
| **ffmpeg** | `ffmpeg` / `ffmpeg-full` | 视频文件首帧缩略图提取与音频元信息抽取 |
| **7-Zip** | `7zip` / `sevenzip` / `p7zip` | 压缩包 (zip/tar/7z/rar) 内容提取与目录树预览 |
| **poppler** | `poppler-utils` / `poppler` | PDF 文档高分辨率矢量封面抽取与预览 (`pdftoppm`) |
| **ImageMagick** | `imagemagick` / `ImageMagick` | 字体文件预览、苹果 HEIC 格式照片及 JPEG XL 高级图像格式 |
| **resvg** | `resvg` | SVG 矢量图形终端栅格化预览 |
| **xclip** / **wl-clipboard** | `xclip` / `wl-clipboard` | 系统剪贴板双向同步互通 (X11 与 Wayland 全支持) |
| **Nerd Fonts** | `Symbols Nerd Font` | 文件与目录类型图标、Powerlevel10k 状态提示符符号 |

### 严格幂等性与零重复保障 (Zero-Duplicate)

安装脚本具备严格的**幂等性 (Idempotency)** 设计：
- **多别名智能检测**：在调用系统包管理器前，先检测系统是否已有目标命令或其发行版等价别名（如 Debian/Ubuntu 下的 `fdfind` 代表 `fd`、`batcat` 代表 `bat`；Arch 下的 `7zz` 代表 `7z`；Linux 下的 `convert` 代表 `magick`；Wayland 下的 `wl-copy` 代表剪贴板工具）。
- **零冗余开销**：如果对应命令已存在，安装器将**立即直接跳过**，绝不进行耗时的包管理器网络检索或加锁事务，确保反复运行绝不产生多余开销。
- **优雅官方降级**：若系统发行版仓库确实未收录某个软件，安装器会自动从 GitHub 官方 Release 下载架构匹配的独立预编译二进制，校验后部署至 `~/.local/bin/`。

### 平台与依赖

| 平台或组件 | 当前实现与边界 |
| --- | --- |
| Linux | 安装器识别 APT、DNF/YUM、Pacman、Zypper 及部分衍生发行版；已在 Debian 13 (trixie) x86_64 生产实机完成全量安装、自动化体检与回归验证 |
| macOS | 安装路径使用 Homebrew（未安装时可交互引导）；已在 macOS (Apple Silicon arm64 / Intel) 上完成实机安装部署与全套回归测试验证 |
| 架构 | 安装器接受 `x86_64`/`amd64`、`aarch64`/`arm64`；每个上游二进制仍有自己的系统要求 |
| Windows | 可在 MSYS/Cygwin 中运行部分隔离测试；真实安装入口不支持 Windows 原生环境 |
| Bash | 安装和管理脚本必须用 Bash 运行，不使用 `sh install.sh`；已全面适配并验证 macOS 原生 Bash 3.2 (3.2.57) 以及 Linux 的 Bash 4/5 |
| Zsh | 交互配置运行依赖；已在 macOS (Zsh 5.9) 与 Debian 13 (Zsh 5.9) 上完成实机全流程验证 |
| tmux | 原样使用模板需至少 3.2，因为配置直接使用 `terminal-features` 和 `display-popup`；插件可能有额外要求 |
| FZF | 优先使用 `fzf --zsh`，旧版本尝试加载发行版/Homebrew/用户集成脚本；没有可用集成脚本时提示升级 |
| 超时工具 | 优先 `timeout`，其次 `gtimeout`；缺失时部分初始化和检查会直接运行，启动诊断则拒绝执行 |

tmux 的相关功能从 3.2 引入，参见[官方发布说明](https://github.com/tmux/tmux/issues/2737)。FZF 的 `--zsh` 从 0.48.0 提供，参见[官方集成说明](https://github.com/junegunn/fzf#setting-up-shell-integration)。本项目没有验证各发行版的最低/最高版本，不以过时的系统版本表承诺兼容。

### 推荐现代终端模拟器 (GPU 加速 / Rust / 高颜值)

为了使 Powerlevel10k 彩虹流线主题、Yazi 终端图片/PDF/视频预览以及 FZF 快捷键达到最佳视觉与性能体验，推荐搭配以下现代终端：

| 终端 | 核心语言 | 特点与优势 | 快速安装命令 |
| :--- | :--- | :--- | :--- |
| **WezTerm** | **Rust** | 功能最全，自带分屏，原生支持 Kitty 图形协议（Yazi 图片预览首选） | macOS: `brew install --cask wezterm`<br>Linux: [详细安装方法](LINUX_ZSH_SETUP_GUIDE.md#1-wezterm-rust-全能终端-安装) |
| **Alacritty** | **Rust** | 极简极速，输入延迟极低，天然契合搭配本项目 tmux 分屏使用 | macOS: [官方 DMG / Cargo 安装](LINUX_ZSH_SETUP_GUIDE.md#alacritty-macos-install)<br>Linux: `sudo apt install alacritty` / `pacman -S alacritty` |
| **Ghostty** | **Zig** | 原生 macOS Metal 硬件加速与毛玻璃背景，支持图形协议 | macOS: `brew install --cask ghostty`<br>Linux: [详细安装方法](LINUX_ZSH_SETUP_GUIDE.md#3-ghostty-现代高性能终端-安装) |

> 详细的各 Linux 发行版（Debian/Ubuntu/Fedora/Arch/openSUSE）与 macOS 完整安装命令请参阅：[现代终端模拟器安装指南](LINUX_ZSH_SETUP_GUIDE.md#9-推荐现代终端模拟器安装指南macos-与主流-linux-发行版)。项目内置了适配 Tokyo Night 主题与中文字体回退的 WezTerm / Alacritty 配置文件（详见 [`terminal_configs/README.md`](terminal_configs/README.md)），可在安装时附加 `--with-terminals` 一键部署。

## 快速开始

在目标 Linux 或 macOS 的普通用户终端中执行。Linux 安装系统包时会调用 sudo；不要用 `sudo bash install.sh`。

### 1. 获取完整项目并验证

```bash
git clone https://github.com/vicky-clair/xao_Rui_is-one-lick-configuration-script-for-ZSH.git "$HOME/.zsh-project"
cd "$HOME/.zsh-project"
bash scripts/test_installer.sh
bash scripts/test_management.sh
bash install.sh --dry-run --profile basic --p10k-style skip --lang zh
```

已有仓库时进入现有目录，不重复克隆。测试失败先检查日志；`SKIP` 表示对应功能没有验证。预演不联网、不写项目状态、不安装软件，但也不会验证软件包可用性或备份完整性。

### 2. 按需求安装

```bash
# 基础配置，保留已有个人主题
bash install.sh --profile basic --p10k-style skip --lang zh

# 或：完整工具集与彩虹主题
bash install.sh --profile full --p10k-style rainbow --lang zh

# 或：完整工具集、tmux 与主题向导
bash install.sh --profile full --with-tmux --p10k-wizard --lang zh

# 或：全自动无人值守安装（适用于 CI/CD 自动化构建、Docker 容器或脚本一键部署）
bash install.sh --profile full --p10k-style rainbow --yes --lang zh
```

以上是几种选择，不需要依次执行。交互模式下安装前会显示计划并确认（传入 `--yes` 或 `-y` 时默认全部自动确认）；是否修改默认登录 Shell、是否进入新 Zsh 会话会另外询问。检测到已安装的 vfox、lazydocker、lazygit 或 tmux 时会自动纳入安装选项，因此即使选择 `basic`，也要检查最终计划，尤其是 `.tmux.conf` 是否将被替换。

安装器部署的是 **`templates/zshrc.zsh`**。根目录 `.zshrc` 是行为不同的参考配置，不要把直接复制它当作等价的安装或升级步骤。个人别名通常放入 `~/.zshrc.local`。

### 3. 新会话验收

```bash
zsh -n "$HOME/.zshrc"
zsh
```

先用子 Shell 验证，异常时可以退出回到原终端。功能开关需新会话验证；反复 `source ~/.zshrc` 不能可靠清除旧别名和钩子。

### 单文件远程入口

完整仓库方式更便于检查、管理和重试。也可以先下载入口脚本、阅读后运行：

```bash
bootstrap_dir=$(mktemp -d)
curl -fSL https://raw.githubusercontent.com/vicky-clair/xao_Rui_is-one-lick-configuration-script-for-ZSH/main/install.sh -o "$bootstrap_dir/install.sh"
less "$bootstrap_dir/install.sh"
bash "$bootstrap_dir/install.sh" --dry-run --lang zh
bash "$bootstrap_dir/install.sh" --lang zh
```

逐条执行，下载失败不要继续。缺少模板时，实际安装会尝试下载项目到 `${XDG_CONFIG_HOME:-$HOME/.config}/zsh-project-repo`。如果 Git 克隆失败而进入原始文件下载分支，只下载 Zsh/tmux 模板与更新检测脚本，可能缺少安装器和管理/重试脚本；此时应改用完整仓库。自举下载及 Homebrew 准备可能发生在最终配置替换确认之前，只有 `--dry-run` 明确提前退出。

## 命令参考

每次选择一个主操作。管理操作的参数、确认规则和范围详见[配置管理](CONFIGURATION_MANAGEMENT.md)。

| 参数 | 作用 |
| --- | --- |
| `--help` / `-h` | 查看安装器帮助 |
| `--dry-run` | 只展示计划 |
| `--profile basic` / `--profile full` | 选择基础环境或完整工具集 |
| `--p10k-style STYLE` | `rainbow`、`lean`、`classic`、`wizard`、`skip`；默认值为 `rainbow` |
| `--p10k-wizard` | 等同于 `--p10k-style wizard` |
| `--with-latest-nvim` | 在 `full` 且非 Homebrew 分支请求下载 Neovim 官方 Release；不在 `basic` 中独立生效 |
| `--with-vfox` / `--with-lazydocker` / `--with-lazygit` / `--with-tmux` | 启用对应可选组件 |
| `--without-tmux` / `--no-tmux` | 显式跳过 tmux 及其配置（即使系统已安装 tmux 也不启用） |
| `--with-terminals` / `--with-terminal-configs` | 自动备份并部署 [`terminal_configs/`](terminal_configs/README.md) 下的 WezTerm 与 Alacritty 终端配置 |
| `--lang zh` / `--lang en` | 安装、更新界面语言；管理脚本当前主要为中文 |
| `--check-updates` | 检测更新，联网并写缓存，不升级软件 |
| `--update` | 检测、确认后更新第三方组件；Linux 系统包仍需手动升级 |
| `--rollback DIR` | 从安装备份恢复受管配置；需交互确认 |
| `--disable` / `--enable` | 停用/恢复项目 Zsh 配置 |
| `--configure` / `--set KEY=0或1` | 配置菜单或单项开关 |
| `--doctor` / `--profile-startup` | 只读体检 / 真实执行配置的启动诊断 |
| `--retry-failed [TOOL]` | 重试失败清单或指定组件 |
| `--list-backups` / `--diff-backup DIR` | 查看备份或差异 |
| `--restore-backup DIR --scope zsh` | 按范围恢复；范围可为 `zsh`、`tmux`、`all` |
| `--yes` / `-y` | 全自动免交互确认模式；支持常规安装、CI/CD 自动化构建、管理与重试命令全部静默放行 |

主题还支持 `--p10k-rainbow`、`--p10k-lean`、`--p10k-classic`、`--p10k-skip` 简写。

## 常用功能

以下以安装模板为准，要求对应工具存在且开关开启。

| 按键或命令 | 用途 |
| --- | --- |
| Tab / 右方向键 | 补全 / 在行尾接受自动建议 |
| Ctrl+R / Ctrl+T / Alt+C | FZF 历史搜索 / 文件选择 / 目录选择（`full=1`） |
| 上下方向键 | 按已输入前缀搜索历史 |
| 双击 Esc | OMZ sudo 插件为当前输入添加 sudo 前缀 |
| `y` / `z 关键词` | Yazi 终端文件管理器（含视频/PDF/图片预览，退出后切换目录） / zoxide 跳转（`full=1`） |
| `tv` / Ctrl+P | television 智能模糊查找器（`full=1`，可通过 `tv-keys=1` 接管 Ctrl+T/Ctrl+R） |
| `tre` | 现代化目录树（`full=1`，带 `.gitignore` 过滤与 `-e` 编号跳转联动） |
| `agrep` | TRE 模糊正则表达式匹配工具（`full=1`） |
| `ll` / `la` | eza 详细列表 / 含隐藏项列表（`full=1`） |
| `v` / `vim` / `vi` | 运行 Neovim 包装函数（`full=1` 且存在 nvim） |
| `lg` / Ctrl+G | lazygit Git 面板 |
| `lzd` | lazydocker 容器面板 |
| `gst` / `man 命令` | OMZ Git 状态别名 / 手册；颜色取决于分页器和终端 |
| `t` / `ta [名称]` / `tls` / `tn 名称` | 接入 main / 挂载会话 / 列出会话 / 新建会话 |
| `zsh-config` | 配置菜单；可附加 `--doctor`、`--set banner=0` 等管理参数 |
| `zsh-check-updates` / `zsh-update` | 手动检测 / 更新第三方组件 |

### tmux 操作

前缀键为 `Ctrl+a`：先按前缀，再按表中的键。

| 后续按键 | 作用 |
| --- | --- |
| `\|` / `-` | 左右分屏 / 上下分屏，继承当前目录 |
| `c` / `m` | 新建窗口 / 最大化或还原窗格 |
| `h` / `j` / `k` / `l` | 向左/下/上/右调整窗格 5 格，可连续按键 |
| `r` | 重新加载 `.tmux.conf`，其中的命令与插件也会立即热重载生效 |
| `g` / `G` | lazygit 弹窗 / 在新窗口打开 lazygit |
| `[` | 进入复制模式（`v` 开始选择，`Ctrl+v` 切换矩形选择，`Esc` 退出复制模式，`y` 复制并退出） |
| `p` / `]` | 粘贴 tmux 内部缓冲区（若从本机向远程粘贴，请使用终端的快捷键如 `Ctrl+Shift+V` 或 `Cmd+V`） |
| `I`（Shift+i） | TPM 安装插件 |

**状态栏设计与全方位硬件监控 (Status Bar & Hardware Monitoring)**：
- **位置常驻屏幕底部**：模板默认配置 `status-position bottom`，符合终端视线交互习惯。全新系统首次安装后直接开箱即用常驻在底部。
- **配置即时热重载**：任何时候修改了 `~/.tmux.conf`，只需在 Tmux 中按下 **`Ctrl + a` 然后按 `r`**（或命令 `tmux source-file ~/.tmux.conf`），屏幕底部弹出绿色成功提示，修改立即生效，无需重启 Tmux 服务！
- **Tokyo Night 实时监控模块**：右侧状态栏基于 `v2.7.2` 稳定版引擎，内置高颜值 Nerd Font 硬件仪表：
  - `󰥔 时间`：实时日期与时刻
  - `󰛳 网络`：网卡实时上下行收发速率（如 `↓1K ↑2K`）
  - ` CPU`：核心实时运算负载百分比
  - ` 内存`：物理 RAM 占用百分比
  - `󰋊 磁盘`：根目录使用率
  - `󰁹 电池`：笔记本电量与充电感知
- **台式机/云服务器硬件适配提示**：如果机器为台式电脑、工控机、迷你主机或云服务器（无物理电池），Linux `upower` 服务可能会虚拟注册 `0%` 电池，只需编辑 `~/.tmux.conf` 将 `@theme_plugins` 中的 `battery` 删掉，然后按 `Ctrl + a r` 热重载，即可去除电池图标，保持状态栏清爽利落。

**会话常驻保活与自动重连 (Persistence & Auto-Attach)**：
- **常驻保活**：直接关闭终端窗口或网络意外断开时，Tmux 后台进程与运行中的任务（编译、下载、服务）完好保留，绝不中断。
- **自动接入恢复**：开启 `tmux` 时，打开终端自动接入或创建 `main` 会话，无缝恢复工作现场。
- **平稳退回原生终端**：在 tmux 内部输入 `exit` 或按 `Ctrl+a d`（脱离）后，**平稳退回原生普通终端（Zsh Prompt），绝不会闪退关闭窗口**。在原生终端输入 `t` 即可随时重新接入；
  - **想保留现场下次用**：按 `Ctrl+a d` 脱离或直接关闭终端窗口；
  - **想彻底结束销毁**：在窗格中输入 `exit`。

**剪贴板与鼠标交互指南**：
- **复制直通本地**：鼠标拖选松开、双击（选词）、三击（选行）或键盘 `y` 均使用 `copy-pipe-and-cancel`，自动写入系统剪贴板并**立即退出复制模式**，彻底根除停留在复制模式导致后续键盘打字假死卡住的故障。
- **随时退出复制模式**：按 `Esc` 或在窗格内任意位置**鼠标单击**，即可立即退出复制模式，随时恢复正常键盘打字输入。
- **全平台终端剪贴板 (OSC 52)**：全局通配启用 `*:RGB:clipboard` 与 `Ms` 转义序列，无需安装图形工具即可在 Windows Terminal、iTerm2、Alacritty、WezTerm 等终端中透传剪贴板，并对 `xclip` 增加了 1 秒超时防护，避免 SSH X11 转发失效时连接挂起。
- **终端原生选择技巧**：任何时候按住 **`Shift`** 键再用鼠标拖选，即可强制绕过 tmux 鼠标拦截，直接调用本地终端的原生选区与复制功能。

👉 **更详细的会话管理、状态栏排查、Vim 联动、断电恢复与实战技巧请参阅 [Tmux 生产力使用指南 (TMUX_USAGE_GUIDE.md)](TMUX_USAGE_GUIDE.md)**。

## 更新与重新部署

| 目标 | 操作 | 影响 |
| --- | --- | --- |
| 查看第三方更新 | `bash install.sh --check-updates` | Git fetch、包信息查询和缓存写入 |
| 更新第三方组件 | `bash install.sh --update` | Git 插件、TPM、FZF 仓库及 macOS Homebrew 工具；不部署模板 |
| 同步项目新配置 | 仓库中检查本地改动、`git pull --ff-only` 后重新运行安装器 | 重新选择安装项、备份并部署模板和选项 |
| 修改个人别名 | 编辑 `~/.zshrc.local` | 新会话加载，安装器不覆盖 |
| 仅修复缺失组件 | `bash install.sh --retry-failed TOOL` | 重试软件，不重写配置 |

重新安装会保留完整的已有 OMZ/主题/插件目录，并跳过部分已存在的可选命令；但基础依赖仍调用包管理器，Arch 分支包含 `pacman -Syu`，旧版 FZF/Neovim 可能触发下载。选项文件会重新生成，主题和 tmux 可能重新部署，不能保证固定耗时，也不是仅复制发生变化的行。

默认后台检测间隔为 7 天，在打开交互式 Zsh 时判断是否到期，并非独立定时服务。关闭 `auto-update` 不会隐藏已有缓存。APT 结果依赖本地软件包索引；Zypper/YUM-only、没有 `checkupdates` 的 Arch，以及独立 Release 二进制没有完整的应用版本检测覆盖。“没有更新”只适用于实际检查的范围。

## 配置回退与当前限制

```bash
bash install.sh --list-backups
bash install.sh --diff-backup /实际安装备份目录 --scope all
bash install.sh --rollback /实际安装备份目录
```

将示例路径替换为安装输出的 `install-XXXXXXXX` 目录。恢复只覆盖备份中记录的配置，不卸载软件、不回退插件版本或登录 Shell。后续修改导致哈希不一致时会拒绝覆盖；更灵活的范围恢复见[配置管理](CONFIGURATION_MANAGEMENT.md)。

使用前还需了解：

- 安装器不支持自定义 `ZDOTDIR`，受管文件为符号链接或目录时拒绝自动替换。
- `failed-components` 是跳过包的记录，不是所有安装步骤和插件的完整健康报告；TPM 插件安装失败可能被忽略。
- `--update` 没有统一配置快照或完整事务回退，TPM 和 FZF 的行为也不能概括为全部受本地修改保护。
- 安装日志位于备份目录；安装失败时备份可能尚未生成完整哈希，不保证可直接自动回退。

更多具体边界及后续维护事项见[开发文档](DEVELOPMENT.md)。

## 配置文件、环境变量与选项清单

项目将用户功能开关持久化存储在 `~/.zsh-project-options`（纯键值对，不执行任意代码），在 Zsh 启动时按需读取。可以通过 `bash install.sh --set KEY=0|1` 或 `zsh-config` 交互菜单修改。

| 配置键名 | 取值范围 | 默认值 | 作用说明 |
| :--- | :--- | :--- | :--- |
| `ZSH_PROJECT_FULL` | `0` 或 `1` | `0` (basic) / `1` (full) | 是否启用完整工具链功能别名与集成（FZF、Yazi、television、tre、eza 等） |
| `ZSH_PROJECT_VFOX` | `0` 或 `1` | `0` | 是否在 Zsh 启动时激活 vfox 多版本工具管理器 |
| `ZSH_PROJECT_LAZYDOCKER` | `0` 或 `1` | `1` | 是否挂载 lazydocker 容器面板命令别名 (`lzd`) |
| `ZSH_PROJECT_LAZYGIT` | `0` 或 `1` | `1` | 是否挂载 lazygit Git 面板命令别名 (`lg`) 与全局快捷键 (`Ctrl+G`) |
| `ZSH_PROJECT_TMUX` | `0` 或 `1` | `0` (默认未选) / `1` (传 `--with-tmux`) | 是否启用 tmux 辅助别名 (`t`、`ta`、`tls`、`tn`) 及跨平台剪贴板别名 |
| `ZSH_PROJECT_TMUX_AUTO` | `0` 或 `1` | `1` | 开启 tmux 时，启动交互终端是否自动接入或创建 `main` 会话 |
| `ZSH_PROJECT_BANNER` | `0` 或 `1` | `1` | 终端启动时是否显示欢迎横幅与工具加载状态 |
| `ZSH_PROJECT_FASTFETCH` | `0` 或 `1` | `1` | 终端启动时是否自动运行 Fastfetch 打印系统硬件与发行版状态 |
| `ZSH_PROJECT_TIMER` | `0` 或 `1` | `1` | 终端启动时是否统计并显示高精度初始化耗时 |
| `ZSH_PROJECT_AUTO_CHECK_UPDATE` | `0` 或 `1` | `1` | 是否启用定期后台异步检测更新（非阻塞） |
| `ZSH_PROJECT_CHECK_INTERVAL_DAYS`| 正整数 | `7` | 后台检测更新的触发间隔天数（天） |
| `ZSH_PROJECT_TELEVISION` | `0` 或 `1` | `1` | 是否启用 television (`tv`) 现代模糊搜索器集成 |
| `ZSH_PROJECT_TV_KEYBINDINGS` | `0` 或 `1` | `0` | 是否允许 television 接管 Ctrl+T / Ctrl+R 等原生快捷键 |
| `ZSH_PROJECT_TRE` | `0` 或 `1` | `1` | 是否启用 tre 现代目录树包装别名 |

### 全局运行时环境变量

- `ZSH_PROJECT_DIR`：可选指定项目脚本根目录。未设置时自动采用 `${XDG_STATE_HOME:-~/.local/state}/zsh-project/scripts`。
- `ZSH_PROJECT_PROFILING`：设为 `1` 时在终端启动时通过 `zsh/zprof` 记录各阶段微秒级耗时。
- `POWERLEVEL9K_INSTANT_PROMPT`：默认设置为 `off`，确保 Fastfetch、横幅和工具提示能够完整输出，杜绝输出被截断或与提示符重叠的问题。

---

## 本地测试、开发与 Docker 容器运行

本项目配备了完整的自动化测试与代码质量验证套件，可直接在本地开发环境或隔离容器中执行。

### 1. 本地测试与质量检查命令

```bash
# 1. ShellCheck 静态代码质量分析（CI 强力卡点，全库 0 错误 0 警告）
shellcheck install.sh scripts/*.sh

# 2. Bash 与 Zsh 原生语法解析校验
bash -n install.sh scripts/*.sh
zsh -n templates/zshrc.zsh .zshrc

# 3. 安装器隔离回归测试（模拟各种异常下载、幂等性、包名白名单与边界场景）
bash scripts/test_installer.sh

# 4. 配置管理器隔离回归测试（模拟配置快照、哈希校验、备份回滚与安全锁）
bash scripts/test_management.sh

# 5. 运行只读环境体检（检查 24 项 CLI 工具、版本读取与路径有效性）
bash scripts/manage.sh --doctor
```

### 2. Docker 隔离容器验证

您可以在任何已安装 Docker 的宿主机上，无需污染本机环境，一键体验与测试全套安装：

```bash
# 启动 Ubuntu 24.04 隔离容器进行极速验证
docker run --rm -it ubuntu:24.04 bash -c "
  apt-get update && apt-get install -y git sudo curl ca-certificates zsh tmux
  useradd -m -s /bin/bash testuser && echo 'testuser ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers
  su - testuser -c '
    git clone https://github.com/vicky-clair/xao_Rui_is-one-lick-configuration-script-for-ZSH.git ~/.zsh-project
    cd ~/.zsh-project
    bash install.sh --profile full --with-tmux --with-terminals --p10k-style rainbow --yes --lang zh
    zsh
  '
"
```

---

## 常见错误与故障排查速查

| 现象 / 错误提示 | 根本原因 | 推荐解决方案 |
| :--- | :--- | :--- |
| 提示符图标显示为方框或乱码 (`?`、`□`) | 当前宿主机终端缺少 Nerd Font 矢量图标字体 | 在终端软件（Windows Terminal/iTerm2/WezTerm）设置中将字体切换为 **JetBrainsMono Nerd Font**。 |
| `vfox 初始化失败或超时，本次已跳过` | vfox 首次安装未初始化或环境缺少网络 | 运行 `vfox --version` 检查，如需重试安装可执行 `bash install.sh --retry-failed vfox`。 |
| `macOS 当前 Bash 版本 (3.2) < 4.0` 警告 | macOS 自带的 `/bin/bash` 停留在 2007 年的 3.2 版 | 运行 `brew install bash` 安装现代 Bash。本项目安装器与脚本原生兼容 Bash 3.2，但 Tmux 某些主题组件依赖现代特性。 |
| Tmux 内部无法使用系统剪贴板 | 远程 SSH 会话未启用 OSC 52 或缺少 X11/Wayland 转发 | 本项目 Tmux 配置已默认开启 OSC 52 终端透传。在 Windows Terminal、iTerm2 或 WezTerm 中直接鼠标拖选或按 `y` 即可自动同步至本机剪贴板。 |

> 更多启动报错、插件冲突、历史记录丢失等详细疑难杂症，请查阅完整专著：[Zsh 排错与故障诊断指南 (ZSH_TROUBLESHOOTING.md)](ZSH_TROUBLESHOOTING.md)。

---

## 贡献指南与问题反馈

欢迎为本项目提交 Issue 或 Pull Request！

1. **Fork 本仓库** 并基于 `main` 分支拉取您的功能分支 (`git checkout -b feature/awesome-feature`)。
2. **规范提交代码**：
   - 保证代码符合项目现有架构规范；
   - 在关键逻辑处添加规范的中文注释；
   - 运行 `shellcheck install.sh scripts/*.sh` 确保静态检查通过；
   - 运行 `bash scripts/test_installer.sh` 与 `bash scripts/test_management.sh` 确保测试全部 PASS。
3. **提交与推送**：提交信息请遵循 Conventional Commits 规范（如 `feat(...)`、`fix(...)`、`docs(...)`）。
4. **发起 Pull Request**：详细说明改动动机、测试结果及兼容性验证。

Bug 反馈与功能建议：[GitHub Issues 页面](https://github.com/vicky-clair/xao_Rui_is-one-lick-configuration-script-for-ZSH/issues)

---

## 开源许可证与致谢

本项目采用 **MIT 开源许可证** 授权。详情参见 [LICENSE](LICENSE)（遵循 MIT 许可条款）。

### 第三方生态与开源致谢

本项目由衷感谢以下卓越的开源项目及其社区贡献者：

- [Oh My Zsh](https://github.com/ohmyzsh/ohmyzsh)：极其流行且成熟的 Zsh 配置管理框架；
- [Powerlevel10k](https://github.com/romkatv/powerlevel10k)：极致性能与极致美观的 Zsh 主题；
- [Yazi](https://github.com/sxyazi/yazi)：基于 Rust 构建的现代化极速终端文件管理器；
- [tmux](https://github.com/tmux/tmux) & [tmux-tokyo-night](https://github.com/fabioluciano/tmux-tokyo-night)：强大的终端复用器与高颜值主题；
- [fzf](https://github.com/junegunn/fzf)、[eza](https://github.com/eza-community/eza)、[bat](https://github.com/sharkdp/bat)、[zoxide](https://github.com/ajeetdsouza/zoxide)、[fastfetch](https://github.com/fastfetch-cli/fastfetch)、[television](https://github.com/alexpasmantier/television)、[tre-command](https://github.com/dduan/tre)、[vfox](https://github.com/version-fox/vfox)、[neovim](https://github.com/neovim/neovim)：现代命令行生产力工具的基石。

---

## 文件结构

| 文件 / 目录 | 用途 |
| --- | --- |
| `install.sh` | 安装、第三方更新、安装备份回退和管理分发入口 |
| `scripts/manage.sh` / `scripts/retry_tools.sh` | 配置管理 / 失败组件重试 |
| `scripts/check_updates.sh` | 更新检测与缓存写入 |
| `scripts/test_installer.sh` / `scripts/test_management.sh` | 当前隔离回归入口 |
| `templates/zshrc.zsh` / `templates/tmux.conf` | 安装器实际部署的模板 |
| `templates/zshrc.local.example` | 用户扩展示例 |
| `terminal_configs/` | WezTerm 与 Alacritty 现代终端推荐配置文件及中文字体回退链 |
| `AUDIT_REPORT.md` | 项目安全与质量工程审计报告 |
| `LINUX_ZSH_SETUP_GUIDE.md` | Linux 与 macOS 全流程环境安装与配置指南 |
| `TMUX_USAGE_GUIDE.md` | Tmux 现代化生产力键位速查、剪贴板互通与实战技巧指南 |
| `CONFIGURATION_MANAGEMENT.md` | 选项开关、快照备份与受管文件状态机制 |
| `DEVELOPMENT.md` | 开发规范、模块架构图、加载生命周期与边界约定 |
| `INSTALLER_TESTING.md` | 验收测试套件规范与双平台实机复测记录 |
| `ZSH_TROUBLESHOOTING.md` | Zsh 终端疑难杂症全景故障排查指南 |
| `.zshrc` / `.tmux.conf` | 根目录参考配置；`.zshrc` 与安装模板行为不同 |
| `.zshenv` | 环境变量占位文件，安装器不部署它 |
| `.github/workflows/tests.yml` | GitHub Actions 多平台矩阵回归与 ShellCheck 静态分析 CI 工作流 |
| `assets/` | 项目展示截图 |

