# CLAUDE.md

このファイルは Claude Code (claude.ai/code) がこのリポジトリで作業する際のガイドラインです。

## スタック

macOS 用 dotfiles を **chezmoi** で管理。**mise を司令塔**にして適用・更新・削除自動化を1コマンドに統一。Claude Code 自身の設定(`~/.claude/...`)は **別リポ `Hirayama61/cc-dotfiles`** に分離し、このリポからオーケストレートする。

## ディレクトリ構成

```
dotfiles/                          # このリポ
├── .chezmoiroot                   # 内容: "home" — chezmoi にソースルートを伝える
├── home/                          # chezmoi ソース。ここ配下のみが $HOME に展開される
│   └── dot_zshrc, dot_config/...  # dot_ プレフィックスで $HOME に . 始まりとして展開
├── template/
│   ├── dotfiles.toml              # ~/.config/chezmoi/dotfiles.toml の雛形
│   └── cc-dotfiles.toml         # ~/.config/chezmoi/cc-dotfiles.toml の雛形
├── bin/sync.sh                    # 削除自動化付き chezmoi apply ラッパー
├── Brewfile                       # mise(bootstrap CLI) + GUI cask のみ
├── mise.toml                      # 全タスクの入口
└── CLAUDE.md / README.md / LICENSE

~/ghq/github.com/Hirayama61/cc-dotfiles/   # 別リポ(運用中。Claude Code 設定を管理)
├── .chezmoiroot
└── home/dot_claude/...            # ~/.claude/... を管理

~/.config/chezmoi/                 # ローカル限定(どちらのリポにも入らない)
├── dotfiles.toml                  # sourceDir, persistentStateAbsPath, [data]
└── cc-dotfiles.toml             # 同上(cc-dotfiles 用)
```

## 適用方法

適用は **必ず `mise run apply` 経由**。`~/.zshrc` 等 chezmoi 管理下のファイルを直接編集しない — 次の apply で source の内容に上書きされる。

```sh
mise run bootstrap        # 新マシン初回: brew bundle + config 雛形配置 + apply
mise run apply            # 両リポ適用(削除自動化込み)
mise run apply:dotfiles   # このリポだけ
mise run apply:cc-dotfiles     # cc-dotfiles だけ(リポが clone されてなければ skip)
mise run diff             # 両リポの pending diff
mise run update           # 両リポ git pull → apply
```

## 削除自動化の仕組み

chezmoi はソースから消えたファイルの target を自動削除しない。`bin/sync.sh` がこれを補う:

1. 適用前に `chezmoi managed` の出力を `~/.cache/dotfiles/<name>-managed.txt` に保存
2. 次回適用時、前回 snapshot との diff(`comm -23`)で **消えたパスを検出**
3. 該当 `$HOME/<path>` を削除してから `chezmoi apply`

これにより Claude Code が `home/` 配下のファイルを `rm` した次回 `mise run apply` で `~/...` 側も自動削除される。`.chezmoiremove` の手書きは不要。

## 機密語コミットブロック

`home/dot_config/git/hooks/private_executable_pre-commit` がグローバル git
`pre-commit`(`core.hooksPath` 経由で全リポ適用)として動作し、`~/.config/git/sensitive-words.txt`
の各パターン(1 行 1 `grep -E`、大小無視)を staged diff に照合してヒット時にコミットを止める。

- **リスト本体は git 管理外**。隠したい文字列の一覧そのものなので公開リポに入れない。
  雛形 `template/sensitive-words.txt.example` のみ commit する。
- 初期配置: `cp template/sensitive-words.txt.example ~/.config/git/sensitive-words.txt`
  して他人のハンドル/個人リポ名・トークン接頭辞などを追記。
- 誤検知時のみ `git commit --no-verify`。リスト不在/staged 空なら素通し。

## macOS システム設定 (defaults / pmset / nvram)

`bin/macos-defaults.sh` が `defaults write` / `pmset` / `nvram` で macOS の **システム側グローバル設定** を一括投入する。chezmoi(`$HOME` 配下のファイル管理)とは別レイヤー。

```sh
mise run macos    # 新マシンで1回実行。sudo パスワード必要。
```

