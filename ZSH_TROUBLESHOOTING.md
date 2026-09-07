# Zsh 配置问题与修复记录

记录日期：2026-09-06

## 环境与修改范围

- 运行环境：Debian GNU/Linux 13，Zsh 5.9，通过 Windows Terminal 的 SSH 会话使用。
- 本地配置目录：`C:\XMWJJ\ZSH`。
- Debian 配置文件：`/home/hailan20251015/.zshrc`、`/home/hailan20251015/.zshenv`。
- 主题：Powerlevel10k，已确认安装于 `~/powerlevel10k`。
- 系统信息工具：`/usr/bin/fastfetch`。
- 修改范围限定为 Zsh 配置；修改其它设置或文件前，需要用户同意。本记录文档由用户明确要求创建。

## 最终验证结果

用户在 Debian 执行：

```zsh
zsh -n ~/.zshrc && exec zsh
```

早期一次启动验证结果（后续功能测试见下方矩阵）：

- 语法检查通过，Zsh 启动完成。
- 没有 Instant Prompt 初始化输出警告。
- vfox 本次初始化成功，没有卡住。
- 工具加载提示、Fastfetch 系统信息、完成横幅和计时正常显示。
- 本次显示耗时为 **890ms**。这是配置内计时器的单次结果，不代表完整终端启动耗时，也不保证每次相同。

后续用户已确认主题显示正常。耗时曾出现 890ms、1615ms 等不同结果，不据此认定性能提升或回退。

### 最终功能测试矩阵

以下是用户在 Debian 终端完成的交互验证，不是本地自动化测试：

| 项目 | 最终结果 |
| --- | --- |
| `.zshrc`、`.zshenv` 语法 | 通过 |
| 启动横幅、Fastfetch、计时 | 通过，无 Instant Prompt 警告 |
| Powerlevel10k 外观 | 用户确认正常 |
| 自动建议、右方向键接受 | 恢复 OMZ 后通过 |
| 命令高亮、Tab 路径补全 | 通过 |
| FZF Ctrl+R、Ctrl+T、Alt+C | 通过 |
| 跨终端历史共享 | 通过，第二终端截图确认搜到共享命令 |
| sudo 双 Esc 快捷键 | 通过；只测试输入编辑，不要求执行 sudo |
| Yazi `y` 退出目录联动 | 通过 |
| Neovim、eza `ll` / `la` | 通过 |
| zoxide 跳转、手册打开 | 用户确认正常 |
| Git `gst` 别名 | 正常调用 Git；非仓库目录报错符合预期，未专门测试仓库操作 |
| vfox 版本、SDK 列表 | 正常返回 |
| lazydocker | 补充 PATH 后版本检查和界面打开通过 |
| 历史子串搜索 | 函数已加载；上下键仍为前缀搜索，未改为子串搜索 |
| 解压 `extract` | 函数已加载；按用户要求跳过实际解压测试 |

最后一轮用户确认其余测试正常。2026-09-06 的中文注释整理只在 Windows 项目进行，可执行内容已核对一致，尚未对整理版重新开展 Debian 运行验证。

## 1. Instant Prompt 与启动输出冲突

### 现象

启动出现：

```text
[WARNING]: Console output during zsh initialization detected.
```

### 原因

加载 Powerlevel10k Instant Prompt 缓存后，配置继续打印工具状态、横幅并运行 Fastfetch，触发初始化输出警告。

### 修复

用户希望保留完整启动展示，因此关闭 Instant Prompt，继续使用 Powerlevel10k 主题。

注释或删除下面整个缓存加载段：

```zsh
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi
```

在主题加载前设置，并在加载 `~/.p10k.zsh` 后再次确保：

```zsh
typeset -g POWERLEVEL9K_INSTANT_PROMPT=off
```

关闭 Instant Prompt 不等于关闭主题，只是不再提前显示缓存提示符。无需删除主题缓存文件。

## 2. 补全重复初始化及目录错误

### 原因

旧配置先手动执行 `compinit`，随后 Oh My Zsh 再初始化补全。旧的手动缓存逻辑因此被移除。

此外，旧配置把 `zsh-completions` 根目录加入 `fpath`，而补全文件在 `src` 中，加入时机也晚于补全初始化。

### 修复

