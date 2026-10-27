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

- **ツールの状態:** Yazi、FZF、television、eza、tre、lazygit、Neovim、zoxide などの連携状況と、コマンドやショートカットを表示します。
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

### 4. 重要な注意事項とベストプラクティス

1. **一般ユーザーでの実行（sudo は使用しない）**: 対象マシンで通常のユーザーとして `bash install.sh` を実行してください。システムパッケージのインストール時に必要に応じて自動で `sudo` を要求します。`sudo bash install.sh` で実行すると、ホームディレクトリの設定ファイルの所有権が `root` になり権限の問題が発生します。
2. **Nerd Font の導入**: Powerlevel10k プロンプトや Yazi/Tmux 状態バーのアイコン表示には [JetBrainsMono Nerd Font](https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip) などの Nerd Font が必要です。ターミナル（Windows Terminal、iTerm2、WezTerm 等）のフォント設定を変更してください。
3. **個人用設定は `~/.zshrc.local` に記述**: 個人用の環境変数、エイリアス、関数は `~/.zshrc.local` に記述してください。インストーラーや更新機能（`zsh-update`）がこのファイルを上書きすることはありません。
4. **新しいセッションでの反映**: 設定変更後は、新しいターミナルを開くか `exec zsh` を実行してください。`source ~/.zshrc` では古いエイリアスやフックが完全には解除されません。
5. **デスクトップ・サーバー向け Tmux バッテリー非表示**: バッテリーのないデスクトップやクラウドサーバーでは、`~/.tmux.conf` の `@theme_plugins` から `battery` を削除し、Tmux 内で `Ctrl + a r` を押すことでアイコンを非表示にできます。
6. **UTF-8 と LF 改行コード**: 設定ファイルは UTF-8 および LF (`\n`) 改行コードを維持してください。Windows の CRLF 改行コードで保存しないでください。

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
| **フルプロファイル** | FZF、fd、bat、eza、zoxide、Yazi（マルチメディアプレビュー連携ツール: ripgrep、jq、ffmpeg、7-zip、poppler、ImageMagick、resvg 等を含む）、Neovim、Fastfetch、television、tre、agrep のインストールと連携を試行 |
| **追加ツール** | vfox、lazydocker、lazygit、tmux。SDK の導入、Docker サービスや権限の設定は別途必要 |
| **プロンプトのスタイル** | Rainbow、Lean、Classic、公式ウィザード、または既存の `.p10k.zsh` を維持 |
| **設定管理** | 機能の切り替え、読み取り専用の状態確認、明示的な起動診断、無効化・有効化、失敗したコンポーネントの再試行 |
| **更新** | 起動時のキャッシュ表示、期限到達時のバックグラウンド確認、別コマンドによる確認付き更新 |
| **バックアップ** | 管理対象ファイルの元の内容・存在状態・操作後のハッシュを保存し、復元時にその後の編集を確認 |

### プラットフォームと依存関係

