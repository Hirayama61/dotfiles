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
│   ├── cc-dotfiles.toml           # ~/.config/chezmoi/cc-dotfiles.toml の雛形
│   └── sensitive-words.txt.example # 機密語リストの雛形(実体は git 管理外)
├── bin/
│   ├── sync.sh                    # 削除自動化付き chezmoi apply ラッパー
│   ├── skills-sync.sh             # 外部 skill(ext-skills.txt)+ ローカル進化(active/)を symlink 同期
│   ├── chezmoi-source.sh          # chezmoi source パス解決の単一情報源(sync.sh / mise run diff が使用)
│   ├── macos-defaults.sh          # macOS システム設定の一括投入(mise run macos)
│   ├── wt.sh                      # フラット worktree 作成ヘルパ(worktree 規約の正規経路)
│   ├── lib/                       # wt.sh と WorktreeCreate hook(cc-dotfiles 側)が共有するパス導出ライブラリ
│   ├── demo.sh                    # README 用デモ収録スクリプト
│   └── demo/                      # デモ収録の素材(claude-prompt.txt 等)
├── .claude/                       # このリポ作業時の Claude Code プロジェクト設定(~/.claude/ のグローバル設定とは別)
├── ext-skills.txt                 # 外部 agent skill のマニフェスト(1 行 1 skill)
├── Brewfile                       # mise(bootstrap CLI) + GUI cask のみ
├── mise.toml                      # 全タスクの入口
└── CLAUDE.md / README.md / LICENSE

~/ghq/github.com/Hirayama61/cc-dotfiles/   # 別リポ(運用中。Claude Code 設定を管理)
├── .chezmoiroot
└── home/dot_claude/...            # ~/.claude/... を管理

~/.config/chezmoi/                 # ローカル限定(どちらのリポにも入らない)
├── dotfiles.toml                  # sourceDir, persistentState, [data]
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
mise run update           # 両リポ git pull → apply → 新規ツール install
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
- **state DB / cache は config ごとに分離**: トップレベルキー `persistentState`(state DB)と `cacheDir`(externals 等のキャッシュ)で別パスにする(`template/*.toml` でそう設定済)。どちらも `[chezmoi]` 配下ではなくトップレベルに置くこと(誤ってテーブル配下に書くと未知キーとして黙殺され、共有既定を奪い合って並列 apply が競合する)。
- **cc-dotfiles リポの clone 先は固定**: `~/ghq/github.com/Hirayama61/cc-dotfiles`。`mise.toml` の `CC_DOTFILES_DIR` で参照。
- **Brewfile は厳選**: ブートストラップ用 CLI(`mise`)と GUI cask のみ。CLI ツールは原則 chezmoi で扱える設定ファイル管理に寄せ、ツール本体は mise や Homebrew formula で個別に管理する判断は都度行う。

## 新ファイルの追加手順

1. 担当リポを決める(dotfiles か cc-dotfiles)
2. `home/dot_<name>` または `home/dot_config/<tool>/...` として配置
3. `mise run diff` で適用予定を確認
4. `mise run apply` で反映

## テンプレート機能(マシン別出し分け)

chezmoi は Go テンプレートをサポートする。ファイル名末尾に `.tmpl` を付け、内容で `{{ .email }}` のように参照すると、`~/.config/chezmoi/dotfiles.toml` の `[data]` で定義した値が apply 時に展開される。業務PC用の email や API トークンは `[data]` に書いておけば source には絶対に出ない。

例: `home/dot_config/git/config.tmpl`(共有 gitconfig 本体。`~/.config/git/config` に展開)
```
[user]
    name = {{ .git_name }}
    email = {{ .email }}
```
git config --global の端末ローカル書込(CodeRabbit の machineId 等)は、初回のみ生成される include shim `home/create_dot_gitconfig`(→ `~/.gitconfig`)が `~/.config/git/config` を include する形で吸収し、公開リポ管理下から隔離している。

## 新マシン追加

1. Homebrew インストール → `brew install mise`
2. 両リポを `~/ghq/github.com/Hirayama61/{dotfiles,cc-dotfiles}` に clone
3. `cd ~/ghq/github.com/Hirayama61/dotfiles && mise run bootstrap`
4. `~/.config/chezmoi/*.toml` を必要に応じて編集(email 等)
5. `mise run apply`
6. `mise run macos`(macOS のシステム設定を投入)

## 外部 skill 管理 (ext-skills)

Claude Code の agent skill のうち**外部リポ由来**のものは、リポに vendoring せず `ext-skills.txt` のマニフェストで宣言し symlink で取り込む。