- 从 OMZ 插件列表中移除 `zsh-completions`。
- 在加载 OMZ 前加入正确目录。
- OMZ 存在时由它统一初始化补全；仅在 OMZ 不存在时手动初始化。

```zsh
typeset -U fpath
if [[ -d "$ZSH_CUSTOM/plugins/zsh-completions/src" ]]; then
  fpath=("$ZSH_CUSTOM/plugins/zsh-completions/src" $fpath)
fi

if [[ -r "$ZSH/oh-my-zsh.sh" ]]; then
  source "$ZSH/oh-my-zsh.sh"
else
  autoload -Uz compinit
  compinit
fi
```

## 3. 高亮与主题重复加载

### 高亮

旧配置通过插件列表和手动 `source` 各加载一次高亮，而且后面还有 FZF 初始化与按键绑定。

修复为：从插件列表移除 `zsh-syntax-highlighting`，仅在配置末尾加载一次。

```zsh
if [[ -r "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]]; then
  source "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
fi
```

### Powerlevel10k

旧配置既让 OMZ 加载主题，又手动加载 `~/powerlevel10k`。修复后设置 `ZSH_THEME=""`，在 OMZ 加载后依次检查独立安装目录和 OMZ 主题目录，只加载第一个可读的主题文件。

`~/.p10k.zsh` 只保留一次 `source`，不要为了设置 Instant Prompt 而重复加载整个主题配置。

## 4. 历史记录选项冲突

旧配置同时启用共享历史和增量写入。修复为：

```zsh
setopt share_history
unsetopt inc_append_history inc_append_history_time
```

当前历史文件为：

```zsh
HISTFILE="$HOME/.zhistory"
```

项目里的 `.zsh_history` 未被这份配置引用。历史文件保存旧命令，不属于必须部署的配置。

## 5. vfox 初始化卡住

### 现象及证据

启动只显示“正在加载常用工具”横幅，之后没有响应。执行跟踪最后停在：

```text
vfox activate zsh
```

带超时的跟踪返回 `137`，表示进程被强制结束。该次卡住发生在 vfox 激活命令，Powerlevel10k 配置已执行到后续步骤。

### 修复

只修改 `.zshrc`，为生成激活脚本的命令增加超时，并且仅在命令成功时执行生成的脚本：

```zsh
if command -v vfox &>/dev/null; then
  if _vfox_init=$(timeout -k 1s 5s vfox activate zsh); then
    if eval "$_vfox_init"; then
      print -P "%F{green}✓%f %F{cyan}vfox%f 已加载 (版本管理)"
    else
      print -P "%F{yellow}⚠ vfox 初始化脚本执行失败%f"
    fi
  else
    print -P "%F{yellow}⚠ vfox 初始化失败或超时，本次已跳过%f"
  fi
  unset _vfox_init
fi
```

5 秒后请求终止，必要时再过 1 秒强制结束。此保护针对 `vfox activate zsh`，不对后续 `eval` 中的操作设置超时。

**状态：已增加启动保护，最近一次 vfox 加载成功；导致此前卡住的根因尚未查明。** 未修改 vfox 配置、安装文件或版本。

## 6. 复制不完整导致语法错误

### 现象

先后出现第 193 行、第 129 行的：

