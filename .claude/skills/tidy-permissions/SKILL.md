---
name: tidy-permissions
description: >-
  Claude Code の許可リストを定期整理する。トランスクリプトから常用コマンドを集計し、
  安全なもの(read-only + 非破壊なローカル作成/変更)を「リポ固有 → このリポの .claude/settings.json」
  「PC全体で汎用 → cc-dotfiles の .chezmoidata.yaml」に振り分け、危険な広域許可と
  settings.local.json の蓄積ノイズを一掃する。許可プロンプトが増えてきた / 設定を
  片付けたい時にユーザーが起動する(主に dotfiles リポでの定期メンテ作業)。
---

# tidy-permissions

Claude Code の許可設定を「版管理された意図の集合」に保つための定期整理スキル。
`fewer-permission-prompts`(組み込み)のスキャン手法をベースに、このユーザー固有の
**3分割ルーティング**と **cc-dotfiles(chezmoi)連携**を加えたもの。

このスキルは原則 **dotfiles リポ(`~/ghq/github.com/Hirayama61/dotfiles`)** で実行する。

## 前提となる場所

- トランスクリプト: `~/.claude/projects/<sanitized-cwd>/*.jsonl`(直近 ~50 ファイルを横断)
- リポ固有 allowlist: このリポの `.claude/settings.json`(git 追跡。版管理された意図)
- ローカル junk: `.claude/settings.local.json`(`~/.config/git/ignore` で ignore 済。蓄積する)
- PC全体 allowlist: `~/ghq/github.com/Hirayama61/cc-dotfiles/home/.chezmoidata.yaml`
  の `claude.permissions.allow`(→ `settings.json.tmpl` 経由で `~/.claude/settings.json` に展開)
- cc-dotfiles の chezmoi config: `~/.config/chezmoi/cc-dotfiles.toml`
  (`mise env` で `CHEZMOI_CC_DOTFILES` を取得できる)

## 手順

### 1. 集計

直近 ~50 の `*.jsonl` を走査し、`tool_use` の Bash `input.command` から
先頭コマンド + 第1サブコマンド(`sudo`/`timeout`/env 接頭辞・パイプ・`&&` を考慮)を、
MCP は完全ツール名を、出現回数つきで集計する。`< 3` 回は捨てる。

### 2. 安全なものに絞る(read-only + 非破壊なローカル作成/変更)

**必ず除外(任意コード実行 = 許可の意味が消える):**
インタプリタ(`python`/`python3`/`node`/`bun`/`deno`/`ruby`/`perl`/`php`/`lua`)、
シェル(`bash`/`sh`/`zsh`/`eval`/`exec`/`ssh`)、ランナー(`npx`/`bunx`/`uvx`/`uv run`)、
タスクランナーのワイルドカード(`mise run *` を除く ※後述)、`gh api *`、`docker run/exec`、
`kubectl exec`、`sudo`、`curl`(URL 完全一致でない限り)。

**許容(read-only に加え、非破壊なローカル作成/変更):**
ファイル/ディレクトリを「作る・複製する・移動する」だけで、削除も権限変更もしない
もの。`mkdir`/`touch`/`cp`/`mv`/`ln`。read-only 全般と `jq`(純フィルタ。fs 書き込み
もコマンド実行もしない)も許容。`git add` / `git commit -m`(ローカル限定)も許容。

**除外(破壊・特権・副作用 — ここは溶かさない監査の不変条件):**
削除(`rm`/`rmdir`)、権限/所有変更(`chmod`/`chown`)、特権昇格(`sudo`)、
インストール/ビルド(`brew bundle/uninstall`・`mise install`・`mise exec`)、
ネットワーク/リモート副作用(汎用 `curl`・`git push`/`merge`)。
理由: 「作成」と「削除/権限変更/コード実行/ネットワーク」の間に線を引く。
低リスクでも削除・権限・特権・remote は無確認にしない(`chmod -R 777` の類を防ぐ)。

