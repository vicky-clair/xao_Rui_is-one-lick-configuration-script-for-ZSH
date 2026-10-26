# 项目审计报告

审计日期：2026-10-26　｜　审计基线：commit `68cd8ce`（main）　｜　范围：`install.sh`、`scripts/`、`templates/`、根目录配置、CI 与全部文档

---

## 一、结论摘要

| 等级 | 数量 | 说明 |
| --- | --- | --- |
| 严重 / 高 | 0 | 未发现可被直接利用的漏洞，未发现密钥泄露到仓库或提交历史 |
| 中 | 3 | 供应链校验缺失、文档存在未经验证的 macOS 结论、远程测试流程的凭据处理 |
| 低 | 3 (1项已修复) | 手动更新命令健壮性、复制管道重复、tmux 无自动化测试（L-1 重载累积已完成修复） |
| 信息 | 3 | ShellCheck 结果、CI 覆盖面、本地敏感文件 |

整体代码质量良好：脚本统一 `set -Eeuo pipefail`，拒绝 root/sudo 运行，受管文件写入前检查符号链接，备份带存在状态与 SHA-256，恢复前校验后续修改，管理器不执行选项文件内容，测试套件用命令替身隔离网络与提权。

---

## 二、本次实际执行的检查

| 检查 | 环境 | 结果 |
| --- | --- | --- |
| `bash -n` 六个脚本、`zsh -n` 模板与 `.zshrc` | Debian 13 实机 | 全部通过 |
| `scripts/test_installer.sh` | Debian 13 实机 | 退出码 0，全部 PASS |
| `scripts/test_management.sh` | Debian 13 实机 | 退出码 0，全部 PASS |
| ShellCheck v0.10.0（`-S warning`） | Debian 13 实机（临时二进制，位于 `/tmp`） | 0 error，5 warning（见 I-1） |
| tmux 配置在隔离 socket 加载 | tmux 3.5a | 无报错，`default-terminal` 正确命中 `tmux-256color` |
| tmux 重复加载行为 | tmux 3.5a | 发现选项累积（见 L-1） |
| 换行符检查（CRLF） | 远程部署文件与仓库脚本 | 未发现 CRLF |
| 密钥扫描（工作区 + 全部提交历史） | 本地 | 仓库与历史中无密码；仅未跟踪的 `.zhistory` 含主机信息 |

**未执行**：macOS 实机复测、真实全新安装（会修改系统）、Wayland/WSL 剪贴板实测。

---

## 三、问题清单

### 中风险

#### M-1 第三方下载缺少完整性校验（供应链）
- **位置**：[install.sh](install.sh) L1373-L1540（television、tre、Neovim、lazydocker、lazygit、Nerd Font）；[scripts/retry_tools.sh](scripts/retry_tools.sh) L181-L330；[templates/tmux.conf](templates/tmux.conf) TPM 段
- **现状**：
  - Release 二进制通过 `releases/latest` 下载，仅校验"可执行"或 `--version`，未校验 SHA-256 或签名。
  - vfox 回退路径直接下载并执行 `version-fox/vfox` **main 分支**上的 `install.sh`（L1480-L1481），未固定版本。
  - TPM 与 5 个 tmux 插件均克隆默认分支 HEAD。
  - Homebrew 引导使用官方 `curl | bash` 方式（L631），属于业界惯例。
- **影响**：上游仓库或发布资产被篡改时，会以当前用户权限执行恶意代码。项目在 [DEVELOPMENT.md](DEVELOPMENT.md) 中已承认"没有统一的签名/校验流程"。
- **建议**：对提供 `checksums.txt` 的项目（lazygit、lazydocker、television、Neovim）下载后比对；vfox 脚本固定到 tag；TPM 可固定 commit。

#### M-2 文档中的 macOS 结论未经本次验证
- **位置**：[INSTALLER_TESTING.md](INSTALLER_TESTING.md) 验收表 Tmux 行与日期说明
- **现状**：2026-10-26 的 tmux 加固（127 守卫、自动重载、timeout 预检等）只在 Debian 13 实机验证过，但表格中 macOS 列也写着"通过"，日期说明也写了"双平台完成验证"。此前对话中关于"macOS 100% 正常运行"的说法同样**没有经过 macOS 实测**，这是审计方此前的表述错误。
- **处理**：本次已修正为"macOS 以 2026-10-19 基线为准，10-26 加固项待复测"。从配置本身分析，macOS 路径（`pbcopy`、无 X11、`if-shell infocmp`）风险较低，但仍需实机确认。