```text
parse error near `\n'
```

第一次提供的内容停在 lazydocker 段内；第二次通过 `wc -l` 确认文件只有 128 行，并在 Yazi 函数的 `builtin cd` 处结束，后续的 `fi`、`}` 和其它配置全部缺失。

### 修复

使用完整文件替换，不要仅补上报错附近的一个 `fi`。建议用 SCP 传输，避免大段终端粘贴截断。

在 Windows PowerShell 中执行：

```powershell
scp "C:\XMWJJ\ZSH\.zshrc" hailan20251015@192.168.9.165:~/.zshrc.new
```

地址和用户名以当前 Debian 连接信息为准。然后在 Debian 中先检查、再备份并替换：

```zsh
zsh -n ~/.zshrc.new &&
cp -p ~/.zshrc ~/.zshrc.backup-$(date +%Y%m%d-%H%M%S) &&
mv ~/.zshrc.new ~/.zshrc &&
exec zsh
```

这些操作只涉及 Zsh 配置、临时配置和备份。语法检查失败时，后面的替换不会执行。备份保留的是替换前状态，不一定是可用版本。

## 7. 其它已处理项目

- 使用 `typeset -U path PATH` 避免重复添加 PATH 项。
- 插件目录计算拆成两步：先定义 `name`，再构造 `dir`，避免在同一个 `local` 声明中依赖刚赋值的变量。
- 本地 `.zshenv` 已为 `$HOME/.cargo/env` 增加可读检查，文件不存在时跳过。Debian 是否同步该文件未在本次输出中确认。
- Fastfetch 保留自动运行，使用 `~/.config/fastfetch/config.jsonc`。最后一次已成功展示；没有修改其配置文件。

## 8. 自动建议未加载：OMZ 主程序缺失

### 现象与定位

`plugins` 包含 `zsh-autosuggestions`，文件存在，但 `_zsh_autosuggest_start` 和 `_zsh_autosuggest_fetch` 找不到。手动加载主文件后两个函数出现，说明主文件可以加载。

后续检查发现 `~/.oh-my-zsh` 只有 `custom` 目录，没有 `oh-my-zsh.sh`。配置走备用补全分支，插件列表没有被 OMZ 处理。这也解释了 OMZ 自带插件最初没有生效。

### 修复与验证

1. 在 `.zshrc` 的 OMZ 缺失分支中增加现有自动建议主文件的直接加载，作为备用逻辑。
2. 获得用户许可后，从官方 `https://github.com/ohmyzsh/ohmyzsh.git` 克隆到独立暂存目录。
3. 检查冲突后复制 OMZ 主程序，跳过已有的 `custom`，保留 `.zshrc`；没有运行自动安装脚本。
4. 新开 Zsh 后确认自动建议函数、sudo、extract、历史子串搜索函数和 `gst` 别名存在。
5. 用户实际测试自动建议、高亮、补全、FZF 和 sudo 快捷键，均正常。

不要因插件目录存在就认定 OMZ 完整安装。当前 OMZ 已恢复，无需重复安装；恢复时留下的 `.omz-restore.*` 暂存目录没有在本轮自动删除。

## 9. lazydocker 存在但命令找不到

### 原因与证据

程序位于 `~/.version-fox/sdks/golang/packages/bin/lazydocker`，但出问题的会话 PATH 没有该目录。由于 `command -v lazydocker` 失败，`.zshrc` 也没有创建 `lzd` 别名。

### 修复

在基础环境中显式加入：

```zsh
export PATH="$HOME/.version-fox/sdks/golang/packages/bin:$PATH"
```

保留 `typeset -U path PATH` 去重。当前终端补充路径和别名后，版本检查及 `lzd` 界面均通过；本地项目已持久化此路径。该固定目录适用于当前机器，迁移时检查是否需要调整。

未修改 Docker 权限、服务状态或 lazydocker 文件。

## 10. 第二个终端似乎搜不到共享历史

通过历史文件检查确认测试命令已写入；第二个终端的 `fc -l` 也出现了带星号的外部会话记录。随后截图中能看到独立的 `echo ZSH_CROSS_SESSION_PROBE_02`。

实际情况是 FZF 同时匹配包含关键词的检查命令和多行历史，当前选中行不是测试命令，容易误认为没有找到。确认截图后，该项通过，没有为此修改历史或 FZF 配置。

复测时在一个终端执行独特的 `echo` 标记，等提示符出现，再到另一个终端执行一次命令并重新打开 Ctrl+R，搜索标记即可。不要只以当前选中行判断是否匹配。

## 11. 交互终端粘贴注释出现报错

`command not found: #` 出现在向交互终端粘贴带注释的测试命令时。该会话没有启用交互注释识别；不影响 `.zshrc` 中正常使用中文注释。后续测试命令省略注释行，没有因此修改用户选项。

## 12. 切换目录后等待约一分钟：vfox 自动钩子

用户报告 `cd dockerdome` 后提示符显示约一分钟耗时。检查确认 `cd` 是内置命令，`_vfox_hook` 同时存在于 `chpwd_functions` 和 `precmd_functions`。当前会话移除这两个位置的 vfox 钩子后，用户反馈恢复正常，证据重点指向该钩子；钩子内部具体阻塞原因尚未查明。

项目 `.zshrc` 在成功执行 vfox 激活脚本之后加入：

```zsh
chpwd_functions=("${(@)chpwd_functions:#_vfox_hook}")
precmd_functions=("${(@)precmd_functions:#_vfox_hook}")
```

