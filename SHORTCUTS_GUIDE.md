# ⌨️ 终端快捷键全栈排查与完整操作指南（Zsh / Tmux / Screen / TUI 工具）

> 本指南基于仓库当前实现及 **Debian 13 实机 (`tmux 3.5a` + `Zsh 5.9` + `GNU Screen 4.09.01` + 全套 CLI/TUI 工具)** 全栈键位实测编写，详细梳理快捷键拦截层级、已发现的真实冲突与避坑/修复方案，以及各工具常用快捷键速查表。

---

## 目录
1. [快捷键拦截层级：为什么按下去没反应或触发了别的功能？](#1-快捷键拦截层级为什么按下去没反应或触发了别的功能)
2. [实机排查发现的冲突清单与解决方案](#2-实机排查发现的冲突清单与解决方案)
3. [Tmux 快捷键大全（Prefix：`Ctrl+a`）](#3-tmux-快捷键大全prefixctrla)
4. [GNU Screen 共存快捷键大全（Prefix：`Ctrl+b`）](#4-gnu-screen-共存快捷键大全prefixctrlb)
5. [Zsh 命令行与插件快捷键大全](#5-zsh-命令行与插件快捷键大全)
6. [常用 TUI 工具与编辑器快捷键及冲突提醒](#6-常用-tui-工具与编辑器快捷键及冲突提醒)
7. [高频“卡死 / 失灵 / 怎么退出”急救速查表](#7-高频卡死--失灵--怎么退出急救速查表)

---

## 1. 快捷键拦截层级：为什么按下去没反应或触发了别的功能？

按键从键盘按下到最终响应，会严格按**由外向内**的顺序经过每一层拦截；**外层一旦截获，内层永远收不到该按键**：

```text
① 本地终端模拟器（Windows Terminal / WezTerm / Alacritty / iTerm2）
   └─ 拦截系统粘贴（Ctrl+Shift+V / Cmd+V）、Shift+鼠标拖选原生复制等
② Linux TTY 行规程（stty：^C / ^Z / ^D / ^\ / ^S / ^Q）
   └─ 拦截终端控制信号与 XON/XOFF 流控（ixon）
③ 外层 Tmux 全局根表（-T root，无需按 Ctrl+a 即刻触发！）
   └─ vim-tmux-navigator（Ctrl+h/j/k/l/\）、tmux.expose（Alt+e）、鼠标点击拖拽
④ 外层 Tmux 前缀表（-T prefix，先按 Ctrl+a 再按功能键）
   └─ 接管所有 Ctrl+a 开头组合键（包括单按 Ctrl+a）
⑤ 内层 GNU Screen（若在 Tmux 内启动）
   └─ 默认接管 Ctrl+a（冲突！），建议配置 ~/.screenrc 改用 Ctrl+b（escape ^Bb）
⑥ Zsh 行编辑器（ZLE，主映射为 emacs 模式）
   └─ fzf（Ctrl+r/t、Alt+c）、television（Ctrl+p）、lazygit（Ctrl+g）、sudo（Esc Esc）等
⑦ 前台全屏 TUI / 编辑器（Neovim / nano / yazi / tv / lazygit）
   └─ 在最内层接收未被前面 1~6 层截获的按键
```

---

## 2. 实机排查发现的冲突清单与解决方案

以下 8 项均已在实机交互式 PTY 环境下实际验证：

### 冲突 1：`vim-tmux-navigator` 全局拦截 `Ctrl+h / j / k / l / \`（高影响）
* **原因**：`~/.tmux.conf` 加载了 `christoomey/vim-tmux-navigator` 插件，在 `-T root` 全局绑定了无需前缀的 `C-h`、`C-j`、`C-k`、`C-l`、`C-\`。只有当 Tmux 检测到当前窗格 PTY 前台进程名匹配 `view|vim|nvim|fzf` 时才会放行，其余所有程序全部被 Tmux 拦截为“切换窗格”。
* **实测受影响场景**：
  1. **Zsh 命令行**：
     * `Ctrl+k` 无法删除光标至行尾（`kill-line`），而是**向上切换 Tmux 窗格**；
     * `Ctrl+l` 无法清屏（`clear-screen`），而是**向右切换 Tmux 窗格**；
     * `Ctrl+h` / `Ctrl+j` 分别向左/向下切换 Tmux 窗格。
  2. **`nano` 编辑器**：`Ctrl+k`（剪切整行）、`Ctrl+j`（段落对齐）、`Ctrl+h`（帮助）均被 Tmux 劫持为切窗格，无法使用 `Ctrl+k` 剪行。
  3. **`television` (`tv`) 模糊搜索器**：`~/.config/television/config.toml` 默认使用 `ctrl-j`/`ctrl-k` 上下移动、`ctrl-h` 打开帮助、`ctrl-l` 切换布局，但 `tv` 不在插件的进程白名单中，在 `tv` 内按 `Ctrl+h/j/k/l` 会直接切走 Tmux 窗格（请改用 **`↑` / `↓` 方向键** 或 `Ctrl+n` / `Ctrl+p` 移动）。
  4. **在 `screen` 内运行 `nvim` / `fzf`**：`vim-tmux-navigator` 检查的是外层 Tmux 窗格的 `#{pane_tty}`，只能看到 `screen` 进程，因此内嵌 `screen` 中的 `nvim`/`fzf` 同样会被外层 Tmux 抢走 `Ctrl+h/j/k/l`。
  5. **旧版 SSH 终端退格键（Backspace）跳窗格**：部分客户端将 Backspace 发送为 `^H`（即 `Ctrl+h`）而非 `^?`（DEL），会导致按退格键时跳窗格。
* **解决方案**：
  * **临时绕行**：清屏改按 **`Ctrl+a` → `Ctrl+l`**（插件专门保留的清屏映射）或输入 `clear`；在 `tv` 中用 `↑` / `↓` 替代 `Ctrl+k` / `Ctrl+j`；将本地终端退格键设为 `ASCII DEL (127 / ^?)`。
  * **彻底消除冲突（推荐：若不需要用 `Ctrl+h/j/k/l` 跨窗格，且本地 Neovim 未安装配套 `vim-tmux-navigator` 插件）**：注释掉 `~/.tmux.conf` 中的 `set -g @plugin 'christoomey/vim-tmux-navigator'`，重启 Tmux 服务（或手动执行 `tmux unbind -n C-h C-j C-k C-l 'C-\'`）即可恢复 Zsh、`nano` 与 `tv` 的全部原生 `Ctrl+h/j/k/l` 快捷键。

### 冲突 2：`tmux.expose` 绑定全局 `Alt+e` 但缺少可执行文件（中影响）
* **原因**：`~/.tmux.conf` 引入了 `cesarferreira/tmux.expose`，默认在 `-T root` 绑定了 **`Alt+e`（`M-e`）** 调用 `display-popup ... tmux-expose`；但 TPM 仅克隆了该项目的 Rust 源码，未编译安装 `tmux-expose` 二进制。
* **实测表现**：在终端内按 `Alt+e` 会触发一个一闪而逝的失败弹窗并吞掉按键。
* **解决方案**：
  * 若需要使用会话缩略图切换面板：进入 `~/.tmux/plugins/tmux.expose` 执行 `cargo install --path . --locked`（确保 `~/.cargo/bin` 在 `PATH` 中）；
  * 若不需要：从 `~/.tmux.conf` 移除 `set -g @plugin 'cesarferreira/tmux.expose'` 并执行 `tmux unbind -n M-e`。

### 冲突 3：Tmux 与 GNU Screen 均使用 `Ctrl+a` 导致无法脱离/退出（高影响）
* **原因**：`~/.tmux.conf` 将 Tmux 前缀设为 `Ctrl+a`（并 `unbind C-b`），与 `screen` 默认的命令键 `Ctrl+a` 完全重叠。未配置 `~/.screenrc` 时，外层 Tmux 会截获 `Ctrl+a d`（直接脱离 Tmux 而 `screen` 仍处于 `Attached`）以及 `Ctrl+a \`（透传 `\` 导致出现 `exit\` 续行）。
* **解决方案**：
  * **最推荐**：直接用 Tmux 自带窗口（`Ctrl+a c`）和分屏（`Ctrl+a |` / `-`），不必套娃使用 `screen`。
  * **如需并用**：在 `~/.screenrc` 中配置 `escape ^Bb`（将 `screen` 前缀改为 Tmux 已解绑的 `Ctrl+b`），详见第 4 节。

### 冲突 4：Tmux 内部 `Ctrl+a p` 被映射为“粘贴”而非“上一窗口”（易误解）
* **原因**：`~/.tmux.conf` 第 153 行显式执行了 `bind-key p paste-buffer`，**覆盖了 Tmux 原生默认的 `Ctrl+a p`（`previous-window`）**。
* **实测表现**：按 `Ctrl+a` 再按 `p` 会粘贴 Tmux 缓冲区内容，而不是切换回上一个窗口。
* **解决方案**：
  * 切换窗口请用 **`Ctrl+a n`**（下一个）、**`Ctrl+a w`**（交互式窗口树列表）、**`Ctrl+a 1~9`**（按编号直达），或在状态栏上**向上滚动鼠标滚轮**（`WheelUpStatus`）。
  * 粘贴 Tmux 内部缓冲区可用 **`Ctrl+a p`** 或 **`Ctrl+a ]`**。

### 冲突 5：`tmux-tokyo-night` 覆盖了 `Ctrl+a ?`（低影响）
* **原因**：原生 Tmux 中 `Ctrl+a ?` 用于查看全部快捷键（`list-keys`），但 `tmux-tokyo-night` 插件将 `Ctrl+a ?` 绑定为主题选项面板（`options_viewer.sh`），另将快捷键查看器绑定到了 **`Ctrl+a B`（大写 B）**。
* **解决方案**：查看所有生效的 Tmux 快捷键请按 **`Ctrl+a` → `B`（大写 B）**，或按 **`Ctrl+a` → `/`** 后按任意键查询单个键位。

### 冲突 6：Tmux `Ctrl+a m` 覆盖了原生窗格标记键
* **原因**：`~/.tmux.conf` 同时将 `Ctrl+a m` 与 `Ctrl+a z` 均绑定为窗格最大化/还原（`resize-pane -Z`），覆盖了原生 `select-pane -m`（标记窗格）。
* **解决方案**：如需标记窗格以便交换，可在窗格内**点击鼠标右键**选择 `Mark`，或按 `Ctrl+a :` 输入 `select-pane -m`。

### 冲突 7：TTY 流控 `ixon` 导致子程序中按 `Ctrl+s` 冻结输出（中影响）
* **原因**：`stty -a` 显示终端默认开启 `ixon`（`stop = ^S`, `start = ^Q`）。Zsh 自身开启了 `noflowcontrol`（提示符下按 `Ctrl+s` 不会卡死），但运行普通前台程序（如 `cat`、`less` 或未接管 raw 模式的脚本）时，误按 `Ctrl+s` 会触发 XOFF 挂起屏幕输出，看起来像“死机”。
* **解决方案**：
  * **紧急解冻**：按 **`Ctrl+q`** 立即恢复输出；
  * **永久禁用（可选）**：在 `~/.zshrc.local` 中添加 `[[ -t 0 ]] && stty -ixon 2>/dev/null || true`。

### 冲突 8：Zsh 插件对 `Ctrl+g` / `Ctrl+p` / `Alt+l` / `双击 Esc` 的接管
* **`Ctrl+g`（`lazygit-widget`）**：覆盖了 Zsh 原生 `send-break`（终止当前输入或退出 `Ctrl+r` 搜索）。在任意目录按 `Ctrl+g` 会拉起 `lazygit`，取消命令行搜索请改用 **`Esc`** 或 **`Ctrl+c`**。
* **`Ctrl+p`（`television-widget`）**：默认配置（`ZSH_PROJECT_TV_KEYBINDINGS=0`）下覆盖了 Zsh 原生“上一条历史”。请改用 **`↑` / `↓` 方向键**（已增强为前缀子串搜索）或 **`Ctrl+r`**。
* **`Alt+l`（`Esc+l`）**：Oh My Zsh 默认绑定为自动输入并执行 `ls`（`^Q ls^J`），而非 Emacs 单词小写。
* **`双击 Esc`（`\e\e`）**：OMZ `sudo` 插件绑定为在当前命令行自动添加/移除 `sudo` 前缀；因 Tmux `escape-time` 设为 `10ms`、Zsh `KEYTIMEOUT=40`（400ms），连续按两次 `Esc` 取消操作时可能顺带加上 `sudo`。

---

## 3. Tmux 快捷键大全（Prefix：`Ctrl+a`）

> **按键规则**：下表中标记为 `Prefix + 键` 的操作，均需**先按 `Ctrl+a`，双手松开，再按后续键**。

### 3.1 会话管理（Session）
| 快捷键 / 命令 | 作用 | 说明 |
| :--- | :--- | :--- |
| `t` / `ta [名]` / `tls` / `tn 名` | Zsh 快捷命令 | 接入 `main` / 挂载会话 / 列出会话 / 新建会话 |
| **`Ctrl+a` → `d`** | **脱离会话（Detach）** | 挂起到后台保活任务并平稳退回原生 Zsh |
| `Ctrl+a` → `s` | 交互式会话切换 | 上下键选择会话或展开预览 |
| `Ctrl+a` → `$` | 重命名当前会话 | 修改状态栏左下角会话名 |
| `Ctrl+a` → `(` / `)` | 切换到上一 / 下一会话 | 多会话快速轮切 |
| `Ctrl+a` → `L` | 切回最近一次访问的会话 | 两个会话间反复横跳 |
| `Ctrl+a` → `Alt+c` | 修改会话默认目录 | 将当前窗格目录设为整个会话新建窗口的默认目录 |
| `Ctrl+a` → `Ctrl+s` | 手动保存会话快照 | `tmux-resurrect` 保存布局与路径（另有 `continuum` 每 15 分钟自动保存） |
| `Ctrl+a` → `Ctrl+r` | 手动恢复会话快照 | `tmux-resurrect` 恢复上次保存的布局 |

### 3.2 窗口管理（Window，类似于浏览器标签页）
| 快捷键 | 作用 | 说明 |
| :--- | :--- | :--- |
| **`Ctrl+a` → `c`** | **新建窗口** | 继承当前窗格所在目录，编号从 `1` 开始 |
| `Ctrl+a` → `1` ~ `9` | 直达指定编号窗口 | 快速切换标签页 |
| `Ctrl+a` → `n` | 下一个窗口 | 顺序向后切 |
| `Ctrl+a` → `w` | 交互式窗口与窗格树 | 可视化预览所有窗口与窗格，回车跳转 |
| `Ctrl+a` → `f` | 按关键字查找窗口 | 快速定位窗口 |
| `Ctrl+a` → `,` | 重命名当前窗口 | 例如命名为 `dev` / `logs` |
| `Ctrl+a` → `&` | 关闭当前窗口 | 底部确认 `y/n` 后销毁 |
| 状态栏滚轮上/下 | 上一 / 下一窗口 | 鼠标悬停底部状态栏滚动滚轮即可切换 |

### 3.3 窗格与分屏（Pane）
| 快捷键 | 作用 | 说明 |
| :--- | :--- | :--- |
| **`Ctrl+a` → `\|`** | **左右分屏（垂直切分）** | 继承当前目录 |
| **`Ctrl+a` → `-`** | **上下分屏（水平切分）** | 继承当前目录 |
| **`Ctrl+a` → `m` / `z`** | **最大化 / 还原当前窗格** | 临时全屏查看日志/代码，再按恢复 |
| `Ctrl+a` → `方向键` | 切换当前活动窗格 | 支持 500ms 内连续按键（`-r`） |
| `Ctrl+a` → `h/j/k/l` | 向左/下/上/右调整窗格大小 5 格 | 支持连续按键（`-r`） |
| `Ctrl+a` → `Alt+方向键` | 调整窗格大小 5 格 | 同上，方向键版本 |
| `Ctrl+a` → `Ctrl+方向键` | 微调窗格大小 1 格 | 精细调整 |
| `Ctrl+a` → `q` | 显示窗格数字编号 | 闪现编号时按对应数字直接跳转 |
| `Ctrl+a` → `o` / `;` | 下一个窗格 / 上一次活动窗格 | 快速轮换或来回切换 |
| `Ctrl+a` → `{` / `}` | 与上一 / 下一窗格互换位置 | 对调分屏位置 |
| `Ctrl+a` → `!` | 将当前窗格拆分为独立窗口 | 单窗格升级为新标签页 |
| `Ctrl+a` → `Space` | 轮换预设分屏布局 | 等宽、等高、平铺等切换 |
| `Ctrl+a` → `x` | 关闭当前窗格 | 底部确认 `y/n` |
| `Ctrl+h/j/k/l` / `Ctrl+\` | 无需前缀直接切左/下/上/右/上一个窗格 | 由 `vim-tmux-navigator` 提供（**注意冲突 1**） |

### 3.4 复制模式（Vi 键位）、粘贴与剪贴板
| 快捷键 / 鼠标操作 | 作用 | 说明 |
| :--- | :--- | :--- |
| **鼠标拖选松开 / 双击 / 三击** | **自动复制到本地剪贴板并退出** | 通过 OSC 52 同步至 Windows/macOS 剪贴板，不卡死 |
| **按住 `Shift` + 鼠标拖选** | **绕过 Tmux，原生终端选择** | 遇到不支持 OSC 52 的客户端时必用兜底方案 |
| `Ctrl+a` → `[` | 进入 Vi 复制模式 | 右上角显示历史行号 |
| `h/j/k/l` / `w/b` / `0/$` / `g/G` | 复制模式内移动光标 | 分别对应方向、单词、行首尾、缓冲顶/底 |
| `Ctrl+u` / `Ctrl+d` | 向上 / 向下半屏翻页 | `Ctrl+b` / `Ctrl+f` 为整页翻 |
| `/` / `?` / `n` / `N` | 向下/上搜索文本、下一/上一匹配 | 翻查长日志利器 |
| `v` / `V` / `Ctrl+v` | 字符选择 / 整行选择 / 矩形列块选择 | 选定开始 |
| `y` / `Enter` | **复制选区并立即退出复制模式** | 自动走 OSC 52 / 系统剪贴板管道 |
| `Esc` / `q` / 鼠标单击 | 取消选择并退出复制模式 | 随时恢复正常打字 |
| **`Ctrl+a` → `p` 或 `]`** | 粘贴 Tmux 内部复制缓冲区 | 从本地电脑向远程粘贴请用 **`Ctrl+Shift+V`** 或 **`Cmd+V`** |
| `Ctrl+a` → `=` | 查看并选择历史粘贴缓冲区 | 可选最近 50 条记录 |

### 3.5 工具弹窗、帮助与配置管理
| 快捷键 | 作用 | 说明 |
| :--- | :--- | :--- |
| **`Ctrl+a` → `Ctrl+a`** | **向内层发送字面量 `Ctrl+a`** | 用于在 Zsh 命令行跳至行首，或向未改键的 `screen` 透传前缀 |
| **`Ctrl+a` → `Ctrl+l`** | **向内层发送 `Ctrl+l` 清屏** | 绕过 `vim-tmux-navigator` 拦截执行终端清屏 |
| `Ctrl+a` → `g` / `G` | 居中弹窗打开 / 新窗口打开 `lazygit` | 弹窗按 `q` 退出自动返回原窗格 |
| **`Ctrl+a` → `r`** | **热重载 `~/.tmux.conf`** | 底部提示生效，不中断会话 |
| `Ctrl+a` → `B`（大写 B） | 弹出 Tmux 全部快捷键速查表 | `tmux-tokyo-night` 提供的动态查看器 |
| `Ctrl+a` → `?` | 弹出 Tokyo Night 主题选项面板 | 注意已覆盖原生 `list-keys` |
| `Ctrl+a` → `/` | 查询单个前缀按键的功能 | 输入目标键立即显示绑定命令 |
| `Ctrl+a` → `:` | 打开 Tmux 命令提示符 | 手动执行 tmux 命令 |
| `Ctrl+a` → `I` / `U` / `Alt+u` | TPM 安装 / 更新 / 清理插件 | 需大写 `I`、`U` |

---

## 4. GNU Screen 共存快捷键大全（Prefix：`Ctrl+b`）

在 `~/.screenrc` 配置 `escape ^Bb` 后（已同步修改 `192.168.9.165`），外层 `tmux` 使用 **`Ctrl+a`**，内层 `screen` 使用 **`Ctrl+b`**，两者互不干扰：

| 操作目标 | 已配置 `~/.screenrc`（Prefix: `Ctrl+b`） | 未配置 `~/.screenrc` 的其他机器（透传 `Ctrl+a`） |
| :--- | :--- | :--- |
| **脱离 `screen`（后台保活）** | **`Ctrl+b` → `d`** | **`Ctrl+a` → `Ctrl+a` → `d`** |
| **彻底退出当前 `screen` 会话** | 停掉前台进程后输 `exit`；或 **`Ctrl+b` → `\` → `y`** | 停掉前台进程后输 `exit`；或 **`Ctrl+a` → `Ctrl+a` → `\` → `y`** |
| **新建 `screen` 窗口** | `Ctrl+b` → `c` | `Ctrl+a` → `Ctrl+a` → `c` |
| **切换上一 / 下一 `screen` 窗口** | `Ctrl+b` → `p` / `n` | `Ctrl+a` → `Ctrl+a` → `p` / `n` |
| **查看 `screen` 窗口列表** | `Ctrl+b` → `"` | `Ctrl+a` → `Ctrl+a` → `"` |
| **关闭当前 `screen` 窗口** | `Ctrl+b` → `k` → `y` | `Ctrl+a` → `Ctrl+a` → `k` → `y` |
| **向内层发送字面量 `Ctrl+b`** | `Ctrl+b` → `b` | 直接按 `Ctrl+b` |
| **进入 `screen` 回滚/复制模式** | `Ctrl+b` → `[`（`Esc` 退出） | `Ctrl+a` → `Ctrl+a` → `[` |
| **从外部强行关闭指定会话** | `screen -S <会话名> -X quit` | `screen -S <会话名> -X quit` |

---

## 5. Zsh 命令行与插件快捷键大全

### 5.1 常用命令行编辑与导航（含 Tmux 下实测差异标注）
| 快捷键 | 动作 | 在 Tmux 内的实际行为 / 注意事项 |
| :--- | :--- | :--- |
| **`Ctrl+a` → `Ctrl+a`** | 跳到命令行行首 | 单按 `Ctrl+a` 会触发 Tmux 前缀，**必须连按两次** |
| **`Ctrl+e`** | 跳到命令行行尾 | 正常可用 |
| `Alt+b` / `Alt+f`（或 `Ctrl+←` / `Ctrl+→`） | 向左 / 向右按单词移动 | 正常可用 |
| `←` / `→` | 左移字符 / 在行尾**接受灰色自动建议** | 由 `zsh-autosuggestions` 提供 |
| `↑` / `↓` | 按当前已输入前缀搜索历史命令 | 由 `history-substring-search` 提供 |
| **`Ctrl+w`** / `Alt+Backspace` | 删除光标前一个单词 | 正常可用 |
| **`Ctrl+u`** | 清空整行（Zsh 为 `kill-whole-line`） | 正常可用 |
| `Alt+d` / `Ctrl+Delete` | 删除光标后一个单词 | 正常可用 |
| **`Ctrl+k`** | 原生为删除到行尾 | ⚠️ **被 `vim-tmux-navigator` 拦截为向上切窗格** |
| **`Ctrl+a` → `Ctrl+l`** | 清屏（`clear-screen`） | ⚠️ 单按 `Ctrl+l` 会向右切窗格，清屏需先按 `Ctrl+a` |
| `Backspace` | 向左删除字符 | 使用 `^?` (DEL)，正常可用；若终端错发 `^H` 会触发切窗格 |
| `Ctrl+y` | 粘贴刚才剪切（kill）的命令行文本 | 正常可用 |
| `Ctrl+_` 或 `Ctrl+x` → `Ctrl+u` | 撤销上一步命令行编辑 | 正常可用 |
| **`Ctrl+x` → `Ctrl+e`** | 在 `$EDITOR`（Neovim）中编辑当前长命令 | 保存退出 Neovim 后自动执行，写长脚本极实用 |
| `Alt+.` 或 `Alt+_` | 插入上一条命令的最后一个参数 | 连续按可往前翻历史参数 |

### 5.2 工具与插件专属快捷键
| 快捷键 | 所属组件 | 功能说明 | 备注 |
| :--- | :--- | :--- | :--- |
| **`Ctrl+r`** | `fzf` | 交互式模糊搜索历史命令 | 若设 `tv-keys=1` 则由 `television` 接管 |
| **`Ctrl+t`** | `fzf` | 模糊搜索当前目录文件并插入命令行 | 支持 `bat` / `eza` 右侧实时预览 |
| **`Alt+c`** | `fzf` | 模糊搜索子目录并自动 `cd` 进入 | 配合 `fd` + `eza` 目录树预览 |
| **`Tab`** | `fzf` / Zsh | 触发智能补全（如 `cd **<Tab>`、`kill <Tab>`） | 正常可用 |
| **`Ctrl+p`** | `television` (`tv`) | 呼出多通道现代模糊查找器 | 见冲突 1：在 `tv` 内请用 `↑`/`↓` 导航 |
| **`Ctrl+g`** | `lazygit` | 呼出 Git TUI 管理界面 | 覆盖了 Zsh `send-break` |
| **`双击 Esc`** | OMZ `sudo` | 为当前命令行自动加上/去掉 `sudo` 前缀 | — |
| `Alt+l` | OMZ 默认键位 | 自动插入并执行 `ls` | — |
| `Ctrl+c` | TTY `SIGINT` | 中断当前前台命令 / 清空当前输入 | — |
| `Ctrl+z` | TTY `SIGTSTP` | 挂起当前前台任务到后台（可用 `fg` 恢复） | 有挂起任务时第一次输入 `exit` 会提示阻止退出 |
| `Ctrl+d` | TTY `EOF` | 命令行空行时退出当前 Shell；输入中为补全/删字符 | — |

---

## 6. 常用 TUI 工具与编辑器快捷键及冲突提醒

### 6.1 Neovim（当前安装配置为 NvChad v2.5 + 自定义映射）
> 在**直接运行于 Tmux** 时，`vim-tmux-navigator` 会将 `Ctrl+h/j/k/l` 放行给 `nvim`；但在 **`screen` 内运行 `nvim`** 时，这些键会被外层 Tmux 抢走。

| 快捷键 | 模式 | 功能 | 备注 |
| :--- | :--- | :--- | :--- |
| `Space` | Normal | Leader 前缀键 | 如 `<Space>ff` 找文件（Telescope） |
| `;` | Normal | 等同 `:` 进入命令模式 | `~/.config/nvim/lua/mappings.lua` 自定义 |
| `jk` | Insert | 退出插入模式（等同 `<Esc>`） | `~/.config/nvim/lua/mappings.lua` 自定义 |
| `Ctrl+s` | Normal | 保存当前文件（`:w`） | NvChad 默认映射（在终端内若无 raw 模式则有流控风险，nvim 下正常） |
| `Ctrl+h/j/k/l` | Insert | 光标左/下/上/右移动 | NvChad 默认映射 |
| `Ctrl+h/j/k/l` | Normal | 在 Neovim 内部分屏间切换 | 当前未装 nvim 侧插件，切出到其他 Tmux 窗格仍需用 `Ctrl+a + 方向键` |
| `Ctrl+a` → `Ctrl+a` | Normal | 对光标下数字加 1 | 单按 `Ctrl+a` 会被 Tmux 截获 |

### 6.2 `nano` 编辑器
| 快捷键 | 功能 | Tmux 下是否受影响 |
| :--- | :--- | :--- |
| **`Ctrl+o`** | **写入保存（Write Out）** | ✅ 正常（`screen` 改用 `Ctrl+b` 后完全不受影响） |
| **`Ctrl+x`** | **退出 `nano`** | ✅ 正常 |
| `Ctrl+w` | 搜索文本 | ✅ 正常 |
| `Ctrl+u` | 粘贴刚剪切的行 | ✅ 正常 |
| `Ctrl+c` | 显示当前光标行列号 / 取消提示 | ✅ 正常 |
| **`Ctrl+k`** | 原生为“剪切当前行” | ⚠️ **被 `vim-tmux-navigator` 拦截为向上切 Tmux 窗格**（在 `nano` 中剪行请用 **`Alt+6` 复制** + **`Backspace`**，或移除 `vim-tmux-navigator`） |
| **`Ctrl+j`** | 原生为“段落对齐” | ⚠️ **被 `vim-tmux-navigator` 拦截为向下切 Tmux 窗格** |
| `Ctrl+a` → `Ctrl+a` | 跳至行首 | 单按 `Ctrl+a` 被 Tmux 截获，需连按两次 |
| `Ctrl+e` | 跳至行尾 | ✅ 正常 |

### 6.3 `yazi` 文件管理器（通过 `y` 命令启动，退出自动 `cd`）
| 快捷键 | 功能 | Tmux 下注意事项 |
| :--- | :--- | :--- |
| `j` / `k` / `h` / `l`（或方向键） | 上下移动、退回上级、进入目录/打开文件 | ✅ 正常 |
| `Space` / `Ctrl+a`→`Ctrl+a` / `Ctrl+r` | 选中当前、全选、反选 | 全选需按两次 `Ctrl+a` |
| `y` / `x` / `p` / `d` / `D` / `a` / `r` | 复制 / 剪切 / 粘贴 / 回收站 / 永久删除 / 新建 / 重命名 | ✅ 正常 |
| `s` / `S` / `Ctrl+s` | `fd` 文件名搜 / `rg` 内容搜 / 取消搜索 | ✅ 正常 |
| `.` | 切换显示隐藏文件 | ✅ 正常 |
| **`q`** / `Q` | 退出并自动切换 Shell 工作目录 / 退出但不改目录 | ✅ 正常 |

### 6.4 `lazygit`（`lg` / `Ctrl+g` / `Ctrl+a g`）与 `television`（`tv` / `Ctrl+p`）
* **`lazygit`**：`Tab` / `←` / `→` 切面板、`j`/`k`/`↑`/`↓` 移动、`Space` 暂存、`c` 提交、`P`/`p` 推拉、`?` 看帮助、**`q`** 退出。若以 **`Ctrl+a g`** 弹窗打开，注意弹出窗口内尽量不要触发依赖 `Ctrl+h/j/k/l` 的全局跳转。
* **`television` (`tv`)**：**`↑` / `↓`**（或 `Ctrl+n` / `Ctrl+p`）移动选择、`Tab` 多选、`Enter` 确认、`Ctrl+y` 复制条目、`Ctrl+o` 开关预览、`Esc` / `Ctrl+c` 退出（⚠️ 不要在 Tmux 内按 `tv` 默认的 `Ctrl+h/j/k/l`，会触发 `vim-tmux-navigator` 切窗格）。

---

## 7. 高频“卡死 / 失灵 / 怎么退出”急救速查表

| 遇到什么现象 | 真实原因 | 立即恢复 / 正确按键 |
| :--- | :--- | :--- |
| 终端突然完全卡住、敲键盘无任何回显（跑普通命令/文本工具时） | 误按了 `Ctrl+s` 触发 TTY `ixon` 流控暂停 | 立即按 **`Ctrl+q`** 解除暂停 |
| 按 `Ctrl+l` 没清屏反而光标跑去右边窗格了 | `vim-tmux-navigator` 拦截了 `Ctrl+l` | 改按 **`Ctrl+a` → `Ctrl+l`** 清屏，或输入 `clear` |
| 按 `Ctrl+k` 没删到行尾反而切去上面窗格了 | `vim-tmux-navigator` 拦截了 `Ctrl+k` | 在 Zsh 用 `Ctrl+u` / `Ctrl+w`；在 `nano` 用 `Alt+6` |
| 在 `tmux` 里进 `screen` 后按 `Ctrl+a d` 退不出来 | `Ctrl+a` 被外层 `tmux` 抢走导致脱离了 `tmux` | 本仓库配置在 `~/.screenrc` 改用 **`Ctrl+b` → `d`** 脱离；未改配置时连按 **`Ctrl+a` → `Ctrl+a` → `d`** |
| 输入命令或进入复制模式后打字没反应 | 误触了鼠标或复制模式 / 未退出 Vi 模式 | 单击一下窗格或按 **`Esc`** / **`q`** |
| 想用鼠标直接选中并按本地终端习惯复制 | Tmux 鼠标接管了左键拖拽 | **按住 `Shift` 键不放**再拖选 |
| 按 `Ctrl+a` 想让光标回行首却没反应 | Tmux 正在等待前缀后的下一个键 | **再按一次 `Ctrl+a`**（即连按两次 `Ctrl+a`） |
| 按 `Ctrl+a p` 突然粘贴出一堆字而不是切上一窗口 | `~/.tmux.conf` 将 `p` 绑定为 `paste-buffer` | 用 **`Ctrl+a w`** 或 **`Ctrl+a n`** / 状态栏滚轮切窗口 |
| 想看全部 Tmux 快捷键按 `Ctrl+a ?` 出来的却是主题配置 | `tmux-tokyo-night` 占用了 `?` | 改按 **`Ctrl+a` → `B`（大写 B）** 查看全部绑定 |
