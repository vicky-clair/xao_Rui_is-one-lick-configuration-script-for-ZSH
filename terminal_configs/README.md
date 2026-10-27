# 现代化终端仿真器推荐配置 (WezTerm & Alacritty)

本目录为当前 ZSH / Tmux 环境专门适配优化的现代化终端（**WezTerm** 与 **Alacritty**）配置文件。与项目的 Tokyo Night 状态栏、Powerlevel10k 提示符及 Neovim 保持 100% 视觉与体验一致。

---

## 目录结构

```text
terminal_configs/
├── wezterm/
│   └── wezterm.lua        # WezTerm 完整配置 (含全套字体回退、WebGPU 硬件加速与毛玻璃效果)
├── alacritty/
│   ├── alacritty.yml      # Alacritty v0.12 及以下版本配置 (当前 Pop!_OS 22.04 默认)
│   └── alacritty.toml     # Alacritty v0.13+ 最新 TOML 格式配置
└── README.md              # 配置指南与效果说明
```

---

## 优化要点与改进空间

### 1. 字体与排版优化 (Typography & Fallbacks)
- **主英文字体**：统一使用 `JetBrainsMono Nerd Font`，提供一流的代码连字（Ligatures）与数千个现代化开发图标（Git 分支、CPU、电量、Neovim 图标等）。
- **中文平滑回退 (WezTerm)**：
  配置了多级回退链：`JetBrainsMono Nerd Font` -> `Noto Sans CJK SC` (思源黑体) -> `WenQuanYi Micro Hei Mono` -> `Noto Color Emoji`。
  彻底根治中文字符缺失、字体高度错位或回退到繁体/手写楷体导致的视觉割裂问题。
- **行距微调**：行高优化为 `1.05`，窗口内边距设为 `12px`，避免文字直接紧贴窗口边框。

### 2. 视觉美化 (Tokyo Night 官方色系)
- 配色方案对齐官方 **Tokyo Night** 深色基调（背景 `#1A1B26`），与终端内的 Zsh、Tmux 底部状态栏、Bat、Eza 与 LazyGit 实现浑然一体的沉浸感。
- **透明度与质感**：背景透明度设为 `0.95`，兼顾通透质感与高对比度文字可读性。
- **光标动画**：采用呼吸竖线 `BlinkingBar`（650ms 频率），打字体验顺滑自然。

### 3. 与 Tmux 的协同改进
- **防止双状态栏**：WezTerm 配置了 `hide_tab_bar_if_only_one_tab = true`，当只开一个标签页时隐藏 WezTerm 顶栏，全心交给 Tmux 的底部状态栏。

### 4. 渲染性能 (GPU 加速)
- WezTerm 默认启用 `WebGpu` 引擎与 `120 FPS` 帧率上限，无论是本地还是远程开发均丝滑无顿挫。
- 关闭了尖锐的系统蜂鸣音 (`audible_bell = "Disabled"`)。

---

## 部署与生效方法

### 方式 A：WezTerm
将配置复制或软链接至用户配置目录：
```bash
mkdir -p ~/.config/wezterm
cp terminal_configs/wezterm/wezterm.lua ~/.config/wezterm/wezterm.lua
```
*注：WezTerm 支持热重载，保存配置后窗口会瞬间自动刷新生效。*

### 方式 B：Alacritty
针对当前 Linux 发行版（根据版本选择）：
```bash
mkdir -p ~/.config/alacritty
# 若 Alacritty 为 0.12 版本（如当前 Pop!_OS 22.04 LTS）：
cp terminal_configs/alacritty/alacritty.yml ~/.config/alacritty/alacritty.yml

# 若未来升级至 0.13+ 版本：
cp terminal_configs/alacritty/alacritty.toml ~/.config/alacritty/alacritty.toml
```
