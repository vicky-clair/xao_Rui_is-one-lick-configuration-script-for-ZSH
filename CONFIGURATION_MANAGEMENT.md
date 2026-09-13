# Zsh 配置管理

核对日期：2026-09-13。本文描述安装器部署的 `templates/zshrc.zsh`；根目录 `.zshrc` 的部分工具不受同样的开关控制，差异见[开发文档](DEVELOPMENT.md)。首次部署见[安装指南](LINUX_ZSH_SETUP_GUIDE.md)。

在完整项目目录中运行下列命令。涉及配置写入或组件安装时会询问确认。加 `--dry-run` 仅展示操作，不写文件、不联网、不执行用户配置。`--yes` 可显式跳过管理操作的确认，不适用于普通安装流程。

## 停用与恢复

```bash
bash install.sh --disable
bash install.sh --enable
```

停用将带有项目标识的 `.zshrc` 备份后替换为注释占位文件；恢复取回停用前的文件。新会话生效，保留插件、应用、tmux 配置、`.zshenv` 和默认登录 Shell。停用不撤销 `.zshenv` 或系统全局配置中的行为。

重复停用不生成新备份。停用期间若修改了 `.zshrc`，恢复会拒绝覆盖，请先比较备份。停用状态下重新安装或回退会被阻止，需先恢复。停用后 `zsh-config` 不会在新会话加载，请使用项目里的 Bash 命令。

## 体检与启动性能

```bash
bash install.sh --doctor
bash install.sh --profile-startup
```

体检检查配置语法、OMZ/主题/核心插件文件、PATH、工具版本、布尔开关及钩子声明；不加载用户配置，不联网，不自动修复。版本查询仅在有 `timeout` 或 `gtimeout` 时执行，每项最多约 3 秒。缺少可选工具仅作提示，发现需检查的问题返回非零。钩子声明不等于当前会话状态，可在原 Zsh 中用 `typeset -p chpwd_functions precmd_functions` 查看。

性能诊断需要 Zsh 与 `timeout`/`gtimeout`。确认后真实执行一次 `.zshrc`，再切换到 HOME 触发目录钩子；总超时约 32 秒。新版模板按 OMZ、主题、vfox、FZF、zoxide、Fastfetch、用户扩展与高亮输出阶段耗时，再输出 `zprof` 函数统计。诊断关闭项目后台更新检测，但用户扩展或插件仍可能写缓存、联网或执行其它初始化。旧模板只有 `zprof`，没有新增阶段标记。普通终端启动不输出诊断明细。

诊断子 Shell 保留交互模式，但关闭作业控制、使用空标准输入，避免在 `timeout` 的进程组中争抢前台终端。它不用于交互输入测试；超时或启动失败会打印退出码。

## 功能开关

```bash
bash install.sh --configure
bash install.sh --set banner=0
bash install.sh --set fastfetch=0
bash install.sh --set timer=0
bash install.sh --set auto-update=0
```

菜单显示选项，每次输入一项 `名称=0` 或 `名称=1`，回车取消。设置写入 `~/.zsh-project-options`，先备份再替换；管理器不执行此文件中的代码，并保留其它内容。

| 名称 | 作用 | 未设置时 |
| --- | --- | --- |
| `full` | FZF、Yazi、eza、zoxide、Neovim 等完整工具集成 | 关闭 |
| `vfox` | vfox 激活 | 关闭 |
| `lazydocker` | lazydocker 别名 | 开启（检测到命令时生效） |
| `lazygit` | lazygit 别名与 Ctrl+G 快捷键 | 开启（检测到命令时生效） |
| `tmux` | tmux 别名 | 关闭 |
| `banner` | 启动横幅与成功信息；错误及更新提示仍显示 | 开启 |
| `fastfetch` | 启动时显示系统信息，同时要求 `full=1` | 开启 |
| `timer` | 横幅中的启动计时，同时要求 `banner=1` | 开启 |
| `auto-update` | 周期性后台版本检测；已有缓存提示仍可显示 | 开启 |

开关不安装或卸载软件；`tmux=0` 不修改 `.tmux.conf`。更改后新开终端验证，不根据旧会话残留的别名判断。横幅、Fastfetch、计时开关以及下述扩展和快捷命令需要新版 `templates/zshrc.zsh`。旧安装仅更新项目源码不会自动替换家目录中的模板；普通 `--update` 也不重新部署模板。使用安装器重新部署时会备份配置，并按安装选项重写选项文件。

新版模板安装后支持快捷命令：

```zsh
zsh-config                    # 配置菜单
zsh-config --doctor
zsh-config --set banner=0
```

## 用户扩展

将个人别名和按键设置放入 `~/.zshrc.local`，可参考 `templates/zshrc.local.example`。它在主配置之后、语法高亮之前加载，安装器不会创建或覆盖这个文件。它不属于自动备份恢复范围，请自行保存。影响工具初始化的开关应使用管理命令，放在 `.zshrc.local` 中对本次启动已太晚。

## 仅重试失败组件

```bash
bash install.sh --retry-failed
bash install.sh --retry-failed lazydocker
bash install.sh --retry-failed lazygit
```

