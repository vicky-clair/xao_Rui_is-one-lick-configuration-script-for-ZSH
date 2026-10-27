# 故障排查与历史验证记录

核对日期：2026-10-19。本文按当前脚本说明排查步骤，末尾保留早期 Debian 实测摘要。首次部署见[安装指南](LINUX_ZSH_SETUP_GUIDE.md)，备份和开关见[配置管理](CONFIGURATION_MANAGEMENT.md)。

## 先判断问题所在

| 现象 | 优先查看 |
| --- | --- |
| 文件解析报错、新会话无法启动 | 文件完整性、换行、语法和用户扩展 |
| 配置菜单已关闭工具但仍加载 | 是否使用根目录参考 `.zshrc`，是否仍在旧会话 |
| 建议/插件缺失 | OMZ 主入口和插件文件，而不只是目录存在 |
| 加载横幅后停顿或 cd 很慢 | vfox 激活、目录钩子、Fastfetch、用户扩展 |
| 更新失败或提示一直存在 | 检查范围、网络、包索引、默认超时和缓存 |
| Neovim 只有小块显示区域 | PTY 尺寸、终端协商、resize 和编辑器配置 |
| tmux 复制不到本机 | tmux 缓冲区、OSC 52、客户端及中间层设置 |
| 回退被拒绝 | 备份归属、文件后续修改、快照类型与完整性 |

先记录 `git rev-parse --short HEAD`、系统/架构、Bash/Zsh 版本及使用的配置来源。当前测试结果见[测试与验收](INSTALLER_TESTING.md)，不要把历史截图或旧日志当成新版本的完整验收结果。

## 1. 无法启动、语法错误或文件截断

保留现有会话。必要时从可用终端运行 `bash --noprofile --norc`，或用 `zsh -f` 跳过通常的用户启动文件；系统级初始化仍可能执行。

```bash
zsh -n "$HOME/.zshrc"
wc -l "$HOME/.zshrc"
tail -n 15 "$HOME/.zshrc"
```

`parse error near` 可能由引号、括号、fi/花括号缺失或 Windows 换行造成。检查报错附近以及文件末尾，不按旧文档固定行数判断文件完整性。采用 UTF-8 无 BOM、LF 文件，优先传完整文件，不在终端粘贴长段配置。

需要替换时先传至新文件，用 `zsh -n` 检查，比较差异并备份当前内容，再部署；详细路径见[安装指南](LINUX_ZSH_SETUP_GUIDE.md)。不要直接执行 `cp .zshrc ~/.zshrc`：根目录参考配置和安装模板并不等价。

交互终端粘贴注释后出现 `command not found: #`，通常是该会话没有启用交互注释。可省略注释行或在自己的交互会话运行 `setopt interactivecomments`。这不表示配置文件里的中文注释非法。

## 2. Instant Prompt 警告或主题显示异常

出现 `Console output during zsh initialization detected` 时，检查配置中是否仍 source 了 `p10k-instant-prompt` 缓存。本项目保留横幅和 Fastfetch 输出，模板在主题前后设置：

```zsh
typeset -g POWERLEVEL9K_INSTANT_PROMPT=off
```

保留 Powerlevel10k 主题，移除或停用自己配置中的 Instant Prompt 缓存加载段即可；不要为了消除警告删除整个主题。主题向导可能修改 `.zshrc`，运行后再次比较相关部分。

图标显示方框时，检查显示终端的字体及 UTF-8 设置。SSH 场景下字体主要由客户端终端选择；不同字体、终端和个人 `.p10k.zsh` 不会得到完全相同的截图效果。

## 3. 自动建议、补全或高亮不工作

先查实际文件：

```bash
test -r "$HOME/.oh-my-zsh/oh-my-zsh.sh"
test -r "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh"
test -d "$HOME/.oh-my-zsh/custom/plugins/zsh-completions/src"
test -r "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
```

以上 test 没有输出，用退出码判断。OMZ 只有 custom 目录并不代表完整安装；安装器遇到主入口缺失会停止。不要删除 custom 后重装，可先在独立目录获取完整官方 OMZ，比较并保留自定义内容后恢复。

