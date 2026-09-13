# 测试与验收

本文维护可复现的测试入口、结果边界和目标机验收方法。首次安装见[安装指南](LINUX_ZSH_SETUP_GUIDE.md)，管理命令见[配置管理](CONFIGURATION_MANAGEMENT.md)。

## 最近一次本地验证

日期：2026-09-13。基于提交 `b889723` 的工作区，包含本轮中文注释和文档编辑。环境为 Windows 下的 Bash 5.2.37（版本输出目标为 `x86_64-pc-cygwin`）；当前无可用 Zsh 命令。

| 检查 | 本次结果 | 解释 |
| --- | --- | --- |
| 六个正式 Bash 脚本语法 | 通过 | 解析检查，不执行安装 |
| 六份 Markdown 文档检查 | 通过 | 34 个本地链接有效、43 段 Bash 示例语法通过、代码围栏配对；外部资料仅针对引用的关键事实核查 |
| `bash scripts/test_installer.sh` | 退出码 0，可运行用例通过 | 原生悬空符号链接切换、Zsh 运行用例跳过 |
| `bash scripts/test_management.sh` | 退出码 0，可运行用例通过 | Zsh 开关、扩展顺序、分段诊断及 Linux PTY 用例未验证 |
| Linux / macOS 实际安装 | 未执行 | 不从模拟结果推断安装成功 |
| 当前版本远端 CI | 本轮未查询或触发 | 工作流存在不等于当前代码已通过 |
| 终端交互、tmux 剪贴板、实际 Release 下载 | 本轮未执行 | 需要目标机验证 |

本次测试现场保留在 Bash 的 `/tmp/zsh-installer-tests.8oiwnWCN` 和 `/tmp/zsh-management-tests.qH5kSme6`。这些是当前测试环境的临时路径，不是需要部署的仓库资源。

测试中故意制造的拒绝覆盖、非法参数和失败下载会输出“错误”或 `FAIL: lazydocker`，随后应由测试断言确认预期失败。判断套件结果要同时看最终退出码、完成标记和 SKIP，不能只搜索日志中的一个单词。

## 第一层：静态语法检查

在项目根目录、Bash 环境执行：

```bash
bash -n install.sh
bash -n scripts/check_updates.sh
bash -n scripts/manage.sh
bash -n scripts/retry_tools.sh
bash -n scripts/test_installer.sh
bash -n scripts/test_management.sh
```

存在 Zsh 的目标机另行执行：

```bash
zsh -n templates/zshrc.zsh
zsh -n .zshrc
zsh -n .zshenv
```

每条命令须检查退出码。`zsh -n` 只检查语法，不验证命令存在、运行副作用、网络、插件版本或终端协议。tmux 配置不是 Bash/Zsh 脚本，不能用 `bash -n` 验证；加载它会执行 run-shell/TPM 命令，应在隔离环境或明确准备好的目标会话中测试。

## 第二层：隔离回归

```bash
bash scripts/test_installer.sh
bash scripts/test_management.sh
```

套件创建临时 HOME、状态目录及命令替身，不执行真实软件安装。退出后打印并保留目录；它们不覆盖真实用户配置。现有 `scratch/` 是历史审计材料，当前回归入口仍是 `scripts/test_*.sh`。

### 安装器套件覆盖

- 普通预演、更新预演和缺少模板时的预演，不调用联网/提权替身或写状态。
- Neovim 无效二进制拒绝、目录切换失败恢复、成功切换保留旧版；部分用例要求原生链接能力。
- 主题预设暂存、向导不提前删除个人主题、主题回退和后续修改保护。
- 最终选项收集后的 tmux 目标类型检查。
- 离线更新不覆盖旧清单。
- 有 Zsh 时验证模板语法、检查命令路径和关闭开关后不激活工具。

### 管理套件覆盖