保留其它钩子、vfox 命令和启动激活环境，但不再随目录或提示符刷新自动切换 SDK。需要切换版本时，按 vfox 的当前使用说明显式选择版本；不要假设之前选中的版本已经随目录变化。

这是本机避免阻塞的配置措施，不是修复 vfox 内部根因。原有 `timeout` 只保护启动激活命令，并不能约束后续钩子。该持久化修改已写入 Windows 项目，需同步至 Debian 并在新会话复测。若今后需要恢复自动切换，删除上述两行并重新启动 Zsh；延迟可能再次出现。

## 常用排查命令

### 仅检查语法

```zsh
zsh -n ~/.zshrc
```

无输出且退出码为 0 表示语法检查通过，不代表工具初始化一定成功。

### 检查配置位置和工具

```zsh
echo "配置目录=${ZDOTDIR:-$HOME}"
whence -v p10k fastfetch
```

### 查看文件是否截断及报错附近内容

```zsh
wc -l ~/.zshrc
tail -n 12 ~/.zshrc
nl -ba ~/.zshrc | sed -n '115,145p'
```

行数随配置修改而变化，不能只用固定行数判断是否完整，应同时检查文件末尾。

### 启动卡住时

先尝试 Ctrl+C；必要时新开一个 SSH 会话。启动跳过用户启动配置的 Zsh：

```sh
zsh -f
```

然后跟踪交互配置执行：

```zsh
PS4='+%N:%i> ' timeout -k 2s 20s zsh -xic 'exit'
echo "退出码=$?"
```

该命令会实际执行配置和工具初始化。跟踪可能包含令牌或其它环境变量值，分享前遮住敏感内容。`124` 通常表示超时，`137` 表示被强制结束。

单独检查 vfox 激活命令：

```zsh
timeout -k 2s 10s vfox activate zsh
echo "退出码=$?"
```

此命令只输出激活脚本，不执行输出的脚本。

## Tmux 与终端剪贴板常见问题排查

### 1. 终端提示 `missing or unsuitable terminal: tmux-256color`
- **现象**：在 Linux 上输入 `tmux` 报错并无法启动。
- **根因**：精简版 Linux 系统（如部分 Debian/Ubuntu 容器或基础镜像）未预装 `ncurses-term` 终端描述数据库。
- **排查与解决**：
  ```bash
  sudo apt install -y ncurses-term   # Debian / Ubuntu
  sudo dnf install -y ncurses-term   # Fedora
  ```

### 2. 在 Tmux 中复制后，外部系统（Windows/Mac）无法粘贴
- **现象**：在 SSH 远程终端的 Tmux 中划选或按 `y` 复制后，在本地宿主机按 `Ctrl+V` 粘贴为空。
- **根因与排查**：
  1. **终端未启用 OSC 52 剪贴板透传**：Windows Terminal、iTerm2、WezTerm 等现代终端均原生支持。若使用极旧的 Putty 或未开启 OSC 52 的客户端，转义序列会被终端忽略。
  2. **终极兜底方案（Shift 原生穿透）**：按住键盘 `Shift` 键，直接用鼠标在终端框选所需文本，点击右键或按 `Ctrl+C` 复制。此操作 100% 由外层终端直接处理，彻底绕过 tmux。
  3. **检查本地剪贴板工具（针对本地桌面环境）**：
     - Wayland 会话确认安装了 `wl-clipboard`（可用 `command -v wl-copy` 验证）；
     - X11 会话确认安装了 `xclip`。

### 3. 鼠标选中文本后屏幕自动跳回底部
- **现象**：在查看长日志时用鼠标划选，一松开鼠标视野就被弹回屏幕最底部。
- **根因**：原生 Tmux 默认绑定了 `copy-pipe-and-cancel`。
- **解决**：本项目在 `templates/tmux.conf` 中已覆写为 `copy-pipe`，松手仅复制，保持当前视野不跳跃。

### 4. Tokyo Night 主题状态栏图标乱码（显示方框或问号）
- **现象**：Tmux 底部状态栏的时钟、分支或状态指示出现乱码方格。
- **根因**：外层终端（如 Windows Terminal / macOS iTerm2）所选字体不是 Nerd Font。
- **解决**：在终端软件设置中，将字体切换为已打图标补丁的字体（如 `JetBrainsMono Nerd Font`、`MesloLGS NF` 等）。