正确接入顺序为：额外补全的 `src` 先加入 fpath → OMZ 初始化补全和自动建议 → 工具/按键/个人扩展 → 语法高亮。不要同时手动运行 compinit 并让 OMZ 再次初始化，也不要多处加载高亮。

在新 Zsh 中用 `whence -v compdef _zsh_autosuggest_start _zsh_highlight` 检查函数。根目录参考配置有 OMZ 缺失时的自动建议备用加载，安装模板只有备用补全，这一差异不能忽略。

## 4. 工具已安装但 y、lg、lzd、tv、tre、agrep 或其它命令缺失

先在目标会话确认 `command -v yazi`、`command -v lazygit`、`command -v lazydocker`、`command -v tv`、`command -v tre` 或 `command -v agrep`。二进制不在 PATH 时先找到实际安装目录；旧机器上的 `~/.version-fox/sdks/golang/packages/bin` 不一定适用于新机器。

使用安装模板时：

```bash
bash install.sh --configure
bash install.sh --set full=1
bash install.sh --set television=1
bash install.sh --set tre=1
bash install.sh --set lazydocker=1
bash install.sh --set lazygit=1
```

只选择需要的设置，然后新开 Zsh。`full=1` 控制 Yazi/FZF/eza/zoxide/Neovim/television/tre 等集成；lazydocker 和 lazygit 有独立开关。开关不会安装软件，普通安装器会按本次选项重写开关。