| プラットフォーム・依存項目 | 実装と制約 |
| :--- | :--- |
| **Linux** | APT、DNF/YUM、Pacman、Zypper と一部の派生ディストリビューションを認識します。認識できても、すべての追加ツールのパッケージが存在するとは限りません。 |
| **macOS** | Homebrew を使用（未導入時は対話式で導入を案内可能）。macOS（Apple Silicon arm64 / Intel）実機でのインストール・プロンプト描画・全回帰テストを検証済み。 |
| **アーキテクチャ** | `x86_64`/`amd64`、`aarch64`/`arm64` を受け付けます。各配布元のバイナリには独自の要件があります。 |
| **Windows** | MSYS/Cygwin で一部の隔離テストを実行できます。Windows ネイティブ環境へのインストールには対応していません。 |
| **Bash** | インストーラーと管理スクリプトの実行に必要です。`sh install.sh` は使用しないでください。macOS 標準の Bash 3.2 (3.2.57) および Linux の Bash 4/5 で完全互換性を検証済み。 |
| **Zsh** | 対話用設定の実行に必要です。macOS (Zsh 5.9) および Debian 13 (Zsh 5.9) での実機検証を完了しています。 |
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
| `y` / `z keyword` | Yazi ファイルマネージャー（動画・PDF・画像プレビュー対応、終了後にディレクトリ移動） / zoxide で移動（`full=1`） |
| `tv` / `Ctrl+P` | television 曖昧ファインダー（`full=1`、`tv-keys=1` で Ctrl+T/Ctrl+R を置き換え可能） |
| `tre` | モダンなディレクトリツリー表示（`full=1`、`.gitignore` 対応および `-e` 番号ジャンプ連携） |
| `agrep` | TRE 近似正規表現検索 CLI ツール（`full=1`） |
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
| `r` | `.tmux.conf` を再読み込み。変更した設定やプラグインも直ちに反映 |
| `g` / `G` | ポップアップ / 新しいウィンドウで lazygit を開く |
| `[` | コピーモードへ移行（`v` で選択開始、`Ctrl+v` で矩形選択切り替え、`Esc` で終了、`y` でコピーして終了） |
| `p` / `]` | tmux のバッファを貼り付け（ローカルからリモートへ貼り付ける場合は、ターミナルの `Ctrl+Shift+V` や `Cmd+V` を使用） |
| `I`（`Shift+i`） | TPM プラグインをインストール |

**ステータスバー設計とリアルタイムハードウェア監視**:
- **画面最下部に常駐**: `status-position bottom` により、ターミナルの視認性を考慮して常に下部に配置されます。新規システムでは初期状態から下部に表示されます。
- **即時ホットリロード**: `~/.tmux.conf` を編集した場合、tmux 内で **`Ctrl + a` に続いて `r`** を押すだけで、サーバーを再起動することなく設定が即座に反映されます。
- **Tokyo Night モニタリング**: 右側ステータスバーは安定版 `v2.7.2` エンジンと Nerd Font アイコンで駆動します：
  - `󰥔 日時`: リアルタイムの日時と時刻
  - `󰛳 ネットワーク`: リアルタイムの送受信トラフィック (`↓1K ↑2K`)
  - ` CPU`: リアルタイムのコア使用率 (%)
  - ` メモリ`: 物理 RAM 使用率 (%)
  - `󰋊 ディスク`: ルートファイルシステム使用率 (%)
  - `󰁹 バッテリー`: ノート PC のバッテリー残量と充電状態
- **デスクトップ・サーバー向け設定**: バッテリーのないデスクトップ PC やクラウドサーバーでは、Linux の `upower` が仮想的な 0% バッテリーを報告することがあります。`~/.tmux.conf` の `@theme_plugins` から `battery` を削除し `Ctrl+a r` で再読み込みすることで、アイコンを非表示にできます。

**クリップボードとマウスの操作ガイド**:
- **コピー後に自動終了**: マウスドラッグ解放、ダブルクリック（単語選択）、トリプルクリック（行選択）、キーボードの `y` はすべて `copy-pipe-and-cancel` を使用し、クリップボードへコピーした直後にコピーモードを終了します（入力フリーズを防止）。
- **いつでもコピーモードを終了**: `Esc` を押すか、ペイン内の任意の位置を**シングルクリック**することで、直ちにコピーモードを終了して通常のシェル入力へ復帰できます。
- **全ターミナル向け OSC 52 連携**: ターミナル機能をワイルドカード（`*:RGB:clipboard`）で有効化し、`Ms` シーケンスを注入することで、Windows Terminal、iTerm2、Alacritty、WezTerm 等で追加ツールなしにクリップボード同期が可能です。また、SSH X11 転送が不安定な際のハングを防ぐため `xclip` に 1 秒のタイムアウト保護を追加しました。
- **ターミナルネイティブ選択のヒント**: **`Shift`** キーを押しながらマウスでドラッグすると、tmux のマウス横取りを回避し、ターミナルエミュレーター本来の範囲選択・コピーを使用できます。

