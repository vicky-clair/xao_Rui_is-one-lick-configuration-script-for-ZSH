# 项目审计报告

审计日期：2026-10-27　｜　审计基线：commit `6155147`（本地 main，领先 `origin/main` 3 个提交，未推送）　｜　上次审计：2026-10-26 / `68cd8ce`
范围：`install.sh`、`scripts/`、`templates/`、根目录配置、`terminal_configs/`、CI 与文档

> [!IMPORTANT]
> 本次新发现的问题中，**有 4 项是 2026-10-27 的两个 tmux 修复提交（`b71792f`、`6155147`）自己带进来的**（N-1、N-2、N-3、N-5）。这两个提交没有推送，建议先修完这些再推送。

---

## 一、结论摘要

| 等级 | 数量 | 说明 |
| --- | --- | --- |
| 严重 / 高 | 0 | 未发现可被直接利用的漏洞，仓库和提交历史中没有密钥 |
| 中 | 5 | 供应链校验（M-1，沿用）、远程凭据（M-3，沿用）、重试流程会被新依赖卡住（N-1）、版本判断有误（N-2）、tmux 配置和安装流程没有任何自动化覆盖（N-4） |
| 低 | 7 | 文档写错依赖（N-3）、锁定版本要改 3 处（N-5）、终端配置没有部署和字体保障（N-6）、PATH 写死（N-7），以及沿用的 L-2、L-3 |
| 信息 | 4 | ShellCheck、CI 覆盖面、本地敏感文件、未推送提交 |
| 已关闭 | 2 | L-1（重载累积）、M-2（macOS 复测，部分完成） |

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
| ShellCheck | — | **未执行**，本机未安装 |

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
| M-1 | 第三方下载缺少 SHA-256 / 签名校验；vfox 回退脚本取 main 分支；TPM 及插件克隆默认分支 HEAD | **未修复**。主题已锁定 tag，但 TPM 和其余 4 个插件仍是 HEAD |
| M-2 | 文档中的 macOS 结论没有验证 | **部分关闭**：今天在 macOS 27 / tmux 3.8 实机验证了安装、状态栏和 doctor。需要同步更新 [INSTALLER_TESTING.md](INSTALLER_TESTING.md) 验收表；Linux 侧本次改动反而还没复测 |
| M-3 | 远程测试 SSH 明文密码，关闭了主机指纹校验 | **未确认**。仍建议改密码并改用公钥登录 |
| L-1 | `Prefix + r` 重载累积选项 | 已关闭。注意 `set -su terminal-features` 现在包在版本判断里，受 N-2 影响 |
| L-2 | 单行在线更新命令可能留下截断文件 | 未修复 |
| L-3 | 剪贴板管道重复 4 次 | 未修复 |
| L-4 | tmux 没有自动化测试 | 升级为 N-4 |

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