新安装将未完成的可选包写入状态目录的 `failed-components`。不带名称时重试清单；旧安装没有清单时可指定组件。支持 fzf、fd/fd-find、bat/batcat、eza、zoxide、yazi、neovim/nvim、fastfetch、vfox、lazydocker、lazygit、tmux、xclip、wl-clipboard/wl-copy、ncurses-term。

重试先检查命令是否已在 PATH，否则调用系统包管理器安装。lazydocker 与 lazygit 额外支持官方 Release 下载回退，按版本号拼接资产名。其余工具在仓库无包时仍会失败并保留记录；此入口不保证升级到特定版本，不重部署配置、主题或 SDK，也不配置 Docker。成功后仅移除对应失败项，其余失败保留。日志位于状态目录的 `retry-XXXXXXXX/组件.log`。

## 备份查看与按范围恢复

```bash
bash install.sh --list-backups
bash install.sh --diff-backup /实际备份目录 --scope zsh
bash install.sh --restore-backup /实际备份目录 --scope zsh
```

范围为 `zsh`（默认：`.zshrc`、`.zsh-project-options`、`.p10k.zsh`）、`tmux`（仅 `.tmux.conf`）或 `all`。只处理备份中记录的文件。列表显示目录时间与文件原状态；差异显示“备份原内容 → 当前内容”。恢复先显示差异、验证 HOME 和操作后校验值，再询问确认，并备份当前文件。若文件后来被修改则拒绝覆盖，没有强制覆盖开关。

状态目录默认为 `~/.local/state/zsh-project`，设置 `XDG_STATE_HOME` 时改用其下的 `zsh-project`。`install-*` 为安装备份，`manage-*` 为管理快照；`.state` 记录原文件是否存在，`.sha256` 记录该操作结束后内容的校验值。过期 `.zwc` 会移入管理快照，恢复后重新读取源文件。

`--rollback DIR` 适用于安装器生成的完整安装备份，不应指向只保存单个开关的管理快照。它不创建新的恢复前快照；`--restore-backup DIR` 会先备份当前受管文件，并支持上述范围筛选。两者都不卸载软件或还原插件版本。安装中断时可能尚未生成完整哈希，此时不要手工伪造哈希绕过保护，应比较原文件和当前文件后恢复。

管理器拒绝链接或目录形式的受管文件，暂不管理自定义 `ZDOTDIR`。磁盘故障或强制终止时，多文件恢复可能只完成一部分，快照保留供检查。遇到残留 `manage.lock` 或 `retry.lock`，先确认没有操作正在运行再处理，不要并发执行安装、恢复和重试。

## 更新检测、脚本副本与语言

```bash
bash install.sh --check-updates
bash scripts/check_updates.sh --timeout 15 --lang zh
bash install.sh --update --lang zh
```

前两条只检测，但会联网、执行 Git fetch 和写缓存；第三条检测后交互升级第三方组件。Linux 系统包需要用相应包管理器另行更新，`--update` 不部署模板，也不创建安装备份。

`--timeout 15` 只改变这一次独立检测；随后 `--update` 会再次以默认参数检测。`zsh-check-updates` 和 `zsh-update` 当前不会转发额外参数，所以不要用 `zsh-check-updates -t 15` 调整超时。

默认在新会话检查是否距离 `last_update_check` 超过 7 天，再启动后台进程。该文件也可能记录一次失败检查的发起时间，不是可靠的最后成功时间；失败后可以手动检测。`auto-update=0` 只停止周期性检测，旧缓存仍会展示。

`zsh-config` 和检查命令优先使用状态目录 `scripts/` 中的安装副本，缺失时才尝试项目目录。仅在仓库 `git pull` 不会刷新这些副本。需要确认当前行为时可从完整仓库直接调用相应脚本；重新安装会复制新版脚本，但也会重新生成选项，详见 [README](README.md)。找不到完整安装器时，`zsh-update` 可能退化为只执行检测。

管理脚本接受 `--lang` 参数以兼容入口转发，但当前管理提示主要是中文，并未实现完整双语界面。非交互执行写操作需显式 `--yes`；在只有文本替换的操作中它跳过确认，不代表脚本会自动满足缺少的依赖。

## 使用边界

- 管理器读取选项时不执行代码，但真实 Zsh 启动会 source `~/.zsh-project-options`；不要将不可信脚本内容放入其中。
- 重试入口的发行版识别比安装器窄，DNF 分支没有 YUM 回退，部分衍生系统可能需手动安装。
- `failed-components` 只保存跳过的可选包，不包含完整插件健康状态，也不一定记录所有下载或运行失败。
- `--doctor` 不 source 配置，但会执行本机工具的 `--version`；它也不会验证所有按键、TPM 插件、Docker 连接或 SDK 切换。
- `--profile-startup` 会真正执行配置和目录钩子，输出的诊断阶段只适用于相应模板，不代表完整终端连接耗时。
- 主安装器、管理和重试没有统一互斥锁，应顺序运行。状态路径变更后旧备份不会自动迁移。

## 验证

```bash
bash scripts/test_installer.sh
bash scripts/test_management.sh
```

测试使用临时 HOME 和本地桩，不做真实安装，保留测试目录便于排查。GitHub Actions 配置覆盖 Debian 12/13、Ubuntu 24.04、Fedora、Arch 容器；写入配置不代表这些平台已经通过。当前验证结果和跳过项见[测试与验收](INSTALLER_TESTING.md)。