👉 **セッション管理、ステータスバーのトラブルシューティング、Vim 連携、クラッシュ復元の詳細については、[Tmux 利用ガイド (TMUX_USAGE_GUIDE.md)](TMUX_USAGE_GUIDE.md) を参照してください**。

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
| `--without-tmux` / `--no-tmux` | システムに tmux が導入済みであっても tmux とその設定の反映を明示的にスキップ |
| `--with-terminals` / `--with-terminal-configs` | [`terminal_configs/`](terminal_configs/README.md) 内の WezTerm・Alacritty 設定をバックアップ付きで配置 |
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
| `--yes` / `-y` | 非対話式自動化モード。すべてのプロンプトで自動的に yes を選択（CI/CD、Docker、スクリプト自動実行用） |

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
- `failed-components` はスキップされたパッケージの記録であり、すべてのインストール手順やプラグインの完全な状態レポートではありません。TPM プラグインのインストール失敗が無視される場合があります。
- `--update` には、設定全体の統一されたスナップショットや処理全体を元に戻す仕組みはありません。TPM と FZF のすべての操作でローカル変更が保護されるわけではありません。
- インストールログはバックアップディレクトリに保存されます。インストール失敗時にはバックアップのハッシュが不完全な場合があり、自動ロールバックは保証されません。

その他の制約やメンテナンス事項は[開発ドキュメント](DEVELOPMENT.md)を参照してください。

</details>

## 設定オプションと実行時環境

ユーザー機能の切り替えは `~/.zsh-project-options` にプレーンなキーと値のペアとして安全に保持されます（任意のコード実行は行われません）。Zsh 起動時にオンデマンドで読み込まれ、`bash install.sh --set KEY=0|1` または `zsh-config` メニューからいつでも調整可能です。

| 設定キー | 設定値 | デフォルト | 機能と説明 |
| :--- | :--- | :--- | :--- |
| `ZSH_PROJECT_FULL` | `0` または `1` | `0` (basic) / `1` (full) | フル CLI ツールチェーンエイリアスと統合（FZF、Yazi、television、tre、eza 等）を有効化 |
| `ZSH_PROJECT_VFOX` | `0` または `1` | `0` | Zsh 起動時に vfox バージョンマネージャーをアクティブ化 |
| `ZSH_PROJECT_LAZYDOCKER` | `0` または `1` | `1` | lazydocker コンテナ管理エイリアス (`lzd`) をマウント |
| `ZSH_PROJECT_LAZYGIT` | `0` または `1` | `1` | lazygit Git TUI エイリアス (`lg`) とショートカット (`Ctrl+G`) をマウント |
| `ZSH_PROJECT_TMUX` | `0` または `1` | `0` (通常) / `1` (`--with-tmux`) | tmux 補助エイリアス (`t`, `ta`, `tls`, `tn`) とクリップボード連携を有効化 |
| `ZSH_PROJECT_TMUX_AUTO` | `0` または `1` | `1` | 対話型ターミナル起動時に `main` セッションへ自動接続または新規作成 |
| `ZSH_PROJECT_BANNER` | `0` または `1` | `1` | ターミナル起動時のウェルカムバナーとツール読み込み状況を表示 |
| `ZSH_PROJECT_FASTFETCH` | `0` または `1` | `1` | 起動時に Fastfetch を実行しシステム情報を表示 |
| `ZSH_PROJECT_TIMER` | `0` または `1` | `1` | シェルの高精度起動時間を計測・表示 |
| `ZSH_PROJECT_AUTO_CHECK_UPDATE` | `0` または `1` | `1` | バックグラウンド非同期更新検出を有効化（非ブロッキング） |
| `ZSH_PROJECT_CHECK_INTERVAL_DAYS`| 正の整数 | `7` | 自動更新確認の間隔日数（日） |
| `ZSH_PROJECT_TELEVISION` | `0` または `1` | `1` | television (`tv`) スマート曖昧検索ツールを有効化 |
| `ZSH_PROJECT_TV_KEYBINDINGS` | `0` または `1` | `0` | television による Ctrl+T / Ctrl+R ショートカットの引き継ぎを許可 |
| `ZSH_PROJECT_TRE` | `0` または `1` | `1` | tre ディレクトリツリーラッパーエイリアスを有効化 |