カバー範囲: Finder / Dock / Keyboard / Trackpad / Global UI / 書類ごとの入力ソース / Spotlight ショートカット無効化 / `.DS_Store` 抑止 / 起動音 OFF (nvram)。

bootstrap 時に1回流す想定で、apply の depends には入れていない(毎回走らせると sudo を都度求められるため)。設定追加・変更したい時は `bin/macos-defaults.sh` を直接編集して再実行。

## リポジトリ間の役割分担

| リポ | 担当する `$HOME` 配下 |
|---|---|
| dotfiles(これ) | `~/.zshrc`, `~/.config/nvim/`, `~/.config/tmux/`, `~/.config/ghostty/`, `~/.gitconfig` 等(端末/開発環境設定) |
| cc-dotfiles | `~/.claude/` 配下のみ(Claude Code 設定) |

**target path が重複するファイルを同時管理しないこと**。重複した場合は後勝ち(後に apply された側で上書き)になり、状態が予測不能になる。新ファイルを追加する際はどちらの担当か CLAUDE.md を見て判断する。

## 規約

- **dot_ プレフィックス**: `home/dot_zshrc` → `~/.zshrc`、`home/dot_config/nvim/init.lua` → `~/.config/nvim/init.lua`。chezmoi 標準のリネーム規則。
- **chezmoi のソースルートは `home/`**: `.chezmoiroot` ファイルでそう指示している。リポルート直下のファイル(CLAUDE.md, mise.toml 等)は chezmoi の管理対象外。
- **`~/.config/chezmoi/*.toml` は git 管理外**: 雛形は `template/` に commit するが、実体ファイルにはマシン固有の値(email、業務PCのユーザー名等)が入る可能性があるためローカル専用。
- **state DB は config ごとに分離**: `persistentStateAbsPath` で別ファイルにする(`template/*.toml` でそう設定済)。
- **cc-dotfiles リポの clone 先は固定**: `~/ghq/github.com/Hirayama61/cc-dotfiles`。`mise.toml` の `CC_DOTFILES_DIR` で参照。
- **Brewfile は厳選**: ブートストラップ用 CLI(`mise`)と GUI cask のみ。CLI ツールは原則 chezmoi で扱える設定ファイル管理に寄せ、ツール本体は mise や Homebrew formula で個別に管理する判断は都度行う。

## 新ファイルの追加手順

1. 担当リポを決める(dotfiles か cc-dotfiles)
2. `home/dot_<name>` または `home/dot_config/<tool>/...` として配置
3. `mise run diff` で適用予定を確認
4. `mise run apply` で反映

## テンプレート機能(マシン別出し分け)

chezmoi は Go テンプレートをサポートする。ファイル名末尾に `.tmpl` を付け、内容で `{{ .email }}` のように参照すると、`~/.config/chezmoi/dotfiles.toml` の `[data]` で定義した値が apply 時に展開される。業務PC用の email や API トークンは `[data]` に書いておけば source には絶対に出ない。

例: `home/dot_gitconfig.tmpl`
```
[user]
    email = {{ .email | quote }}
    name = {{ .git_name | quote }}
```

## 新マシン追加

1. Homebrew インストール → `brew install mise`
2. 両リポを `~/ghq/github.com/Hirayama61/{dotfiles,cc-dotfiles}` に clone
3. `cd ~/ghq/github.com/Hirayama61/dotfiles && mise run bootstrap`
4. `~/.config/chezmoi/*.toml` を必要に応じて編集(email 等)
5. `mise run apply`
6. `mise run macos`(macOS のシステム設定を投入)

## オーケストレーション

規約と `delegate` エージェント定義は **グローバル**(`~/.claude/CLAUDE.md` /
`~/.claude/agents/delegate.md`、cc-dotfiles で管理)に定義。全プロジェクト共通。

本リポ固有の点のみ:

- **永続台帳はこのリポの `./TASKS.yaml`**(セッション跨ぎの保留・コミット状態の源)。
  セッション内の作業管理はネイティブの TodoWrite / Task ツールを使う(台帳に写さない)。
- 別件と気づいたら台帳に `held` で記録し、勝手に混ぜてコミットしない
  (例: Panda 作業 と 保留中 LSP 系の分離)。
