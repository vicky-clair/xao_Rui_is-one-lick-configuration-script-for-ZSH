# Linux 与 macOS Zsh 跨平台一键配置与更新管理器

本项目提供面向 **Linux**（Debian / Ubuntu / Fedora / Arch / openSUSE）与 **macOS**（Apple Silicon / Intel Mac）的现代化 Zsh 交互环境一键安装、自动配置及插件/应用版本更新管理工具。

集成功能包括：**Powerlevel10k** 极速主题、**自动建议**、**额外补全**、**语法高亮**、**FZF 模糊搜索**、**现代 CLI 工具链（eza、bat、fd、zoxide、yazi 等）**、**Fastfetch 启动信息**，以及**零阻塞终端启动的插件与应用新版本自动检测与提示**。

---

## 核心特性

- 🍏 **全平台兼容**：原生支持 Linux 各主流发行版（APT、DNF、Pacman、Zypper）及 macOS（Homebrew），自动识别 `x86_64`、`aarch64` 与 `arm64` 架构。
- ⚡ **零阻塞后台更新检测**：
  - 终端启动时读取本地缓存（耗时 0ms），若有插件或 CLI 工具更新，高亮显示温馨提示；
  - 自动在后台静默轮询（默认每 7 天异步检测一次，脱离前台进程），绝不拖慢终端打开速度。
- 🔄 **一键安全升级**：
  - 终端内随时输入 `zsh-update` 或运行 `bash install.sh --update`，自动检测并交互式升级已安装的 Git 插件、主题与包管理器工具；
  - 升级前自动检测本地未提交修改，避免代码覆盖与冲突；升级后自动校验 `.zshrc` 语法。
- 🛡️ **可靠的备份与回滚**：安装或恢复时对配置文件进行 SHA-256 校验与状态快照，提供 `bash install.sh --rollback <DIR>` 一键回退。
- ⏱️ **纯 Zsh 内置高精度计时**：采用 `zmodload zsh/datetime` 毫秒级计时，彻底解决 macOS BSD `date` 不支持 `%N` 导致的算术报错。

---

## 系统支持与版本兼容性矩阵

本项目经过系统性兼容审计，支持的操作系统最低、推荐及最高版本如下表所示：

### 1. 操作系统版本支持范围

| 操作系统体系 | 硬件架构 | 最低支持版本 | 推荐使用版本 | 最高支持版本 | 说明与依赖 |
| --- | --- | --- | --- | --- | --- |
| **macOS (Apple Silicon)** | `arm64` (M1/M2/M3/M4) | **macOS 11.0 (Big Sur)** | macOS 14 / 15+ | **macOS 15.x+ (最新)** | 苹果芯片硬件起跑版本，预装 Zsh 5.8+ |
| **macOS (Intel)** | `x86_64` | **macOS 10.15 (Catalina)** | macOS 13 / 14 | **macOS 15.x+ (最新)** | Catalina 首次将 Zsh 设为系统默认 Shell |
| **Debian** | `x86_64`, `aarch64` | **Debian 10 (Buster)** | Debian 12 / 13 | **Debian 13 (Trixie) / Sid** | 包含 Zsh 5.7+、Bash 5.0，实测环境 Debian 13 |
| **Ubuntu** | `x86_64`, `aarch64` | **Ubuntu 20.04 LTS** | Ubuntu 22.04 / 24.04 | **Ubuntu 24.10 / 25.04+** | 20.04 起附带完整 Zsh 5.8 与现代 glibc |
| **Fedora** | `x86_64`, `aarch64` | **Fedora 34** | Fedora 39 / 40 / 41 | **Fedora 41 / Rawhide** | 原生 DNF 包管理器支持 |
| **RHEL / Rocky / Alma** | `x86_64`, `aarch64` | **RHEL 8.0+** | RHEL / Rocky 9.x | **RHEL 9.x / 10.x** | RHEL 7 (Zsh 5.0) 已停止维护且低于基准 |
| **Arch Linux / Manjaro** | `x86_64`, `aarch64` | **Rolling (近期)** | 最新同步版本 | **Rolling (持续更新)** | Pacman 全量同步，始终提供最新 Zsh 5.9+ |
| **openSUSE** | `x86_64`, `aarch64` | **Leap 15.4+** | Leap 15.6 / Tumbleweed | **Tumbleweed (Rolling)** | 原生 Zypper 包管理器支持 |

### 2. 软件运行依赖基准

| 核心组件 | 最低版本要求 | 推荐版本 | 关键功能说明 |
| --- | --- | --- | --- |
| **Zsh** | **>= 5.1** | **>= 5.8** (推荐 5.9) | Powerlevel10k 与 Oh My Zsh 运行底座；内置 `zsh/datetime` 计时模块 |
| **Bash** | **>= 4.2** | **>= 5.0** | `install.sh` 与 `check_updates.sh` 需支持安全错误拦截与关联数组 |
| **Git** | **>= 2.0** | **>= 2.25+** | 支持 `git clone --depth=1` 极速拉取与 `git -C` 路径隔离 |
| **FZF** | **>= 0.20** | **>= 0.48.0** | 0.48+ 原生启用 `--zsh` 极速集成，低版本自动安全降级 |

## 文件结构说明