**除外(冗長):**
- Claude Code がコア自動許可するもの(`cat`/`ls`/`grep`/`find`/`echo`/`printf`/
  全 git read-only サブコマンド/全 gh read-only サブコマンド 等)。
  迷ったら組み込み `fewer-permission-prompts` スキルの一覧を参照。
- 既に cc-dotfiles `.chezmoidata.yaml` の allow にあるもの(`mise run:*` 等)。
- 具体パス1回限りのノイズ(特定ファイルへの `grep`/`cat`、特定コミットメッセージ等)。

### 3. 3分割ルーティング

残ったものを次に振り分ける:

| 区分 | 行き先 | 判定基準 |
|---|---|---|
| **リポ固有** | このリポ `.claude/settings.json` | 絶対パスに `h61`/このリポパスを含む、ターミナルテーマ/ghostty 作業、`open /tmp/*.html`、`Read(~/.config/**)`、`additionalDirectories` |
| **PC全体・汎用** | cc-dotfiles `.chezmoidata.yaml` | パス非依存でどの PC でも有用(`mise registry`/`brew search`/`command -v`/各種 `--version`/汎用 `WebFetch` ドメイン/`git add`/`git commit -m`/非破壊 fs 操作 `mkdir`・`touch`・`cp`・`mv`・`ln`・`jq`) |
| **捨てる** | (削除) | 危険・副作用・冗長・ノイズ(手順2で除外したもの) |

絶対パスにユーザー名を含むものは **global に入れない**(仕事用 PC で username が異なり非可搬)。
リポ固有として `.claude/settings.json` に置く。

### 4. 反映

- **リポ固有**: `.claude/settings.json` の `permissions.allow` にマージ(既存キー保持・重複排除・
  並べ替えない・`deny`/`ask` には触れない)。`additionalDirectories` は維持。
- **PC全体**: `.chezmoidata.yaml` の `claude.permissions.allow` に、既存のコメント分類
  スタイル(`# ----- 分類名 -----`)に合わせて追記。
  反映は次で(対話 TTY を避ける):
  ```sh
  cd ~/ghq/github.com/Hirayama61/dotfiles
  eval "$(mise env -s bash | grep CHEZMOI_CC_DOTFILES)"
  # 先に pending diff を確認し、機能差分が「許可エントリ追加」だけであることを必ず検証する
  chezmoi --config "$CHEZMOI_CC_DOTFILES" diff "$HOME/.claude/settings.json"
  chezmoi --config "$CHEZMOI_CC_DOTFILES" apply --force "$HOME/.claude/settings.json"
  ```
  ⚠️ `settings.json.tmpl` 等に保留中の別作業がある場合、diff に許可以外の変更
  (marketplace/plugin 等)が**±付きで**出ていないか確認。出ていれば apply せず、
  許可追加のみが反映されるタイミングまで保留しユーザーに報告する。
- **junk リセット**: `.claude/settings.local.json` を `{}` にする(危険・ノイズを全消去)。
  ※ クリック許可で再蓄積するので、このスキルは定期的に回す前提。

### 5. 報告とコミット

- 追加/移動/削除した内容を表で提示(件数と代表例、除外理由)。
- コミットは**ユーザーに確認**してから。勝手にコミットしない。
- cc-dotfiles 側に保留中の別作業が同居する場合は、私の許可追加分のみ
  部分ステージする方針を提示する(全部まとめない)。

## 原則

- `permissions.deny` / `permissions.ask` は触らない。`permissions.allow` のみ。
- 「迷ったら入れない」。広い許可1つより、安全な狭い許可を増やす。
- 危険な広域ワイルドカードは**絶対に追加しない**(過去 `python3 *`/`mise exec *` で汚染した)。
- allow に入れてよいのは **read-only + 非破壊ローカル作成/変更**(作る・複製・移動)まで。
  **削除・権限/所有変更・特権昇格・任意コード実行・ネットワーク/リモート副作用は恒久的に
  除外**。これが allowlist を監査可能に保つ不変条件で、低リスクを理由に溶かさない。
- このスキル自体は dotfiles リポにのみ存在させる(cc-dotfiles に置くと仕事用 PC へ伝播し、
  プライベートアカウントへのコミットを誘発するため)。
