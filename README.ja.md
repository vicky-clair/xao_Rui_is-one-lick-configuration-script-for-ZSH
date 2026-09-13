<div align="center">

# Zsh Configuration Manager

**自分好みのターミナルを、管理しやすい設定で。**

Oh My Zsh · Powerlevel10k · 高度な補完 · 追加の CLI ツール

[![シェル回帰テスト](https://github.com/vicky-clair/xao_Rui_is-one-lick-configuration-script-for-ZSH/actions/workflows/tests.yml/badge.svg)](https://github.com/vicky-clair/xao_Rui_is-one-lick-configuration-script-for-ZSH/actions/workflows/tests.yml)
![対象プラットフォーム: Linux と macOS](https://img.shields.io/badge/target-Linux%20%7C%20macOS-89b4fa?style=flat-square)
![シェル: Zsh](https://img.shields.io/badge/shell-Zsh-cba6f7?style=flat-square)

[English](README.md) · [简体中文](README.zh-CN.md) · **日本語**

[プレビュー](#プレビュー) · [クイックスタート](#クイックスタート) · [よく使うコマンド](#よく使うコマンド) · [ドキュメント](#ドキュメント)

</div>

Linux または macOS に、テーマ、補完、入力候補の自動提案、シンタックスハイライトを備えた Zsh 環境を構築します。好みのターミナルツールの追加、機能の切り替え、更新確認、設定のバックアップ管理を、このプロジェクトでまとめて行えます。

> **プラットフォームの検証状況:** Linux と macOS を実装の対象としていますが、すべてのパッケージや環境の組み合わせを検証済みという意味ではありません。記録された確認結果は[テストと検証](INSTALLER_TESTING.md)を参照してください。

## プレビュー

![Debian 13 での Zsh 起動画面。ツールの状態、Fastfetch のシステム情報、キャッシュ済みの更新通知を表示](assets/Ashampoo_Snap_12h48m48s.png)

<p align="center"><sub>Debian GNU/Linux 13 · Zsh 5.9 · 起動メッセージは中国語</sub></p>

| 見やすいプロンプト | すぐに使えるツール | 日常のメンテナンス |
| :--- | :--- | :--- |
| Powerlevel10k の Rainbow、Lean、Classic、または公式設定ウィザード | FZF 検索、zoxide による移動、Yazi、Neovim、任意の Git・コンテナ管理画面 | 機能の切り替え、更新確認、設定バックアップ、無効化と復元 |

<details>
<summary><strong>スクリーンショットの補足</strong></summary>

- **ツールの状態:** Yazi、FZF、eza、lazygit、Neovim、zoxide などの連携状況と、コマンドやショートカットを表示します。
- **システム情報:** Fastfetch が Debian のロゴ、OS、カーネル、デスクトップ環境、ハードウェア情報を表示します。
- **更新通知:** キャッシュされたプラグインの更新一覧です。`zsh-update` で更新処理に進めます。
- **起動時間:** `5441ms` は、このときの設定読み込みに対する計測値です。ターミナル接続全体の時間や、その後に読み込まれるユーザー拡張、ハイライト、最初のプロンプトのフックは含みません。

`vfox 初始化失败或超时，本次已跳过` は、vfox の初期化に失敗したかタイムアウトしたため、そのセッションではスキップしたことを示します。他のツールは引き続き読み込まれます。[トラブルシューティング](ZSH_TROUBLESHOOTING.md)を参照してください。マシン情報、更新件数、所要時間はいずれも撮影時点の記録です。

</details>

## クイックスタート

対象の Linux または macOS マシンで、通常のユーザーとして実行してください。Linux ではシステムパッケージのインストール時に必要に応じて `sudo` を使用します。`sudo bash install.sh` では実行しないでください。

> **表示言語:** インストーラーと更新画面は英語・中国語に対応しています。この日本語 README の例では `--lang en` を使用します。日本語の画面表示には対応しておらず、管理スクリプトは現在主に中国語です。

### 1. クローンして実行計画を確認

```bash
git clone https://github.com/vicky-clair/xao_Rui_is-one-lick-configuration-script-for-ZSH.git "$HOME/.zsh-project"
cd "$HOME/.zsh-project"
bash scripts/test_installer.sh
bash scripts/test_management.sh
bash install.sh --dry-run --profile basic --p10k-style skip --lang en
```

すでにリポジトリを取得している場合は、そのディレクトリを使用してください。テストに失敗した場合はログを確認してください。`SKIP` は該当機能が未検証であることを意味します。ドライランではネットワークアクセス、プロジェクトの状態の書き込み、ソフトウェアのインストールは行いませんが、パッケージの入手可否やバックアップの整合性も検証しません。

### 2. 構成を選んでインストール

次のうち **1 つ**を実行してください。

```bash
# 基本のシェル設定。既存の個人用テーマを維持
bash install.sh --profile basic --p10k-style skip --lang en

# フルツールセットと Rainbow プロンプト
bash install.sh --profile full --p10k-style rainbow --lang en

# フルツールセット、tmux、対話式プロンプト設定ウィザード
bash install.sh --profile full --with-tmux --p10k-wizard --lang en
```

インストーラーは実行計画を表示して確認を求めます。ログインシェルの変更と新しい Zsh セッションの開始は、それぞれ別に確認します。インストール済みの vfox、lazydocker、lazygit、tmux は自動的に選択項目へ含まれるため、`basic` を選んだ場合も最終計画を確認してください。特に `.tmux.conf` が置き換えられるかどうかに注意してください。

> **配置される設定:** インストーラーは [`templates/zshrc.zsh`](templates/zshrc.zsh) を配置します。ルートの `.zshrc` は動作の異なる参考設定です。個人用のエイリアスは通常 `~/.zshrc.local` に記述します。

### 3. 新しいセッションで確認

```bash
zsh -n "$HOME/.zshrc"
zsh
```

最初は子シェルで検証すると、問題があっても終了して元のターミナルに戻れます。機能の切り替えは新しいセッションで確認してください。`source ~/.zshrc` を繰り返しても、古いエイリアスやフックが確実に取り除かれるわけではありません。

<details>
<summary><strong>別の方法: 単体の起動スクリプトをダウンロード</strong></summary>

確認、管理、再試行にはリポジトリ全体を取得する方法が便利です。起動スクリプトだけをダウンロードし、内容を読んでから実行することもできます。

```bash
bootstrap_dir=$(mktemp -d)
curl -fSL https://raw.githubusercontent.com/vicky-clair/xao_Rui_is-one-lick-configuration-script-for-ZSH/main/install.sh -o "$bootstrap_dir/install.sh"
less "$bootstrap_dir/install.sh"
bash "$bootstrap_dir/install.sh" --dry-run --lang en
bash "$bootstrap_dir/install.sh" --lang en
```

コマンドは 1 つずつ実行し、ダウンロードに失敗した場合は先に進まないでください。テンプレートがない場合、実際のインストールでは `${XDG_CONFIG_HOME:-$HOME/.config}/zsh-project-repo` へのプロジェクト取得を試みます。

Git のクローンに失敗して個別ファイルのダウンロードに切り替わると、Zsh/tmux のテンプレートと更新確認スクリプトだけが取得されます。インストーラーや管理・再試行スクリプトが不足する可能性があるため、その場合はリポジトリ全体を取得してください。初期セットアップ用のダウンロードや Homebrew の準備は、設定置換の最終確認より前に行われる場合があります。`--dry-run` のみ、明示的に早期終了します。

</details>

## 主な機能

| 分類 | 内容と動作 |
| :--- | :--- |
| **基本のシェル環境** | Oh My Zsh、Powerlevel10k、入力候補の自動提案、追加の補完、シンタックスハイライト |
| **フルプロファイル** | FZF、fd、bat、eza、zoxide、Yazi、Neovim、Fastfetch のインストールと連携を試行 |
| **追加ツール** | vfox、lazydocker、lazygit、tmux。SDK の導入、Docker サービスや権限の設定は別途必要 |
| **プロンプトのスタイル** | Rainbow、Lean、Classic、公式ウィザード、または既存の `.p10k.zsh` を維持 |
| **設定管理** | 機能の切り替え、読み取り専用の状態確認、明示的な起動診断、無効化・有効化、失敗したコンポーネントの再試行 |
| **更新** | 起動時のキャッシュ表示、期限到達時のバックグラウンド確認、別コマンドによる確認付き更新 |
| **バックアップ** | 管理対象ファイルの元の内容・存在状態・操作後のハッシュを保存し、復元時にその後の編集を確認 |

### プラットフォームと依存関係

| プラットフォーム・依存項目 | 実装と制約 |
| :--- | :--- |
| **Linux** | APT、DNF/YUM、Pacman、Zypper と一部の派生ディストリビューションを認識します。認識できても、すべての追加ツールのパッケージが存在するとは限りません。 |
| **macOS** | Homebrew を使用し、未導入の場合は対話式で導入を案内できます。記録された今回のローカルテストには macOS 実機での検証は含まれていません。 |
| **アーキテクチャ** | `x86_64`/`amd64`、`aarch64`/`arm64` を受け付けます。各配布元のバイナリには独自の要件があります。 |
| **Windows** | MSYS/Cygwin で一部の隔離テストを実行できます。Windows ネイティブ環境へのインストールには対応していません。 |
| **Bash** | インストーラーと管理スクリプトの実行に必要です。`sh install.sh` は使用しないでください。記録されたテスト環境は Bash 5.2.37 で、それ以前のバージョンの互換性は未確認です。 |
| **Zsh** | 対話用設定の実行に必要です。過去の記録には Debian 13 / Zsh 5.9 での一部のユーザー検証がありますが、現行版も対象マシンでの確認が必要です。 |
| **tmux** | テンプレートをそのまま使うには、`terminal-features` と `display-popup` のために 3.2 以上が必要です。プラグインには追加の要件がある場合があります。 |
| **FZF** | `fzf --zsh` を優先し、古いバージョンではディストリビューション、Homebrew、ユーザーの連携スクリプトを探します。利用可能なスクリプトがなければ更新を案内します。 |
| **タイムアウト用ツール** | `timeout`、次に `gtimeout` を優先します。どちらもない場合、一部の初期化や確認は直接実行しますが、起動診断は実行を拒否します。 |

[tmux 3.2 のリリースノート](https://github.com/tmux/tmux/issues/2737)と [FZF 公式のシェル連携手順](https://github.com/junegunn/fzf#setting-up-shell-integration)も参照してください（`--zsh` は 0.48.0 から利用可能）。このプロジェクトでは、各ディストリビューションの対応最小・最大バージョンは確定していません。

## よく使うコマンド

以下はインストールされるテンプレートの動作です。対応ツールが存在し、該当する機能が有効である必要があります。

| キー・コマンド | 操作 |
| :--- | :--- |
| `Tab` / `→` | 補完 / 行末で自動提案を受け入れる |
| `Ctrl+R` / `Ctrl+T` / `Alt+C` | FZF の履歴検索 / ファイル選択 / ディレクトリ選択（`full=1`） |
| `↑` / `↓` | 入力済みの文字列を前方一致で履歴検索 |
| `Esc` を 2 回 | OMZ の sudo プラグインで入力の先頭に sudo を追加 |
| `y` / `z keyword` | Yazi 終了後にディレクトリを移動 / zoxide で移動（`full=1`） |
| `ll` / `la` | eza の詳細一覧 / 隠し項目を含む一覧（`full=1`） |
| `v` / `vim` / `vi` | Neovim のラッパー関数を実行（`full=1` かつ `nvim` が存在） |
| `lg` / `Ctrl+G` | lazygit を開く |
| `lzd` | lazydocker を開く |
| `gst` / `man command` | OMZ の Git 状態表示エイリアス / マニュアル表示。色はページャーとターミナルに依存 |
| `t` / `ta name` / `tls` / `tn name` | tmux / セッションに接続 / 一覧表示 / 新規セッション作成 |
| `zsh-config` | 設定メニュー。`--doctor` や `--set banner=0` などの管理引数も指定可能 |
| `zsh-check-updates` / `zsh-update` | サードパーティ製コンポーネントの更新確認 / 更新実行 |

<details>
<summary><strong>tmux のショートカットとクリップボードの動作</strong></summary>

プレフィックスキーは **`Ctrl+a`** です。先にプレフィックスを押し、続いて以下のキーを押してください。

| キー | 操作 |
| :--- | :--- |
| `\|` / `-` | 左右 / 上下に分割。現在のディレクトリを引き継ぐ |
| `c` / `m` | ウィンドウを作成 / ペインを最大化・元に戻す |
| `h` / `j` / `k` / `l` | 左・下・上・右方向に 5 セルずつペインのサイズを変更。連続入力可能 |
| `r` | `.tmux.conf` を再読み込み。含まれるコマンドやプラグインも実行 |
| `g` / `G` | ポップアップ / 新しいウィンドウで lazygit を開く |
| `[` | コピーモードへ移行。`v` で選択開始、`Ctrl+v` で矩形選択切り替え、`y` でコピーして終了 |
| `p` / `]` | tmux のバッファを貼り付け |
| `I`（`Shift+i`） | TPM プラグインをインストール |

マウス選択には `copy-pipe` を使用し、コピー後もコピーモードを維持します。キーボードの `y` は `copy-pipe-and-cancel` を使用します。設定では OSC 52 を有効にし、ローカルのクリップボード用ツールも試します。SSH クライアントのクリップボードへコピーできるかどうかは、ターミナルの対応状況、設定、中間レイヤーに依存します。[tmux 公式のクリップボード解説](https://github.com/tmux/tmux/wiki/Clipboard)を参照してください。外側のターミナル本来の選択・貼り付けショートカットも、そのターミナルの設定に従って利用できます。

</details>

## 設定とメンテナンス

```bash
# 設定の状態を確認、または起動バナーを無効化
zsh-config --doctor
zsh-config --set banner=0

# 更新を確認し、準備ができたら確認付きの更新処理へ進む
zsh-check-updates
zsh-update
```

### ツールの更新と設定の再配置

| 目的 | 操作 | 影響 |
| :--- | :--- | :--- |
| サードパーティ製コンポーネントの更新確認 | `bash install.sh --check-updates --lang en` | Git fetch、パッケージ情報の照会、キャッシュの書き込み |
| サードパーティ製コンポーネントの更新 | `bash install.sh --update --lang en` | Git プラグイン、TPM、FZF の取得済みリポジトリ、macOS の Homebrew ツールを更新。テンプレートは配置しない |
| プロジェクトの新しい設定を適用 | ローカルの変更を確認し、`git pull --ff-only` 後にインストーラーを再実行 | 項目を再選択し、バックアップを作成してテンプレートとオプションを配置 |
| 個人用エイリアスの変更 | `~/.zshrc.local` を編集 | 新しいセッションで読み込み。インストーラーは上書きしない |
| 不足するコンポーネントのみ再試行 | `bash install.sh --retry-failed TOOL` | 設定を書き換えずにソフトウェアのインストールを再試行 |

再インストールでは、必要な内容がそろっている既存の OMZ・テーマ・プラグインのディレクトリを維持し、導入済みの追加コマンドの一部をスキップします。ただし、基本依存関係の処理では引き続きパッケージマネージャーを呼び出します。Arch の処理には `pacman -Syu` が含まれ、古い FZF/Neovim はダウンロードが必要になる場合があります。オプションは再生成され、テーマや tmux の設定が再配置される場合もあります。所要時間は一定ではなく、変更行だけをコピーする処理でもありません。

バックグラウンド確認の既定の間隔は **7 日**で、対話式 Zsh セッションを開いたときに期限を判定します。独立した定期実行サービスではありません。`auto-update` を無効にしても既存のキャッシュ通知は非表示になりません。APT の結果はローカルのパッケージ索引に依存します。Zypper/YUM のみの環境、`checkupdates` のない Arch、単体のリリースバイナリでは、アプリケーションのバージョン確認が完全にはカバーされません。「更新なし」は実際に確認した範囲のみを示します。

<details>
<summary><strong>インストーラーと管理オプションの一覧</strong></summary>

1 回の呼び出しにつき、主な操作は 1 つ選んでください。引数、確認ルール、対象範囲は[設定管理](CONFIGURATION_MANAGEMENT.md)を参照してください。

| オプション | 用途 |
| :--- | :--- |
| `--help` / `-h` | インストーラーのヘルプを表示 |
| `--dry-run` | 実行計画のみを表示 |
| `--profile basic` / `--profile full` | 基本のシェル環境 / フルツールセットを選択 |
| `--p10k-style STYLE` | `rainbow`（既定）、`lean`、`classic`、`wizard`、`skip` |
| `--p10k-wizard` | `--p10k-style wizard` と同じ |
| `--with-latest-nvim` | Homebrew を使わない `full` プロファイルで Neovim 公式リリースのダウンロードを要求。`basic` では単独で有効にならない |
| `--with-vfox` / `--with-lazydocker` / `--with-lazygit` / `--with-tmux` | 対応する追加ツールを有効化 |
| `--lang zh` / `--lang en` | インストール・更新画面の言語。管理スクリプトは現在主に中国語 |
| `--check-updates` | ネットワーク経由で確認してキャッシュへ書き込み。ソフトウェアの更新は行わない |
| `--update` | 確認・同意後にサードパーティ製コンポーネントを更新。Linux のシステムパッケージは手動更新が必要 |
| `--rollback DIR` | インストール時のバックアップから管理対象の設定を復元。対話式の確認が必要 |
| `--disable` / `--enable` | このプロジェクトの Zsh 設定を無効化 / 再有効化 |
| `--configure` / `--set KEY=0` / `--set KEY=1` | 設定メニューを開く / 個別の機能を切り替える |
| `--doctor` / `--profile-startup` | 読み取り専用の状態確認 / 設定を実際に実行する起動診断 |
| `--retry-failed [TOOL]` | 失敗一覧または指定したツールを再試行 |
| `--list-backups` / `--diff-backup DIR` | バックアップ一覧 / 差分を表示 |
| `--restore-backup DIR --scope zsh` | 範囲を指定して復元。`zsh`、`tmux`、`all` を選択可能 |
| `--yes` | 管理・再試行の入口でのみ確認を明示的に省略。通常のインストール・更新・ロールバックでは使用不可 |

テーマの短縮オプションとして `--p10k-rainbow`、`--p10k-lean`、`--p10k-classic`、`--p10k-skip` も使用できます。

</details>

### 設定の復元

```bash
bash install.sh --list-backups
bash install.sh --diff-backup /path/to/install-XXXXXXXX --scope all
bash install.sh --rollback /path/to/install-XXXXXXXX
```

例のパスは、インストール時に表示された `install-XXXXXXXX` バックアップディレクトリに置き換えてください。復元対象は記録された設定ファイルのみです。ソフトウェアのアンインストール、プラグインのバージョンの巻き戻し、ログインシェルの復元は行いません。その後の編集によってハッシュが一致しない場合は、上書きを拒否します。範囲を指定した復元については[設定管理](CONFIGURATION_MANAGEMENT.md)を参照してください。

<details>
<summary><strong>既知の制限</strong></summary>

- 独自の `ZDOTDIR` には対応していません。管理対象ファイルがシンボリックリンクやディレクトリの場合、インストーラーは自動置換を拒否します。
- メインインストーラーの lazydocker ダウンロードの代替処理では、現在もバージョン番号を含まないアセット名を使用しています。失敗した場合は、`--retry-failed lazydocker` によるバージョン付きのダウンロード処理を試してください。
- `failed-components` はスキップされたパッケージの記録であり、すべてのインストール手順やプラグインの完全な状態レポートではありません。TPM プラグインのインストール失敗が無視される場合があります。
- `--update` には、設定全体の統一されたスナップショットや処理全体を元に戻す仕組みはありません。TPM と FZF のすべての操作でローカル変更が保護されるわけではありません。
- インストールログはバックアップディレクトリに保存されます。インストール失敗時にはバックアップのハッシュが不完全な場合があり、自動ロールバックは保証されません。

その他の制約やメンテナンス事項は[開発ドキュメント](DEVELOPMENT.md)を参照してください。

</details>

## ドキュメント

以下の詳細ガイドは現在、中国語で記述されています。この README は現行の `install.sh`、`scripts/`、`templates/` の実装に基づいています。対応を目指すプラットフォームと実際の検証結果は分けて記録しています。

| ガイド | 内容 |
| :--- | :--- |
| [インストールガイド](LINUX_ZSH_SETUP_GUIDE.md) | 初回インストール、手動配置、新しいセッションでの確認 |
| [設定管理](CONFIGURATION_MANAGEMENT.md) | 機能の切り替え、無効化・復元、コンポーネントの再試行、バックアップ |
| [トラブルシューティング](ZSH_TROUBLESHOOTING.md) | 起動エラー、ツールの不足、更新失敗、ターミナル表示の問題 |
| [開発ドキュメント](DEVELOPMENT.md) | モジュールの役割、読み込み順序、状態ファイル、保守上の規約 |
| [テストと検証](INSTALLER_TESTING.md) | 隔離された回帰テスト、実機確認、検証済みの範囲 |

<details>
<summary><strong>リポジトリの構成</strong></summary>

| パス | 用途 |
| :--- | :--- |
| `install.sh` | インストール、サードパーティ製コンポーネントの更新、インストールバックアップからの復元、管理処理への振り分け |
| `scripts/manage.sh` / `scripts/retry_tools.sh` | 設定管理 / 失敗したコンポーネントの再試行 |
| `scripts/check_updates.sh` | 更新検出とキャッシュの書き込み |
| `scripts/test_installer.sh` / `scripts/test_management.sh` | 現行の隔離回帰テストの入口 |
| `templates/zshrc.zsh` / `templates/tmux.conf` | インストーラーが実際に配置するテンプレート |
| `templates/zshrc.local.example` | 個人用拡張の例 |
| `.zshrc` / `.tmux.conf` | ルートの参考設定。`.zshrc` はインストール用テンプレートと動作が異なる |
| `.zshenv` | 現在は空のファイル。インストーラーは配置しない |
| `.github/workflows/tests.yml` | Linux コンテナの回帰テストワークフロー。結果は各実行記録を参照 |
| `assets/` | プロジェクトのスクリーンショット |
| `scratch/`、`*.before-fix`、`.zhistory`、`.zsh_history` | 過去の監査資料、バックアップ、コマンド記録。新しいマシンへの配置には使用しない |

</details>

---

<p align="center">
  <a href="#zsh-configuration-manager">ページ上部へ</a> · <a href="README.md">English</a> · <a href="README.zh-CN.md">简体中文文档</a>
</p>