| 文件 / 目录 | 用途说明 |
| --- | --- |
| `install.sh` | 跨平台一键交互式安装器与版本更新升级入口 |
| `scripts/check_updates.sh` | 独立的轻量级插件与应用版本检测脚本（供后台轮询与命令调用） |
| `templates/zshrc.zsh` | 经过多平台适配的 `.zshrc` 安装模板文件 |
| `.zshrc` | 交互式 Zsh 完整参考配置（已分节并包含详尽中文注释） |
| `.zshenv` | 跨平台环境变量配置（按需加载 Cargo 等环境） |
| `LINUX_ZSH_SETUP_GUIDE.md` | 从零开始的手动部署、跨平台配置与分步验收指南 |
| `DEVELOPMENT.md` | 架构设计、加载生命周期、开发维护与跨平台工程规范 |
| `ZSH_TROUBLESHOOTING.md` | 常见问题根因、排查命令与最终测试矩阵记录 |

---

## 快速安装与使用

### 1. 一键安装

在目标 Linux 或 macOS 终端中克隆并运行安装脚本：

```bash
git clone https://github.com/your-username/ZSH.git ~/.zsh-project
cd ~/.zsh-project
bash install.sh
```

- **安装类型**：
  - `basic`（基础版）：安装 Oh My Zsh、Powerlevel10k 主题，以及 `zsh-autosuggestions`、`zsh-completions`、`zsh-syntax-highlighting` 三大核心插件。
  - `full`（完整版）：在基础版之上，自动检测并安装 `fzf`、`fd`、`bat`、`eza`、`zoxide`、`yazi`、`neovim`、`fastfetch`。
- **可选组件**：按需提示安装 `vfox`（SDK 版本管理）与 `lazydocker`（容器终端界面）。

### 2. 命令行参数

```bash
bash install.sh [选项]
```

| 参数 | 说明 |
| --- | --- |
| `--dry-run` | 预演执行计划，不修改文件、不联网、不调用权限提升 |
| `--profile basic\|full` | 指定基础模式或完整工具集模式 |
| `--with-vfox` | 请求安装 vfox（若仓库或脚本可用） |
| `--with-lazydocker` | 请求安装 lazydocker |
| `--check-updates` | 检测已安装的插件、主题与应用是否有新版本 |
| `--update` | 交互式更新所有有新版本的组件，并重新校验配置语法 |
| `--rollback <DIR>` | 恢复指定备份目录中的配置，安全回退 |
| `--help` | 查看帮助文档 |

---

## 插件与应用版本检测与更新

### 自动检测与启动提示
- 安装完成后，终端默认开启自动检测机制（保存在 `~/.zsh-project-options` 中）。
- 当有插件（如 Oh My Zsh、Powerlevel10k、autosuggestions）或系统应用有新版本时，新打开终端将看到高亮提示：

```text
💡 [Zsh 更新提示] 检测到以下插件/应用有可用更新：
  • [插件/主题] zsh-autosuggestions (落后 2 个提交)
  • [应用工具] eza (Homebrew 有新版本)
  提示：可在终端输入 zsh-update 执行升级
```

### 快捷交互命令
在已安装配置的 Zsh 终端中，你可以直接使用以下快捷命令：

- **`zsh-check-updates`**：立即手动检测所有插件与工具的更新状态。
- **`zsh-update`**：呼出交互式更新流程，确认后一键升级最新版本。

---

## 常用按键与功能

| 按键 / 命令 | 功能效果 |
| --- | --- |
| **右方向键 (`→`)** | 光标在末尾时接受自动建议（灰色文字） |
| **Tab** | 智能路径与命令补全 |
| **Ctrl + R** | FZF 历史命令模糊查找（支持多终端实时共享历史） |
| **Ctrl + T** | FZF 文件选择（集成 `bat` 代码实时预览） |
| **Alt + C** | FZF 目录选择（集成 `eza` 目录树预览） |
| **上 / 下方向键** | 按已输入前缀搜索历史命令 |
| **双击 Esc** | OMZ sudo 插件：为当前正在输入的命令添加 `sudo` 前缀 |
| **`y`** | 启动 Yazi 终端文件管理器，退出时自动跳转至所选目录 |
| **`z <关键词>`** | zoxide 智能目录跳转 |
| **`ll` / `la`** | eza 现代化彩色列表（带图标、文件大小与详细权限） |
| **`gst`** | OMZ Git 状态别名（等同于 `git status`） |
| **`lzd`** | 启动 lazydocker 容器终端面板 |

---

## 配置回退与安全恢复

如果需要回退到之前的某次安装状态：

1. 查看安装时提示的备份路径（通常位于 `~/.local/state/zsh-project/install-XXXXXXXX/`）。
2. 执行回滚命令：

```bash
bash install.sh --rollback ~/.local/state/zsh-project/install-XXXXXXXX
```

3. 恢复工具会对当前的配置文件哈希进行校验，确认未被意外修改后安全覆盖回原状态。

---

## 进阶与排查

详细的手动配置教程、各发行版软件差异和日常故障排查方法，请参阅：
- [Linux 与 macOS Zsh 完整配置教程](LINUX_ZSH_SETUP_GUIDE.md)
- [架构设计与开发规范文档](DEVELOPMENT.md)
- [问题原因、修复过程与排查命令](ZSH_TROUBLESHOOTING.md)