- **television 快捷键与 FZF 共存问题**：television 默认以优雅共存模式加载，专享 `Ctrl+P` 快捷呼出。若希望由 television 完全接管文件与历史搜索按键，可运行 `bash install.sh --set tv-keys=1`（将 `Ctrl+T` 绑定至 `tv-smart-autocomplete`，`Ctrl+R` 绑定至 `tv-shell-history`）；随时运行 `--set tv-keys=0` 可切回 FZF 优先模式。
- **tre 编号跳转失效**：`tre` 自动封装 `-e` 编号模式并在执行后加载 `/tmp/tre_aliases_$USER`。若编号别名未生效，检查临时文件写权限以及是否已安装并配置 `EDITOR`（如 Neovim/Vim）。
- **lazydocker 状态异常**：存在对应二进制不表示服务已配置：lazydocker 仍依赖可连接的 Docker 环境。按实际错误处理，不把 socket 权限修改当作通用修复。
- **Yazi 媒体预览缺失或无法生成缩略图**：参考 [Yazi 官方安装文档](https://yazi-rs.github.io/docs/installation/)，Yazi 依赖外部工具提供高阶预览与缩略图支持：
  - **文件类型检测**：依赖 `file`（核心基础依赖，安装器已默认安装）。
  - **视频封面**：依赖 `ffmpeg`（Homebrew 优先推荐 `ffmpeg-full`）。
  - **压缩包预览**：依赖 `7z` / `7zz`（`7zip`、`sevenzip` 或 `p7zip-full`）。
  - **PDF 预览**：依赖 `pdftoppm`（`poppler` 或 `poppler-utils`）。
  - **字体与复杂图片预览**：依赖 `magick`（`imagemagick` 或 `imagemagick-full`）。
  - **SVG 矢量图预览**：依赖 `resvg`。
  - **内容检索与跳转**：依赖 `ripgrep` (`rg`)、`fd`、`fzf`、`zoxide`。
  - **图标字体**：推荐使用 Nerd Fonts，Homebrew 可安装 `font-symbols-only-nerd-font`。
  若 macOS 上部分全量库出现软链接冲突，可执行官方强制覆盖链接命令：`brew link ffmpeg-full imagemagick-full -f --overwrite`；其他平台可使用 `bash install.sh --retry-failed <组件名>` 进行单项补偿安装。

## 5. vfox 超时、启动慢或切换目录慢

先运行只读体检，需要测量时再运行真实启动诊断：

```bash
bash install.sh --doctor
bash install.sh --profile-startup
```

诊断会执行 `.zshrc` 和 HOME 目录钩子，可能触发插件的正常副作用。超时约 32 秒，不适合用于测试需要读取键盘的交互步骤。

单独检查激活命令，可在有 timeout 的环境中执行：

```bash
timeout -k 1s 5s vfox activate zsh
```

macOS 有 gtimeout 时使用 gtimeout。该命令只输出激活脚本，不执行输出。

当前配置采用**环境缓存机制**（位于 `${XDG_STATE_HOME:-$HOME/.local/state}/zsh-project/vfox-activate.zsh`），日常启动直接读取本地缓存（耗时 <1ms），彻底杜绝由于 vfox 联网检索插件导致终端启动冻结数秒的问题。安装器也会在初次安装时预生成该缓存。
当用户通过 `vfox add/use` 安装或切换了全局 SDK 后，可在终端输入 **`vfox-refresh`** 命令手动刷新缓存并即时生效。
同时在成功激活后移除 `_vfox_hook`，保留其它钩子，避免历史上出现的目录切换阻塞；代价是不通过这两个钩子自动切换 SDK。

如果不需要 vfox，可通过 `bash install.sh --set vfox=0` 关闭安装模板中的激活，然后新开会话。根目录参考配置不使用这个开关，需先确认配置来源。不要为修复启动添加第二次无保护的激活。

需要更细跟踪时，在理解它会实际执行配置的前提下，用有时限的命令：

```bash
PS4='+%N:%i> ' timeout -k 2s 20s zsh -xic 'exit'
printf '退出码=%s\n' "$?"
```

124 通常表示超时，137 表示被 SIGKILL 结束，不能仅凭退出码确定具体根因。跟踪输出可能展开个人环境变量，分享前检查内容。模板普通计时不包含末尾用户扩展、高亮和首次提示符钩子；不是完整性能基准。

## 6. FZF 兼容性、预览或共享历史异常

`fzf --zsh` 不支持时，模板依次尝试系统、Homebrew 和 `~/.fzf.zsh` 的集成脚本；都缺失才提示升级。官方内置集成参数从 0.48.0 提供，参见[FZF 说明](https://github.com/junegunn/fzf#setting-up-shell-integration)。完整安装模式会尝试处理旧接口，不能只凭版本命令成功判断快捷键已接入。

预览报错时分别检查 fd/fdfind、bat/batcat、eza 的可用性。模板已对 `tokyonight_night` 做存在检查；用户自行设置不存在的 BAT_THEME 仍可能导致预览失败。Fastfetch 的个人配置文件不存在时，当前模板会调用默认配置，无需再粘贴重复初始化块。

共享历史使用 `~/.zhistory`，启用 share_history 并关闭另外两个增量追加选项。两个同用户会话中，用独特的 echo 标记测试：A 执行后等待提示符，B 执行一次命令再打开 Ctrl+R，并用 `fc -l` 辅助判断。FZF 可能同时匹配检查命令和真正的标记，不以当前选中行判断是否同步。

上下方向键是前缀搜索。即使 OMZ 加载了 history-substring-search 插件，也不表示上下键已改成子串搜索。

## 7. 更新检测不完整或更新提示未消失

出现“部分检测失败，保留原缓存”时，先检查 GitHub 网络和相关包查询。已识别的查询失败会保留旧清单并返回非零，不能据此认定没有更新。

```bash
bash scripts/check_updates.sh --timeout 15 --lang zh
```

这只放宽本次独立检测。`bash install.sh --update` 会重新用默认 5 秒参数检测，不会继承前一条命令的超时；`zsh-check-updates -t 15` 也不会转发参数。当前没有持久化超时设置入口。

更新清单需要区分范围：

- APT 使用本地包索引，不在检查时刷新索引；独立 Release 文件不统一比较版本。
- Zypper、YUM-only 以及没有 checkupdates 的 Arch 缺少对应应用检查路径。
- 检查可以 Git fetch 和写缓存；它不是完全无写入的体检。
- 自动检查在新会话判断间隔，触发前就可能写时间戳；失败后可手动重查。
- `auto-update=0` 停止周期性检查，已有缓存仍可显示。

更新时有本地修改的 Git helper 目标会跳过，TPM、FZF 和包管理器错误也可能留下待处理状态。Linux 系统包不会被 `--update` 自动升级，应按相应发行版执行选定的软件包更新；不要将所有系统升级命令一次混用。

若目标是同步项目模板，应检查仓库改动、更新项目源码后重新运行安装器；它会备份并重新部署选项和模板，可能调用包管理器。不要再用“重装固定 2～5 秒”或“只替换变化行”判断行为。

## 8. 主安装器下载失败或失败组件重试

```bash
bash install.sh --retry-failed
bash install.sh --retry-failed lazydocker
```

主安装器的 lazydocker Release 资产名仍不含版本号；独立重试入口按版本号拼接，遇到该下载问题可使用它。其它组件通常通过系统包管理器重试，不能保证具有普通安装器的全部下载回退能力。

失败日志位于状态目录 `retry-XXXXXXXX/组件.log`。失败清单只保留包名，并非所有安装阶段的完整状态；TPM 安装流程可能忽略失败退出码，仍需检查插件文件和实际界面。

单文件安装自举若退化为下载少数模板，管理器或完整安装器可能缺失。此时使用完整仓库，并从仓库直接执行相关命令。修改仓库中的脚本后，状态目录的旧副本不会随 git pull 自动更新。

## 9. tmux 版本、终端类型和剪贴板

模板直接使用 terminal-features 和 display-popup，需要 tmux 3.2 起的功能，见[官方发布说明](https://github.com/tmux/tmux/issues/2737)。更老版本可能报未知选项/命令，不能只删除一条报错就推断插件兼容。

遇到 `missing or unsuitable terminal`：

```bash
printf 'TERM=%s\n' "$TERM"
infocmp "$TERM"
infocmp tmux-256color
```

检查外层 TERM 和目标机 terminfo，而不是盲目将所有场景的 TERM 设为 tmux-256color。缺少条目时按目标发行版安装相应终端数据库；该错误也可能来自错误的 TERM 值。

复制与输入卡死问题排查：

1. **输入文字卡住、按键无响应，只有多次按 `Ctrl+C` 才恢复**：
   - **根本原因**：tmux 开启了鼠标支持，鼠标拖选（或触控板误触微晃）触发了 `copy-mode-vi` 复制模式。如果配置使用的是 `copy-pipe` 而非 `copy-pipe-and-cancel`，鼠标松开后窗格仍停留在复制模式中，后续键盘输入的英文字母全部被当成 vi 移动命令截获吞并，表现为完全无法打字；按 `Ctrl+C` 触发了内部 `cancel` 退出复制模式后才恢复。
   - **解决办法**：使用本项目最新配置，鼠标拖选（`MouseDragEnd1Pane`）、双击、三击及键盘 `y` 均绑定 `copy-pipe-and-cancel`；同时绑定鼠标单击（`MouseDown1Pane`）及 `Escape` 随时退出复制模式。
2. **tmux 远程无法复制到本地客户端**：
   - **检查 OSC 52 支持**：tmux 内运行 `printf "\033]52;c;%s\a" "$(printf 'test-osc52' | base64)"`，看本地剪贴板是否变为 `test-osc52`。若未生效，检查本地终端模拟器（如 iTerm2 需要开启剪贴板权限，Windows Terminal 需新版支持）。
   - **通配终端特性**：本项目已配置 `set -as terminal-features ",*:RGB:clipboard"` 与 `set -as terminal-overrides ',*:Ms=\E]52;%p1%s;%p2%s\7'`，自动兼容各类现代终端。
   - **xclip 挂起防护**：SSH 场景下若有残留或失效的 `$DISPLAY`，调用 `xclip` 可能长时间挂起。本项目已加入 `timeout 1s` 超时熔断保护。
   - **原生终端选择兜底**：任何时候均可按住 **`Shift` 键**再用鼠标拖选，直接绕过 tmux 调用本地终端原生剪贴板。
3. **tmux 内按前缀再按 p 能否粘贴**？能粘贴说明 tmux 内部缓冲区正常；从外部粘贴至远程请直接使用终端粘贴键（如 `Ctrl+Shift+V` 或 `Cmd+V`）。

## 10. Neovim 显示范围异常或出现转义字符

80×24 显示区域、终端应答被打印等现象可能与 PTY 尺寸、客户端协商、复用器、输入模式或编辑器配置有关。仅凭截图中的一串转义字符无法证明具体因果链。

先在 Shell 检查：

```bash
stty size
printf 'TERM=%s\n' "$TERM"
command -v resize
command -v nvim
```

调整窗口大小后再次比较尺寸；可用 `command nvim --clean` 临时排除个人编辑器配置。项目 nvim 包装函数只在存在 resize 时执行它，然后启动编辑器；TRAPWINCH 只尝试重绘 Zsh 提示符，不能保证修复 SSH 尺寸协商。

Debian 13 中 `/usr/bin/resize` 由 xterm 包提供，参见[官方文件清单](https://packages.debian.org/trixie/amd64/xterm/filelist)。安装器当前尝试的 x11-utils 不能保证提供它。需要此工具时按包归属安装，再验证命令是否存在，不依据安装日志中的其它依赖名称判断。

## 11. 回退失败、开关不生效或残留锁

先运行 `--list-backups` 与 `--diff-backup DIR --scope zsh`。检查备份 HOME、state 文件及当前文件是否在操作后被修改。

备份内原文件保存旧内容，sha256 保存操作后内容；二者不是同一时点。不要用备份原文件哈希覆盖记录以绕过拒绝覆盖检查。

传统 `--rollback` 面向安装快照；单项设置的 manage 快照使用范围恢复入口。安装中断可能没有完整哈希，多文件恢复也不是事务；先比较现有文件和备份再决定手动恢复。

开关不生效时确认配置来源、新会话和选项文件。`git pull` 不会改 HOME 配置或状态目录脚本副本。停用后新会话没有 zsh-config，使用完整仓库里的 Bash 管理入口恢复。

遇到 manage.lock/retry.lock，先确认没有对应操作运行，再检查上次日志并处理残留锁。不要并发执行安装、管理和重试，也不要直接删除全部状态目录。

## 12. 现代终端模拟器与字体排查

### (1) macOS Gatekeeper 阻止或 Homebrew Cask 禁用 Alacritty
- **现象**：执行 `brew install --cask alacritty` 报 `Cask 'alacritty' has been disabled because it does not pass the macOS Gatekeeper check!`；或者打开应用提示“已损坏，无法打开”。
- **原因**：Homebrew 官方于 2026-09-01 暂时禁用了 `alacritty` Cask（由于上游构建公证签名策略变更）。
- **处理方式**：通过 GitHub 官方 Release 下载 `.dmg` 镜像，手动拖入 `/Applications/`，并执行以下命令移除隔离属性：
  ```bash
  xattr -r -d com.apple.quarantine /Applications/Alacritty.app
  mkdir -p ~/.local/bin && ln -sf /Applications/Alacritty.app/Contents/MacOS/alacritty ~/.local/bin/alacritty
  ```

### (2) 终端图标显示方框、乱码或 Powerlevel10k 提示符断裂
- **现象**：P10k 箭头、Git 图标或 Yazi 文件图标显示为乱码或方框问号。
- **原因**：终端未正确配置 Nerd Font 字体。
- **处理方式**：
  1. 确保安装了配套字体：
     ```bash
     brew install --cask font-jetbrains-mono-nerd-font font-meslo-for-powerlevel10k
     ```
  2. 在终端配置文件中指定字体名称：
     - **WezTerm** (`~/.wezterm.lua`):
       ```lua
       local wezterm = require 'wezterm'
       local config = wezterm.config_builder()
       config.font = wezterm.font("JetBrainsMono Nerd Font")
       return config
       ```
     - **Ghostty** (`~/.config/ghostty/config`):
       ```text
       font-family = "JetBrainsMono Nerd Font"
       ```
     - **Alacritty** (`~/.config/alacritty/alacritty.toml`):
       ```toml
       [font.normal]
       family = "JetBrainsMono Nerd Font"
       ```

### (3) `install.sh --doctor` 体检时 `ffmpeg` 阻塞或卡住
- **现象**：体检执行到 `FOUND: ffmpeg` 之后长时间无响应。
- **原因**：`ffmpeg` 默认会在子进程中监听标准输入（stdin）等待键盘交互。
- **处理方式**：已在当前项目的 `scripts/manage.sh` 中为 `ffmpeg -version` 增加了 `-nostdin </dev/null` 重定向。若此前已安装旧版管理脚本，只需在仓库根目录执行 `git pull` 并将 `scripts/manage.sh` 重新同步至状态目录即可。

### (4) Tmux 状态栏在屏幕上方（置顶）或右侧 CPU/内存/网络等硬件监控模块缺失
- **现象**：进入 Tmux 终端时，状态栏出现在屏幕最顶端，或者右侧的状态栏彻底空白，没有显示 CPU、内存、磁盘、实时网速和时间。
- **原因**：
  1. **后台 Tmux 守护进程未重载**：Tmux 采用 C/S 客户端-服务端架构。直接关闭终端或断开 SSH 只会断开连接，后台的 Tmux Server 依然在运行。重新连入后只会 attach 挂载到旧进程上，**并不会自动读取磁盘上更新后的 `~/.tmux.conf`**。若旧进程继承了 `status-position top`，就会一直保持置顶。
  2. **旧版渲染命令失效报错**：旧版主题曾使用已被作者废弃的 `bin/powerkit-render` 脚本，升级到 `v2.7.2` 后新引擎已重构为 `src/render_plugins.sh`。未重载配置的旧 Tmux 进程每隔 5 秒调用不存在的文件报错，导致右侧状态栏无法渲染。
- **处理方式**：
  1. **快捷键热重载**：在 Tmux 终端内直接按快捷键：**`Ctrl + a` 紧接着按 `r`**，底部弹出绿色提示 `✓ ~/.tmux.conf reloaded successfully!` 即刻恢复到底部并亮起全部监控指标。
  2. **命令重载**：在终端执行 `tmux source-file ~/.tmux.conf`。
  3. **插件更新**：按 `Ctrl + a` 然后按 `I`（大写 i）由 TPM 自动更新补齐插件。
  4. **台式机无电池优化**：若为台式机/工控机/云服务器，可编辑 `~/.tmux.conf` 将 `@theme_plugins` 中的 `battery` 移除，避免显示 `0%` 虚拟电池。
  5. **新系统说明**：在全新 Linux 系统上首次安装时，Tmux 无任何历史进程残留，启动即会自动置底并正常渲染所有模块，完全不会复现此问题。

## 历史验证摘要

以下保留自旧文档的 2026-09-06 至 09-07 Debian 13 / Zsh 5.9 用户反馈，属于历史记录，本轮未再次连接目标机验证。

| 项目 | 当时记录 |
| --- | --- |
| 主题、启动展示、语法 | 用户确认正常；单次计时曾为 890ms、1615ms，不作为性能保证 |
| 自动建议 | 恢复缺失的 OMZ 主程序后，函数和右键接受建议通过 |
| 高亮、补全、FZF | 用户反馈交互正常 |
| 共享历史 | 第二终端确认能搜索到标记，曾因选中检查命令误判 |
| Yazi、Neovim、eza、zoxide、手册 | 当时记录为可用，未覆盖所有插件和媒体功能 |
| lazydocker | 补充实际 Go 工具路径后版本和界面可用 |
| vfox | 曾出现激活/目录钩子阻塞；加入超时并移除自动钩子，内部根因未确认 |
| extract | 函数存在，但未执行实际解压测试 |
| Git | gst 能调用 Git，未以此验证仓库写操作 |
| Linux 回归 | 曾记录安装器通过，管理诊断在终端场景失败；后续增加关闭作业控制、空输入及 PTY 用例 |

历史上还修复过 int() 计时报错、模板截断、Instant Prompt 输出冲突、补全/高亮重复加载。当前实现和本轮测试边界以[开发文档](DEVELOPMENT.md)及[测试与验收](INSTALLER_TESTING.md)为准。