- 管理入口预演的分发和不写状态。
- 停用/恢复、重复停用、字节码退役、停用期间的覆盖保护。
- 停用时拦截安装回退。
- 布尔选项编辑保留其它内容且不执行选项中的代码。
- 备份列表、差异、范围恢复及原本不存在文件的恢复。
- 指定组件重试、非法组件拒绝、保留无关失败项与配置。
- 有 Zsh 时验证开关、用户扩展先于高亮加载、手动启动诊断。
- Linux 有 util-linux `script` 时补充控制终端下的诊断回归。

以上测试使用本地桩，不能验证上游 Release 资产名称是否存在、软件包是否兼容、第三方安装脚本行为或真实主题效果。

### GitHub Actions

[工作流](.github/workflows/tests.yml) 在 push、pull_request 和手动触发时配置以下容器：Debian 12、Debian 13、Ubuntu 24.04、Fedora latest、Arch latest。各容器先联网安装测试依赖，再运行两套隔离回归。

Fedora/Arch 镜像标签会变化，不能仅凭发行版名称复现历史环境；记录对应提交、运行链接和版本输出。矩阵没有 macOS、Windows 或单独的 ARM runner，也没有覆盖所有安装器识别的衍生发行版。

## 第三层：目标机预演

在普通用户的 Linux 或 macOS 终端中，从完整项目运行：

```bash
bash install.sh --dry-run --profile basic --p10k-style skip --lang zh
bash install.sh --dry-run --check-updates --lang zh
bash install.sh --dry-run --update --lang zh
bash install.sh --disable --dry-run
```

预期只输出计划。预演会提前退出，因此不能作为包管理器适配、ZDOTDIR、已有配置目标或网络可用性的验证。回退预演也不验证备份内容。

## 第四层：受控安装与新会话

先检查当前配置和备份策略，保留可用会话。需要真实安装时选择一套方案，例如：

```bash
bash install.sh --profile full --p10k-style skip --lang zh
```

这会实际安装软件、联网并替换受管配置。已有组件是否启用以最终计划为准；记录安装备份目录。不需要改变登录 Shell 时在相应提示回答 N。

在新开 Zsh 中按需验证：

| 项目 | 验证方法 |
| --- | --- |
| 语法与加载 | `zsh -n ~/.zshrc`，观察新会话 stderr 和工具状态 |
| 主题、补全、自动建议 | Tab 路径补全；输入已有命令前缀，在行尾按右键接受建议 |
| 高亮 | 输入存在和不存在的命令，观察颜色差异 |
| FZF | Ctrl+R、Ctrl+T、Alt+C；检查预览和目录切换 |
| 共享历史 | 两个同用户会话搜索独特 echo 标记，同时检查 `fc -l` |
| Yazi / zoxide | `y` 退出目录联动；访问目录后 `z` 跳转 |
| lazygit / lazydocker | 先查看版本，再按需要打开界面，不为验收执行删除或提交 |
| 开关 | `--set banner=0` 后新会话检查；记录并恢复原值 |
| 诊断 | `--doctor`、`--profile-startup`；后者会真实执行配置 |
| tmux | 分屏、复制模式、复制到外层终端及缓冲区粘贴；记录终端和 tmux 版本 |
| 更新检测 | 手动检查会联网和写缓存；失败应保留旧清单 |

停用/恢复和回退先在隔离测试验证；需要在真实配置中尝试时，先查看差异并记录当前状态。不要为了验收故意损坏真实配置或关闭最后一个可用会话。

## 验收记录模板

提交问题或记录验证结果时填写：

```text
日期与项目提交：
系统版本与架构：
Bash / Zsh / tmux 版本：
终端客户端与连接方式：
使用安装模板还是根目录参考配置：
安装参数、启用开关：
执行的命令与退出码：
通过项目：
失败现象及对应日志：
跳过项目与原因：
备份位置：
```

历史 Debian 13 / Zsh 5.9 的交互验证摘要保留在[故障排查](ZSH_TROUBLESHOOTING.md)。旧版本结果仅用于定位演变，不能替代本次提交的运行验证。
