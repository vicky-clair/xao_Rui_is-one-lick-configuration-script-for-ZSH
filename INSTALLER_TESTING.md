# 安装器审计修复与 Linux 测试

## 配置管理扩展（2026-09-07）

后续用户 Linux 实测：安装器回归包含 Zsh 与 Neovim 符号链接切换全部通过；管理回归通过配置与重试用例，但启动诊断失败且两个日志为空。旧版提交 `458a6b1` 的 Linux CI 已成功，但没有覆盖控制终端场景。现修正诊断启动参数：保留交互模式，关闭作业控制并使用空标准输入；失败时打印退出码。新增 Linux PTY 回归覆盖 SSH/终端场景，此修复仍需 Linux 重跑确认。

新增功能见 [配置管理指南](CONFIGURATION_MANAGEMENT.md)。除原安装器回归外，现在还需执行 `bash scripts/test_management.sh`。

本轮在 Windows 的 Bash 环境通过两套脚本中可运行的隔离用例：管理预演、停用与重复停用、恢复修改保护、停用状态回退拦截、选项编辑不执行代码、范围恢复、缺失原文件恢复与字节码退出、备份差异与列表、指定组件重试和非法参数拒绝。测试在 MSYS/Cygwin 优先使用 Unix 工具路径，避免误调用 Windows `find.exe`。

当前机器没有 Zsh，也没有可用 WSL 发行版。Zsh 运行用例（新开关、用户扩展加载顺序、性能阶段统计）与 Neovim 原生链接切换明确标记 SKIP，尚未验证。已添加 Debian 12/13、Ubuntu 24.04、Fedora、Arch 的 GitHub Actions 测试矩阵，尚未触发远端 CI。没有执行真实安装、部署到用户 Linux、运行 macOS 测试或推送代码。

本次修复仅修改项目文件，没有在用户 Debian 上执行安装或部署。

## 已修复问题

1. `--dry-run` 在交互、更新、自举下载之前统一退出，不联网、不写缓存、不调用 sudo。
2. `.p10k.zsh` 随主题选项加入受管文件，统一备份和回退；skip 保留原主题。向导完成后重新记录文件校验值。
3. tmux 和主题的目标类型检查移至交互选择后；目录和符号链接目标会被拒绝。
4. `zsh-check-updates` 在每次调用时定位检查脚本，不依赖已清理的启动临时变量。
5. `ZSH_PROJECT_FULL`、`ZSH_PROJECT_VFOX`、`ZSH_PROJECT_LAZYDOCKER`、`ZSH_PROJECT_TMUX` 控制新模板的工具激活。开关关闭不会卸载已安装软件。
6. Neovim 新目录验证成功后才切换，保留旧目录和链接；切换失败尝试恢复旧路径。没有自动删除旧版本备份。
7. 更新失败、跳过或 Linux 软件包待手动更新时保留提示；重新检测成功且无待处理项目时才报告完成。断网或部分检测失败不覆盖旧缓存。

## 第一轮：先做隔离回归

将更新后的完整项目传到 Linux，进入项目目录，执行：

```bash
bash scripts/test_installer.sh
```

脚本创建独立临时 HOME，用本地桩代替联网命令；不安装软件、不调用真实 sudo、不修改实际用户配置。临时目录会保留并在末尾打印，方便检查。

覆盖预演各入口、缺失模板预演、Neovim 无效二进制和切换失败、主题回退与修改保护、tmux 目标检查、离线更新缓存。若本机有 Zsh，还检查模板语法、更新命令路径和关闭功能开关后的行为。

Windows 缺少 Zsh 或原生符号链接能力时会明确 SKIP；Linux 应尽量完成全部测试。任何 FAIL 都先停止，不运行真实安装。

## 第二轮：真实用户下预演

```bash
bash install.sh --dry-run --profile basic --p10k-style skip --lang zh
bash install.sh --dry-run --check-updates --lang zh
bash install.sh --dry-run --update --lang zh
```

预期只有计划输出，不弹出密码提示、不下载、不显示“正在更新”。`--dry-run --rollback 路径` 也只展示计划，不验证备份内容。

## 第三轮：受控安装

保留当前可用 SSH 会话。若要验证完整环境，用：

```bash
bash install.sh --profile full --p10k-style skip --lang zh
```

注意：这是实际安装，会安装或升级所选软件。已有工具正常时不用为测试重新安装。首次建议选 skip 保留个人主题；vfox、lazydocker、tmux 按需求选择。vfox 开启后模板仍会禁用自动目录钩子，这是当前的已知行为。

安装前显示最终计划，确认后才继续。记录输出的备份目录。不需要修改默认登录 Shell 时回答 N。不要关闭最后一个可用会话。

## 第四轮：新会话验证

在新 SSH 会话执行：

```zsh
zsh -n ~/.zshrc
cat ~/.zsh-project-options
whence -v _zsh_autosuggest_start _zsh_highlight
zsh-check-updates
```

检查更新会联网并更新缓存；断网时应提示未完成，不应说所有组件都是最新。再按 README 的表格测试补全、灰色建议、FZF、目录切换及已选工具。

若选择基础模式或未启用某工具，其别名不出现是预期行为。必须通过 `exec zsh` 或新会话验证开关，不能在旧会话里反复 source 后根据残留别名判断。

## 第五轮：回退

先预演，路径替换成安装器打印的真实备份目录：

```bash
bash install.sh --dry-run --rollback /实际备份路径 --lang zh
```

需要实际回退时去掉 `--dry-run`，核对提示并确认。回退恢复此次管理的配置，不卸载软件、不还原插件版本或默认 Shell。如果安装后手动修改了受管文件，回退会拒绝覆盖，需先比较当前文件与备份。

主题恢复、tmux 目录保护和 Neovim 切换失败应首先通过隔离测试验证，不需要故意破坏真实配置或制造磁盘故障。

## 本地验证边界

Linux 首轮回归曾在启动计时处报 `unknown function: int`，而旧测试只检查最后的命令状态，误报了通过。现已将模板和项目 `.zshrc` 改为整数变量转换；测试同时检查 source 返回值、每个断言、标准错误输出和毫秒计时展示。该修复需要在 Linux 重跑确认，不将之前带错误的结果记录为全通过。

Bash 语法和隔离测试已在当前 Windows/MSYS 环境运行：预演各入口、非法 Neovim 二进制保护、主题恢复与修改保护、tmux 目标检查、离线缓存保留均通过。Neovim 原生符号链接切换用例和 Zsh 运行用例标为 SKIP，不算通过。没有运行真实系统包安装，也没有声称 macOS 和所有 Linux 发行版均已验证。