```sh
mise run skills:sync   # ext-skills.txt を読み ghq clone/更新 → ~/.claude/skills へ symlink
```

- `ext-skills.txt` は 1 行 1 skill。3 形態(`owner/repo:subdir` / `owner/repo/path/to/skill` / `owner/repo`)で複数 or 単体 skill を解釈する(記法はファイル冒頭コメント参照)。
- `bin/skills-sync.sh` が `ghq get -u` で取得し `~/.claude/skills/<name>` へ symlink。マニフェストから外れた symlink は prune する(chezmoi 管理の実体ディレクトリには触れない)。
- `bin/skills-sync.sh --check` は宣言 ↔ symlink の照合だけを行う(ghq もネットワークも呼ばず副作用ゼロ。`missing` / `mismatch` / `invalid` のいずれかがあれば exit 1)。skill 名の存在だけでなく **symlink の向き先**も見る(`readlink` の末尾を `github.com/<owner/repo>/<path>` と照合。同名 skill をローカル進化が上書きしている状態は仕様どおりなので通す)。**末尾一致なので同じ末尾を持つ任意のパスは通る** — 捕まえられるのは宣言の陳腐化・upstream のパス移動・別 owner の同名 skill への取り違えであって、`~/.claude/skills` に書ける相手による意図的な差し替えではない。単体形態(`owner/repo/path/to/skill`)は宣言だけで skill 名が決まるため照合できるが、複数形態(`owner/repo` / `owner/repo:subdir`)は clone の列挙が要るため `skipped` として件数だけ出す。
- 同期の末尾サマリー `unmanaged=<n>` は、`~/.claude/skills`・`~/.claude/agents` にあって symlink でも chezmoi ソース由来でもない実体の件数。報告のみで削除はしない。**突合は source name と target name の完全一致**なので、属性 prefix(`private_` / `exact_` 等)や `.tmpl` が付いた chezmoi 管理エントリは**管理外として誤報告される**。突合先の chezmoi ソース(`$CC_DOTFILES_DIR/home/dot_claude`)が無いときは検出自体を行わず `unmanaged=skipped(...)` と出す(「検査して 0 件」と区別するため)。未 clone だけでなくレイアウト変更・sparse checkout もここに入る — 突合先が無いまま走らせると chezmoi 管理下の実体まで全件「管理外」に化けるため。
- **`--check` は収束判定のゲートには使えない**。見るのは「宣言された skill が張られているか」の一方向だけで、逆向き — 承認済みのローカル進化が `ext-skills.txt` 側の skill を上書きすべきなのに、リンクがまだ ghq 側を指したまま — は緑で通る(次の全量同期で張り替わる)。「`--check` が緑 = 同期済み」と読まない。
- **手で張った symlink の扱いは skills と agents で非対称**。skills 側の prune は宣言集合から外れた symlink を一律に刈るので `pruned:` に出て消える。agents 側の prune はリンク先がローカル進化配下のものだけを刈るため手張りは残り、`unmanaged` にも入らないのでどこにも現れない。
- symlink は再配布ではない(本体は ghq clone でローカルに置く)ため LICENSE 同梱不要。
- `~/.claude/skills/` には cc-dotfiles が実体管理する skill(`obsidian-memory` 等)と ext-skills 経由 symlink の skill が混在する。**外部 skill は vendoring せず symlink** が原則(例: `defuddle` は `kepano/obsidian-skills` から取り込む)。

## ローカル進化 (claude-evolution)

このマシンだけで使う skill/agent は、**git 管理外・マシンローカル**の
`~/.claude-evolution/` に置く(業務知識を git に載せないための分離)。

- `~/.claude-evolution/active/` に置いた skill/agent を `bin/skills-sync.sh` が
  `~/.claude/skills`・`~/.claude/agents` へ symlink する。`candidates/` 配下は対象外で、
  active/ へ移すまで効力を持たない。
- `bin/skills-sync.sh --local-only` は ghq 同期と prune をスキップし、ローカル進化だけを
  張り直す軽量モード(ネットワークを使わない。prune しないので外部 skill の symlink は
  消えないが、同名のローカル進化があるとその名前だけ張り替わる)。
- 作成側の衝突ガード: 宛先が実体(chezmoi 管理)のときは WARN + skip し、実体を symlink で
  上書きしない。prune は従来どおり symlink のみ対象。

## オーケストレーション

規約と `delegate` エージェント定義は **グローバル**(`~/.claude/CLAUDE.md` /
`~/.claude/agents/delegate.md`、cc-dotfiles で管理)に定義。全プロジェクト共通。