## Neovim 窗口卡在 80x24 且启动泄漏转义字符排查与解决

### 现象
1. 启动 Neovim（如 `nvim` / `v`），界面只占终端左上角大约 80 列 × 24 行的一个小区域，右侧和下方全是大片黑色空白，状态栏 `[No Name]` 仅占据半截。
2. 顶部第一行出现一长串转义序列字符，形如：
   `^[[?69;0$y^[[?2026;0$y^[[?2027;0$y^[[?2048;0$y^[[?2031;0$y^[P1$r0m^[\^[[?62;4;9;22c^[]11;rgb:0e0e/1010/1919^[\^[0n^[[I^[[<0;129;18M^[[<0;129;18m^[[0`

### 根因深度剖析
- **为什么卡在 80x24（无法铺满全屏）？**
  - 转义序列中的 `^[[<0;129;18M` 是鼠标位置报告，表示物理光标已处于第 129 列，证明物理窗口至少有 130 多列宽。
  - 但 Linux PTY 伪终端驱动的默认初始尺寸正是 VT100 标准的 `80x24`。当使用某些宿主终端（如 Windows 原生 CMD/PowerShell、旧版 SSH 客户端）连接远端时，初次建立连接未向 Linux 发送 `TIOCSWINSZ` / `SIGWINCH` 窗口尺寸协商信号，导致 Linux 内核和 Neovim 误以为屏幕只有 80x24。
- **为什么顶端有一长串转义字符（乱码）？**
  - 这些字符不是乱码，而是 Neovim 发送的现代特性探测代码的**终端回包**：
    - `^[[?2048;0$y`：查询 In-band resize reporting（内联尺寸动态汇报），终端回复不支持；
    - `^[]11;rgb:0e0e/1010/1919`：OSC 11 查询背景色，终端回复为纯黑/深灰；
    - `^[[<0;129;18M`：SGR 鼠标坐标报告。
  - 由于跨网络或终端应答稍有延迟，当回包到达 Linux 时，Neovim 已经完成了 TUI 初始化并处于普通模式（Normal Mode）。Neovim 将终端发回的这一大串应答误识别为了键盘按键（例如 `y` 触发复制，`0` 跳行首，数字和分号直接输入），导致它们被键入到了当前缓冲区第一行。

### 临时急救（1秒解决）
1. **鼠标微调窗口**：用鼠标微调拖动一下终端窗口边缘（或点一下最大化/还原），终端软件会立刻补发 `SIGWINCH` 信号，Neovim 收到后会**瞬间撑满全屏**！
2. **Neovim 内重绘**：在 Normal 模式下输入 `:redraw!` 回车，或按下 `Ctrl + L`。
3. **Shell 终端重置**：退出 Neovim 后，在命令行执行 `eval $(resize)` 或 `reset`。

### 项目长效自愈补丁
本项目已内置了全套自动化自愈与防御机制：
1. **`templates/zshrc.zsh` 包装 `nvim()` 函数**：
   启动 Neovim 前自动调用 `resize` 工具探测物理终端真实行宽列高，写回 Linux 内核 PTY，从源头杜绝 80x24 锁定。
2. **监听 `TRAPWINCH` 信号**：
   在 Zsh 中注册窗口改变信号，确保窗格尺寸实时与物理屏幕无缝联动。
3. **依赖库补充**：
   在 `install.sh` 的 APT 基础依赖中加入 `x11-utils`（提供 `resize`）与 `ncurses-term`。
4. **客户端推荐**：
   在 Windows 上推荐使用微软官方开源的 **Windows Terminal**，原生支持完美 PTY 握手、RGB 真彩色与 Nerd Fonts 图标。

## 16. lazydocker (lzd) 与 y (yazi) 启动提醒与功能缺失排查

### 现象
终端启动横幅中缺少 `✓ lazydocker 管理工具已启用 (命令: lzd)`，且输入 `lzd` 提示 `command not found`；或者 Yazi 的快捷命令 `y` 不可用。