---

## ローカルテスト・開発および Docker コンテナ検証

本プロジェクトには、隔離された回帰テストスイートと静的解析ルールが完全に用意されています。

### 1. ローカルテストおよび静的解析コマンド

```bash
# 1. ShellCheck による全スクリプトの静的解析（0 エラー 0 警告必須）
shellcheck install.sh scripts/*.sh

# 2. Bash / Zsh 構文解析チェック
bash -n install.sh scripts/*.sh
zsh -n templates/zshrc.zsh .zshrc

# 3. インストーラー隔離回帰テスト（モックダウンロード、シンボリックリンク交換、バージョン境界検証）
bash scripts/test_installer.sh

# 4. 設定マネージャー隔離回帰テスト（スナップショット、チェックサム、ロールバック保護）
bash scripts/test_management.sh

# 5. 読み取り専用環境診断（24 種類の CLI ツールおよびバージョン検出）
bash scripts/manage.sh --doctor
```

### 2. 隔離 Docker コンテナでの動作確認

ローカル環境を変更することなく、Docker コンテナで完全なインストールプロセスを体験・テストできます：

```bash
docker run --rm -it ubuntu:24.04 bash -c "
  apt-get update && apt-get install -y git sudo curl ca-certificates zsh tmux
  useradd -m -s /bin/bash testuser && echo 'testuser ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers
  su - testuser -c '
    git clone https://github.com/vicky-clair/xao_Rui_is-one-lick-configuration-script-for-ZSH.git ~/.zsh-project
    cd ~/.zsh-project
    bash install.sh --profile full --with-tmux --with-terminals --p10k-style rainbow --yes --lang en
    zsh
  '
"
```

---

## トラブルシューティング FAQ

| 現象・エラー | 原因 | 推奨される解決策 |
| :--- | :--- | :--- |
| プロンプトのアイコンが四角 (`□`) や `?` に化ける | ホストターミナルに Nerd Font ベクターアイコンフォントが不足 | ターミナルソフト（Windows Terminal / iTerm2 / WezTerm）の設定でフォントを **JetBrainsMono Nerd Font** に変更してください。 |
| `vfox の初期化に失敗またはタイムアウト` | vfox が初期化されていないかネットワーク環境の遅延 | `vfox --version` を実行するか、`bash install.sh --retry-failed vfox` で再試行してください。 |
| `macOS Bash version (3.2) < 4.0` 警告 | macOS 標準の `/bin/bash` が 2007 年の古いバージョン 3.2 である | `brew install bash` を実行してください。スクリプト自体は Bash 3.2 と完全な互換性がありますが、Tmux の一部モダンテーマで新しい Bash が推奨されます。 |
| Tmux 内部でシステムクリップボードが共有されない | リモート SSH セッションで OSC 52 または X11 転送が未設定 | 本設定では OSC 52 透過が標準有効化されています。Windows Terminal、iTerm2、WezTerm 上でマウスドラッグまたは `y` キーを押すだけでローカルクリップボードへ自動コピーされます。 |

> 詳しい起動エラー、プラグインの競合、復旧手順は [ZSH_TROUBLESHOOTING.md](ZSH_TROUBLESHOOTING.md) をご覧ください。

---

## コントリビューションとフィードバック

プルリクエストや Issue の報告を歓迎します。

1. **本リポジトリを Fork** し、`main` からブランチを作成 (`git checkout -b feature/awesome-feature`)。
2. **コードの品質基準**:
   - Bash 3.2 互換性を保持する。
   - `shellcheck install.sh scripts/*.sh` で 0 警告を維持する。
   - `bash scripts/test_installer.sh` および `bash scripts/test_management.sh` で全テスト PASS を確認する。
3. **コミット**: Conventional Commits 規約（`feat(...)`、`fix(...)`、`docs(...)`）に従ってください。
4. **プルリクエストの作成**: 変更内容とテスト結果を明記してください。

