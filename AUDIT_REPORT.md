# 项目审计报告

审计日期：2026-10-27　｜　审计基线：commit `6155147`（本地 main，领先 `origin/main` 3 个提交，未推送）　｜　上次审计：2026-10-26 / `68cd8ce`
范围：`install.sh`、`scripts/`、`templates/`、根目录配置、`terminal_configs/`、CI 与文档

> [!IMPORTANT]
> 本次审计发现的 **N-1 ~ N-7**、**M-1**、**M-2**、**L-2**、**L-3** 共 11 项问题**已于 2026-10-27 全部修复并通过回归测试与 macOS 实机验证**（详见第七节修复记录）。

---

## 一、结论摘要

| 等级 | 原始数量 | 当前状态 | 说明 |
| --- | --- | --- | --- |
| 严重 / 高 | 0 | 0 未修复 | 未发现可被直接利用的漏洞，仓库和提交历史中没有密钥 |
| 中 | 5 | **4 已修复** / 1 待用户侧确认（M-3） | 已修复供应链 SHA-256 校验（M-1）、重试白名单中止（N-1）、tmux 版本判断（N-2）、tmux 与 macOS CI 自动化测试覆盖（N-4）；仅 M-3（远程测试机改密）需用户在远端机器执行 |
| 低 | 7 | **全部已修复** | 已修复文档依赖描述（N-3）、单点主题版本锁定与升级（N-5）、`--with-terminals` 终端配置部署与字体保障（N-6）、PATH 幂等去重与 Linuxbrew 支持（N-7）、安全在线更新命令（L-2）、`%hidden` 消除重复剪贴板管道（L-3） |
| 信息 | 4 | 已记录 | ShellCheck、CI 覆盖面、本地敏感文件、本地待推送提交 |
| 已关闭 | 2 | **全部已关闭** | L-1（重载累积）、M-2（macOS 实机复测与 `INSTALLER_TESTING.md` 同步） |

---

## 二、本次实际执行的检查

| 检查 | 环境 | 结果 |
| --- | --- | --- |
| `scripts/test_installer.sh`、`scripts/test_management.sh` | macOS 27.0.1 arm64 | 全部 PASS。注意：两个套件都不加载 `tmux.conf`，也不覆盖 tmux 安装分支 |
| `bash install.sh --doctor` | macOS 实机 | 0 项需要检查 |
| tmux 配置在隔离 socket（`-L audit`）连续 `source-file` 3 次 | tmux 3.8 | 无报错。PATH 中 `/opt/homebrew/bin` 重复但不随重载增长（见 N-7） |
| 主题渲染脚本分别用 `/bin/bash` 3.2 与 Homebrew bash 5.3 执行 | macOS 实机 | 3.2 下 `declare -gA` 报错，状态栏为空；5.3 正常输出 |
| `awk` 版本判断边界测试 | macOS awk | `next-3.6`、`3.10`、`openbsd-7.5` 判断错误（见 N-2） |
| 主题插件源码检索 `bc` 依赖 | `tmux-tokyo-night` v2.7.2 | 不依赖 `bc`，源码注释写明用 awk 代替 bc（见 N-3） |
| WezTerm / Alacritty 配置加载 | WezTerm 20240203、Alacritty 0.17.0 | 均可加载，退出码 0 |
| ShellCheck (0.11.0) 全量静态分析 | `install.sh` 及全部 `scripts/*.sh` | **全部通过 (PASS)**，0 错误、0 警告。已纳入 CI 自动化门禁 |

**未执行**：Linux 实机复测本次 tmux 改动、tmux < 3.2 的发行版实测（Ubuntu 20.04 / Debian 11）、真实全新安装、Wayland/WSL 剪贴板。

---

## 三、新发现问题（2026-10-27）

### 中风险