#### M-3 远程测试流程的凭据与主机校验
- **现状**：调试期间 SSH 密码以明文出现在对话中，并临时写入本机 `askpass.bat`（每次用后已删除）；SSH 使用 `StrictHostKeyChecking=no` 与 `UserKnownHostsFile=NUL`，不校验主机指纹。
- **影响**：密码已出现在对话记录与本地会话日志中；关闭主机校验存在中间人风险（仅限局域网）。
- **建议**：**修改该账户密码**，改用 SSH 公钥登录（`ssh-copy-id`），恢复主机指纹校验。

### 低风险

#### L-1 `Prefix + r` 重载会累积终端选项【已修复】
- **位置**：[templates/tmux.conf](templates/tmux.conf) L18-L26
- **现状与修复**：原配置中 `set -as` 会在每次 `source-file` 时追加条目。现已在注入扩展前增加 `set -su terminal-overrides` 与 `set -su terminal-features`，实测无论重载多少次，配置项均恒定保持为 3 条与 4 条，已彻底消除累积问题。

#### L-2 "单行在线更新"命令的健壮性
- **位置**：[TMUX_USAGE_GUIDE.md](TMUX_USAGE_GUIDE.md) 第 11 节方式一
- **现状**：`curl ... -o ~/.tmux.conf` 直接覆盖目标文件；下载中途超时可能留下截断的文件。手动替换还会绕过安装器的哈希记录，之后对 `.tmux.conf` 执行 `--rollback` / `--restore-backup` 会因为"安装后已修改"而被拒绝（这是设计上的保护行为）。
- **建议**：先下载到临时文件，校验非空且 `tmux -f 临时文件 -L test start-server` 可解析，再 `mv`；并在文档中说明对回退的影响。

#### L-3 剪贴板管道重复 4 次
- **位置**：[templates/tmux.conf](templates/tmux.conf) L109、L114、L120、L123
- **影响**：同一段 `sh -c` 长命令复制了 4 份，修改时容易漏改（本次加 timeout 预检时就需要同步改 4 处）。
- **建议**：抽成 `~/.tmux/clipboard-copy.sh`，或用 tmux 3.2+ 的 `%hidden` 变量统一定义。

#### L-4 tmux 配置没有自动化测试
- **现状**：两个回归套件都不加载 `tmux.conf`，tmux 行为只靠人工实机验证。
- **建议**：在 CI 中增加一步：安装 tmux，使用隔离 socket `tmux -L ci -f /dev/null start-server \; source-file templates/tmux.conf`，并断言无报错输出。

### 信息

- **I-1 ShellCheck**：0 error；5 个 SC2034 都在 `scripts/test_installer.sh`（`FAMILY`、`DRY_RUN`、`WITH_TMUX`、`P10K_STYLE`、`SCRIPT_DIR`），这些变量由 `eval` 载入的被测函数使用，属于误报，可加 `# shellcheck disable=SC2034` 注释。
- **I-2 CI 覆盖面**：[tests.yml](.github/workflows/tests.yml) 覆盖 5 个 Linux 镜像，并包含真实安装与幂等性测试，覆盖较好；缺少 ShellCheck 步骤和 macOS runner（`macos-latest`）。
- **I-3 本地敏感文件**：`.zhistory`、`.zsh_history`、`*.before-fix` 已在 `.gitignore` 中、未被跟踪；其中 `.zhistory` 含远程主机与用户名，提交或打包分发项目目录时注意排除。

---

## 四、建议处理顺序

1. 修改远程账户密码并改用公钥登录（M-3）
2. 在 macOS 上复测 tmux 加固项后更新验收表（M-2）
3. 修复 L-1（改动 2 行）并增加 CI 中的 tmux 加载测试（L-4）
4. 为提供校验文件的 Release 下载增加 SHA-256 比对，vfox 脚本固定版本（M-1）
5. 改进单行更新命令、抽取剪贴板脚本（L-2、L-3）