### 根因剖析
1. **选项默认值不一致**：在引入 `~/.zsh-project-options` 配置管理后，`lazygit` 的未配置默认值为 `1`（`${ZSH_PROJECT_LAZYGIT:-1}`），只要检测到命令即生效；而 `lazydocker` 的未配置默认值被设为了 `0`（`${ZSH_PROJECT_LAZYDOCKER:-0}`）。未在选项文件中显式写明 `ZSH_PROJECT_LAZYDOCKER=1` 时，别名与提示会被静默跳过。
2. **安装器未自动继承已有工具**：当系统中已有 lazydocker 时，重新运行 `install.sh` 若用户在安装提示处选 `n`（跳过安装），安装器将 `WITH_LAZYDOCKER=0` 写入了选项文件，导致误关停已有工具。
3. **Yazi `y` 命令依赖 `full` 档案**：Yazi 的快捷包装函数 `y()` 处于 `[[ ${ZSH_PROJECT_FULL:-0} == 1 ]]` 门禁中，在 `basic` 档案或未开启 `full=1` 时不生效。

### 修复与恢复方案
- **本地终端即时恢复**：
  ```bash
  bash install.sh --set lazydocker=1
  bash install.sh --set full=1
  source ~/.zshrc
  ```
- **项目长效补丁**：
  1. 将 `templates/zshrc.zsh` 中 `lazydocker` 默认判断对齐为 `${ZSH_PROJECT_LAZYDOCKER:-1}`。
  2. 在 `install.sh` 交互提示前检测本地 `command -v`，已有工具自动置为 `1`，杜绝覆盖。
  3. 在 `scripts/manage.sh` 的 `--configure` 菜单中将 `lazydocker` 加入默认开启列表。

---

## 17. man 彩色手册页增强与终端提醒集成

### 需求与背景
用户希望将 `man`（系统手册查阅）功能像 `eza`、`lazydocker`、`zoxide` 等工具一样，清晰地在终端启动横幅中展示出来，并保证各平台手册阅读时具备清晰高雅的语法高亮。

### 实现方案
1. 在 `templates/zshrc.zsh` 与 `.zshrc` 中导出标准的 `LESS_TERMCAP_*` 终端高亮变量及 `GROFF_NO_SGR=1`，无论是否加载 Oh My Zsh 插件，`less` 和 `man` 均原生呈现 TokyoNight 配色风格高亮。
2. 在启动横幅加入统一风格的双语提示：
   ```zsh
   _zsh_startup_msg "%F{green}✓%f %F{cyan}man%f 彩色手册已启用 (命令: %F{yellow}man%f)" "%F{green}✓%f %F{cyan}man%f colored man pages enabled (cmd: %F{yellow}man%f)"
   ```
3. 受 `banner=0` 集中静音管理，无任何外部额外依赖，零性能损耗。

---

## 18. 项目二次运行与 Git 拉取后的安装机制答疑（幂等性保证）

### 用户疑问
> 第一次运行 `bash install.sh` 安装配置完成后，如果之后修改了项目并上传 Git，拉取后再次运行 `bash install.sh`，是彻底从头到尾安装一遍，还是会跳过已安装好的部分、只安装修改过的内容？

### 结论与机制
再次运行 `bash install.sh` **绝不会从头到尾重装**，而是具备完整的**幂等性（Idempotence）**，全过程仅需 2~5 秒：
1. **系统与 CLI 依赖 0 秒跳过**：
   - 包管理器在依赖已是最新时直接跳过；
   - `optional_package` 及独立下载均有 `command -v <tool>` 前置守卫，已安装即跳过。
2. **Git 插件与主题完整保留**：
   - `clone_missing()` 遇到已有完整目录直接提示 `保留已有组件` 并立即返回，绝不重新 clone。
3. **配置文件精准热替换**：
   - 自动在 `~/.local/state/zsh-project/` 创建带时间戳和 SHA-256 校验的快照备份；
   - 将最新修改的 `templates/zshrc.zsh` 部署到 `~/.zshrc`；
   - 自动清理旧的 `~/.zshrc.zwc` 编译字节码缓存，保证改动即刻生效。

---

## 后续注意事项

- Windows 项目文件与 Debian 家目录配置是两份文件；本地修改不会自动同步到服务器。
- 保留已连接的终端，先检查语法，再启动新 Zsh 验证。
- 当前计时器通过 `zmodload zsh/datetime` 和一次性 `precmd` 函数计时；已彻底解决跨平台 BSD date 兼容性问题。
- 工具状态提示不能替代各工具功能测试。已测范围以本文测试矩阵为准，不等于验证所有工具的全部能力。
- 未修改 Windows Terminal 字体、Debian 系统设置、Fastfetch 配置或 vfox 配置。