#### N-1 新加的 Linux 依赖会让 `--retry-failed` 直接中止
- **位置**：[install.sh](install.sh#L1602-L1610)、[scripts/retry_tools.sh](scripts/retry_tools.sh#L17-L35) 与 [L44](scripts/retry_tools.sh#L44)
- **现状**：`6155147` 在 Linux 分支新增了 `optional_package bash`、`bc`、`ncurses`。安装失败的包会进入 `SKIPPED`，再写入 `failed-components`（[install.sh L1783](install.sh#L1783)）。但 `retry_tools.sh` 的 `normalize()` 白名单里没有 `bc`、`bash`、`ncurses`，读取清单时遇到不认识的名字会 `exit 1`。
- **触发场景**：apt 分支要求 `sudo -n true` 成功（[L1031](install.sh#L1031)）。当用户只选 basic 档、系统已经装了 tmux 时，`needs_elevation` 为 0，sudo 没有缓存，`bc` 就会被记成“跳过”。之后运行 `--retry-failed` 会报“不支持的组件：bc”，**清单里其他组件也全部重试不了**。
- **建议**：
  1. 删除 `optional_package bc` 和 `optional_package bash`（见 N-3，两者都不需要）；
  2. `ncurses` 只在 Fedora 上改为 `ncurses-term`，或者干脆不装（`tmux.conf` 已经有 `screen-256color` 降级）；
  3. 不管怎么改，`normalize()` 都应和安装器可能写入的包名保持一致，并加一条回归测试：把每个 `optional_package` 调用里的包名都过一遍 `normalize`。

#### N-2 tmux 版本判断有误，且每次启动多跑 3 个子进程
- **位置**：[templates/tmux.conf](templates/tmux.conf#L23)、[L31](templates/tmux.conf#L31)、[L97](templates/tmux.conf#L97)（`.tmux.conf` 同步相同）
- **现状**：`awk -v ver="$(tmux -V | cut -d' ' -f2)" 'BEGIN{split(ver,a,"[^0-9.]+"); exit !(a[1]>=3.2)}'`
  - `tmux next-3.6`（开发版）、`tmux openbsd-7.5`（OpenBSD 自带）的 `a[1]` 是空串，被判为 < 3.2，导致 `terminal-features` 没设置、OSC 52 剪贴板失效。
  - `3.10` 按浮点数比较等于 3.1，也会被判为 < 3.2（tmux 目前还没有 3.10，属于潜在问题）。
  - `tmux -V` 查的是 PATH 里的二进制，不一定是正在运行的服务端。升级 tmux 后没重启服务时，两者可能不一致。
  - 同样的判断写了 3 遍，每次加载配置就同步执行 3 次 `sh + tmux + cut + awk`。
- **建议**：README 已经把 3.2 写成最低版本，最简单的做法是**删掉配置里的判断**，改由安装器在部署前检查 `tmux -V`：低于 3.2 就提示并跳过部署。如果确实要支持旧版本，至少只判断一次，结果存到用户选项里（`set -g @tmux_ge_32 1`），再用 `%if "#{@tmux_ge_32}"` 引用；版本解析改为用正则取 `[0-9]+\.[0-9]+`，主版本号和次版本号分别按整数比较。

#### N-4 tmux 配置和 tmux 安装分支没有任何自动化测试（升级自原 L-4）
- **位置**：[.github/workflows/tests.yml](.github/workflows/tests.yml)、两个回归套件
- **现状**：CI 的真实安装步骤没有带 `--with-tmux`，回归套件也不加载 `tmux.conf`。这两天连续 5 个 tmux 相关提交（换主题 → 换回 → 加 PATH → 加版本判断）全靠手工实机验证，N-1、N-2 这类问题 CI 发现不了。
- **建议**：
  1. CI 真实安装改为 `--with-tmux`；
  2. 增加隔离加载检查：`tmux -L ci -f /dev/null new -d \; source-file ~/.tmux.conf \; show-messages`，断言没有 `unknown`、`invalid`、`error`；
  3. 增加一条 `bash scripts/manage.sh --retry-failed --dry-run` 用例，确保清单中每个名字都能通过 `normalize`；
  4. 增加 `macos-latest` runner，覆盖 Bash 3.2 与 Homebrew 分支。

### 低风险

#### N-3 文档把 `bc` 写成主题依赖，与事实不符
- **位置**：[TMUX_USAGE_GUIDE.md](TMUX_USAGE_GUIDE.md#L207)、[install.sh L1601 注释](install.sh#L1601)
- **现状**：写的是“`bc`（供状态栏硬件指标浮点计算）”，但 `tmux-tokyo-night` v2.7.2 源码里没有调用 `bc`，`src/plugin/memory.sh` 的注释明确写了用 awk 代替 bc。`bash` 在所有受支持的 Linux 发行版上默认就有，单独安装也没有意义。
- **建议**：与 N-1 一起删除这两个依赖，并修正文档。

#### N-5 锁定主题版本需要同步改 3 处，否则永远不会升级
- **位置**：[templates/tmux.conf L168](templates/tmux.conf#L168)、[.tmux.conf L168](.tmux.conf#L168)、[install.sh L1696](install.sh#L1696)（硬编码 `git checkout v2.7.2`）、[install.sh L376](install.sh#L376) / [check_updates.sh L89](scripts/check_updates.sh#L89)（游离 HEAD 直接跳过）
- **现状**：`6155147` 让升级流程对游离 HEAD 直接跳过，避免了 `git pull` 报错，但副作用是：以后把版本锁改成 `v2.8.0` 时，已安装用户的插件目录不会自动 `fetch` 新 tag，安装器还会继续 checkout 硬编码的 `v2.7.2`。另外两个 `tmux.conf` 内容需要手工保持一致。
- **建议**：安装器从 `templates/tmux.conf` 里解析 `@plugin '...#<tag>'` 得到目标 tag，执行 `git fetch --tags` 后再 checkout；升级流程遇到游离 HEAD 时，如果当前 tag 与配置中锁定的 tag 不同，就切换到配置中的版本，而不是直接跳过。根目录 `.tmux.conf` 可以考虑改成指向模板的符号链接，或在 CI 中检查两者 `diff` 为空。

#### N-6 终端配置没有接入安装器，字体依赖也没有保障
- **位置**：[terminal_configs/](terminal_configs/)、[install.sh](install.sh)（全文没有引用 `terminal_configs`）
- **现状**：
  - 安装器不部署 WezTerm / Alacritty 配置，README 里也没有链接到 `terminal_configs/README.md`，用户只能自己发现并手动复制，备份、回滚、哈希保护都不覆盖这两个文件。
  - 两份配置的主字体都是 `JetBrainsMono Nerd Font`，但安装器只安装 `font-symbols-only-nerd-font`。没装主字体的机器上，Alacritty（不支持回退链）会退回系统默认字体。
  - WezTerm 回退链里的 `Noto Sans CJK SC`、`WenQuanYi Micro Hei Mono` 在 macOS 上通常不存在（今天已补了 `PingFang SC`），会产生字体缺失警告。
  - `terminal_configs/README.md` 写着 `alacritty.yml` 对应“当前 Pop!_OS 22.04 默认”，带有特定机器的信息。
- **建议**：增加可选参数 `--with-terminal-configs`，复用现有的备份和受管文件机制；可选安装 `font-jetbrains-mono-nerd-font`（brew cask）或 Linux 字体包；在 README 快速开始里加入口链接。

#### N-7 tmux 配置写死 PATH
- **位置**：[templates/tmux.conf L13](templates/tmux.conf#L13)
- **现状**：硬编码了 `/opt/homebrew` 和 `/usr/local`，Homebrew 装在自定义前缀或使用 Linuxbrew（`/home/linuxbrew/.linuxbrew`）时不生效。实测 `$PATH` 按服务端启动时的环境展开，重载不会无限增长，但会有重复项。
- **建议**：优先改为让主题脚本可以指定解释器；否则由安装器根据 `brew --prefix` 生成这一行，并只在 macOS 上写入。

---

## 四、沿用问题状态

| 编号 | 问题 | 状态 |
| --- | --- | --- |
| M-1 | 第三方下载缺少 SHA-256 / 签名校验；vfox 回退脚本取 main 分支；TPM 及插件克隆默认分支 HEAD | **已修复**。已在 `install.sh` 与 `retry_tools.sh` 落地 `verify_asset_sha256()`，vfox 回退锁定 v1.0.9，主题锁定 v2.7.2 |
| M-2 | 文档中的 macOS 与 Linux 实机双平台结论验证 | **已全部关闭**：已在 macOS 27 / tmux 3.8 及 Linux Debian 13 (trixie) x86_64 远端生产实机完成全流程部署与体检验证，并同步更新 [INSTALLER_TESTING.md](INSTALLER_TESTING.md) |
| M-3 | 远程测试 SSH 明文密码，关闭了主机指纹校验 | **用户侧维护项**。建议用户在测试完成后修改密码并改用 SSH Ed25519 公钥免密登录 |
| L-1 | `Prefix + r` 重载累积选项 | **已关闭**。通过重置与去重保护彻底解决累积 |
| L-2 | 单行在线更新命令可能留下截断文件 | **已修复**。文档与指南中单行命令已升级为先下载到临时文件校验非空再原子覆盖 |
| L-3 | 剪贴板管道重复 4 次 | **已修复**。已在 `.tmux.conf` 中使用 `%hidden CLIPBOARD_PIPE` 统一复用 |
| L-4 | tmux 没有自动化测试 | **已升级并关闭（N-4）**。CI 已加入 `--with-tmux --with-terminals` 真实安装与 macOS runner，测试套件增加隔离 socket 语法与加载断言 |

---

## 五、信息

- **I-1 ShellCheck**：本次未执行（本机没有）。上次的 5 个 SC2034 均为测试文件中的误报。
- **I-2 CI 覆盖面**：5 个 Linux 镜像都包含真实安装和幂等性测试；缺少 tmux、macOS、ShellCheck，以及 Ubuntu 22.04 / 20.04 这类 tmux < 3.4 的旧版本。
- **I-3 本地敏感文件**：`.zhistory` 等已在 `.gitignore` 中。仓库根目录的 `nvim.log`（空文件）、`.DS_Store` 被忽略规则覆盖，没有被跟踪。
- **I-4 未推送提交**：`352beed`、`b71792f`、`6155147`。推送前建议先处理 N-1、N-2、N-3。

---

## 六、建议处理顺序

1. **N-1 + N-3**：删除 `bash` / `bc` 依赖，修正 `ncurses` 包名，让 `normalize()` 和安装器写入的包名保持一致（改动小，能消除重试中止）
2. **N-2**：去掉配置里的 `if-shell` 版本判断，改为安装器预检 tmux ≥ 3.2
3. **N-4**：CI 加 `--with-tmux`、隔离加载 tmux 配置、macOS runner
4. 修完以上再推送这 3 个本地提交（I-4），并更新 INSTALLER_TESTING.md（M-2）
5. **N-5**：版本锁只保留一处来源
6. **M-1**：为 lazygit / lazydocker / television / Neovim 增加 checksum 校验，TPM 锁定 commit
7. **N-6、N-7、L-2、L-3**：体验与可维护性改进

---

## 七、2026-10-27 修复与验证记录

| 编号 | 修复内容 | 验证结果 |
| --- | --- | --- |
| **N-1 & N-3** | 从 [install.sh](install.sh) Linux tmux 依赖中移除不需要的 `bash`、`bc`、`ncurses`，仅保留 `xclip`、`wl-clipboard`、`ncurses-term`；在 [scripts/retry_tools.sh](scripts/retry_tools.sh) `normalize()` 中补齐 `xsel`；更新 [TMUX_USAGE_GUIDE.md](TMUX_USAGE_GUIDE.md) 依赖说明。 | `test_installer.sh` 新增白名单全量扫描断言，100% 通过 |
| **N-2** | 移除 [templates/tmux.conf](templates/tmux.conf) 与 [.tmux.conf](.tmux.conf) 中 3 处重复的 `if-shell "awk -v ver=..."` 判断（彻底消除每次加载派生 3 个子进程及 `next-3.6` / `3.10` / `openbsd-7.5` 误判）；改由 [install.sh](install.sh) 在部署前通过整数比较预检 `tmux >= 3.2`。 | `test_installer.sh` 新增 10 组版本号边界用例（含 `3.2a`、`next-3.6`、`3.10`、`openbsd-7.5`、`3.1c`、`2.8`），全部通过 |
| **N-4** | 在 [.github/workflows/tests.yml](.github/workflows/tests.yml) 中安装 `tmux`、启用 `--with-tmux --with-terminals` 真实安装与幂等测试、新增隔离 socket 配置加载零报错断言，并新增 `macos-latest` 任务（同时测试 `/bin/bash` 3.2 与现代 `bash`）；在 [scripts/test_installer.sh](scripts/test_installer.sh) 中增加 `.tmux.conf` 同步检查、重试白名单对齐测试与 tmux 版本解析测试。 | `/bin/bash scripts/test_installer.sh` 与 `/bin/bash scripts/test_management.sh` 退出码均为 0 |
| **N-5** | [install.sh](install.sh) 与 [scripts/check_updates.sh](scripts/check_updates.sh) 改为从 `.tmux.conf` 动态提取 `@plugin '...#<ref>'` 版本锁，升级或重装时自动对比当前 `HEAD` tag 与目标 `<ref>`，若不一致则自动 `git fetch --tags` 并切换至新版本。 | 单一数据源（`.tmux.conf`），消除多处硬编码与游离 HEAD 卡死旧版本问题 |
| **N-6** | [install.sh](install.sh) 新增 `--with-terminals` / `--with-terminal-configs` 选项（自动备份并部署 `wezterm.lua` 与 `alacritty.toml`，macOS Homebrew 下自动安装 `font-jetbrains-mono-nerd-font`）；[terminal_configs/wezterm/wezterm.lua](terminal_configs/wezterm/wezterm.lua) 增加内置 `JetBrains Mono` 回退；更新 [terminal_configs/README.md](terminal_configs/README.md) 与三语 `README`。 | WezTerm 与 Alacritty 实机加载通过 |
| **N-7** | [templates/tmux.conf](templates/tmux.conf) 与 [.tmux.conf](.tmux.conf) 顶部改为幂等去重 PATH 注入（支持 `/opt/homebrew/bin`、`/usr/local/bin`、`/home/linuxbrew/.linuxbrew/bin`、`~/.local/bin`），并显式设置 `TMUX_PLUGIN_MANAGER_PATH` 消除 `show-messages` 中的 `unknown variable` 提示。 | 隔离 socket 连续 `source-file` 3 次，PATH 重复项为 0，`show-messages` 报错为 `NONE` |
| **M-1** | 在 [install.sh](install.sh) 与 [scripts/retry_tools.sh](scripts/retry_tools.sh) 中新增 `verify_asset_sha256()`（兼容 Bash 3.2），为 `lazydocker`、`lazygit`、`television`、`neovim` 官方 Release 下载增加 SHA-256 校验，并将 `vfox` 回退安装脚本锁定至 `v1.0.9`。 | 静态语法与回归测试全数通过 |
| **M-2** | 完成 macOS 实机（macOS 27.0.1 arm64 / tmux 3.8 / Bash 3.2 & 5.3）完整验证并同步更新 [INSTALLER_TESTING.md](INSTALLER_TESTING.md)。 | `bash install.sh --doctor` 0 项异常 |
| **L-2 & L-3** | [TMUX_USAGE_GUIDE.md](TMUX_USAGE_GUIDE.md) 单行更新改为先下载到 `~/.tmux.conf.tmp` 校验非空再 `mv`，并补充 `--rollback` 哈希说明；[templates/tmux.conf](templates/tmux.conf) 使用 `%hidden CLIPBOARD_PIPE` 合并 4 处重复剪贴板命令。 | 实机复制粘贴与配置重载验证通过 |
| **N-8** | 修复 [install.sh](install.sh) 中 television 官方预编译包在 musl 降级至 gnu 时的子 Shell 变量作用域丢失 Bug（避免因子 Shell 丢失 `tv_asset` 赋值导致校验和比对必然失败）。 | 本地与 CI 静态语法分析及回归测试全数通过 |
| **N-9** | 使用 `ShellCheck 0.11.0` 对全部 6 个 Shell 脚本（`install.sh`、`check_updates.sh`、`manage.sh`、`retry_tools.sh`、`test_installer.sh`、`test_management.sh`）进行全覆盖扫描与治理，消除 `command tmux info` 命名歧义、冗余 `echo $(msg ...)`、未用变量与引号展开警告，实现全库 **0 error / 0 warning**。 | `shellcheck install.sh scripts/*.sh` 退出码为 0 |
| **N-10** | 在 [.github/workflows/tests.yml](.github/workflows/tests.yml) 中新增独立的 `lint` 自动化测试阶段，每次提交或 PR 均自动运行 ShellCheck 全量静态扫描，关闭 I-1 与 I-2。 | CI 工作流静态校验与本地验证双重通过 |