フィードバック・問題報告: [GitHub Issues](https://github.com/vicky-clair/xao_Rui_is-one-lick-configuration-script-for-ZSH/issues)

---

## ライセンスと謝辞

本プロジェクトは **MIT ライセンス** のもとで公開されています。詳細は [LICENSE](LICENSE) を参照してください。

### オープンソースへの謝辞

- [Oh My Zsh](https://github.com/ohmyzsh/ohmyzsh)
- [Powerlevel10k](https://github.com/romkatv/powerlevel10k)
- [Yazi](https://github.com/sxyazi/yazi)
- [tmux](https://github.com/tmux/tmux) & [tmux-tokyo-night](https://github.com/fabioluciano/tmux-tokyo-night)
- [fzf](https://github.com/junegunn/fzf), [eza](https://github.com/eza-community/eza), [bat](https://github.com/sharkdp/bat), [zoxide](https://github.com/ajeetdsouza/zoxide), [fastfetch](https://github.com/fastfetch-cli/fastfetch), [television](https://github.com/alexpasmantier/television), [tre-command](https://github.com/dduan/tre), [vfox](https://github.com/version-fox/vfox), [neovim](https://github.com/neovim/neovim)

---

## ドキュメント

以下の詳細ガイドは現在、中国語で記述されています。この README は現行の `install.sh`、`scripts/`、`templates/` の実装に基づいています。対応を目指すプラットフォームと実際の検証結果は分けて記録しています。

| ガイド | 内容 |
| :--- | :--- |
| [インストールガイド](LINUX_ZSH_SETUP_GUIDE.md) | 初回インストール、手動配置、新しいセッションでの確認 |
| [Tmux 利用ガイド](TMUX_USAGE_GUIDE.md) | Tmux ショートカットチートシート、リモートクリップボード設定、障害復元 |
| [設定管理](CONFIGURATION_MANAGEMENT.md) | 機能の切り替え、無効化・復元、コンポーネントの再試行、バックアップ |
| [トラブルシューティング](ZSH_TROUBLESHOOTING.md) | 起動エラー、ツールの不足、更新失敗、ターミナル表示の問題 |
| [開発ドキュメント](DEVELOPMENT.md) | モジュールの役割、読み込み順序、状態ファイル、保守上の規約 |
| [テストと検証](INSTALLER_TESTING.md) | 隔離された回帰テスト、実機確認、検証済みの範囲 |
| [監査レポート](AUDIT_REPORT.md) | セキュリティおよびエンジニアリング品質監査レポート |

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
| `terminal_configs/` | WezTerm および Alacritty の推奨ターミナル設定とフォールバック |
| `AUDIT_REPORT.md` | セキュリティおよびエンジニアリング品質監査レポート |
| `LINUX_ZSH_SETUP_GUIDE.md` | Linux / macOS 全工程環境インストール・設定ガイド |
| `TMUX_USAGE_GUIDE.md` | Tmux 活用ガイド、ショートカット、クリップボード連携、実用テクニック |
| `CONFIGURATION_MANAGEMENT.md` | オプション切り替え、スナップショットバックアップ、管理ファイル機構 |
| `DEVELOPMENT.md` | 開発規約、モジュールアーキテクチャ、読み込みライフサイクル |
| `INSTALLER_TESTING.md` | 検証テストスイート仕様および実機テスト記録 |
| `ZSH_TROUBLESHOOTING.md` | Zsh ターミナルの総合トラブルシューティングガイド |
| `.zshrc` / `.tmux.conf` | ルートの参考設定。`.zshrc` はインストール用テンプレートと動作が異なる |
| `.zshenv` | 現在は空のプレースホルダー。インストーラーは配置しない |
| `.github/workflows/tests.yml` | Linux コンテナ回帰および ShellCheck 静的解析 CI ワークフロー |
| `assets/` | プロジェクトのスクリーンショット |

</details>

---

<p align="center">
  <a href="#zsh-configuration-manager">ページ上部へ</a> · <a href="README.md">English</a> · <a href="README.zh-CN.md">简体中文文档</a>
</p>
