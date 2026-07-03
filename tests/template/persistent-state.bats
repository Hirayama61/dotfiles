#!/usr/bin/env bats
# template/*.toml の chezmoi「config ごと分離」設定の検証(state DB + cache)。
#
# 複数 chezmoi config を並列 apply する運用では、config ごとに固有の作業領域を
# 持たせないと競合する。分離はいずれもトップレベルキーで行う:
#   - persistentState: state DB(boltdb)。共有すると apply がロックを奪い合う。
#   - cacheDir:        externals 等のキャッシュ。共有すると将来 externals 追加時に
#                      並列 apply で競合しうる(予防的分離)。
# 旧実装は `[chezmoi]` テーブル配下の `persistentStateAbsPath`(chezmoi に存在しない
# キー)で、未知キーは黙殺され全 config が既定の共有 state を奪い合ってロック競合して
# いた。同じ轍を踏まないよう、キーが実際に効くことを dump-config で固定する。
# ここでは template を実際に `chezmoi --config` へ渡し、persistentState / cacheDir が
#   (1) dotfiles で期待の展開後絶対パスに一致
#   (2) cc-dotfiles で期待の展開後絶対パスに一致
#   (3) 両者で互いに異なる
# ことを検証する。jq は CI で未 pin のため使わず、grep/sed で値を抜く。
# dump-config は読み取り専用(state DB を生成しない)で sourceDir 不在でも動くため、
# 実マシンの state を汚さない。~ 展開は $HOME に追従するので一時 HOME に閉じ込める。

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  DOTFILES_TMPL="$REPO_ROOT/template/dotfiles.toml"
  CC_TMPL="$REPO_ROOT/template/cc-dotfiles.toml"

  # ~ 展開を一時ディレクトリへ閉じ込め、実 $HOME を汚さない。
  # chezmoi の ~ 展開は $HOME に追従するため、期待パスも $HOME 起点で組み立てる。
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  EXPECT_STATE_DOTFILES="$HOME/.local/share/chezmoi/dotfiles-state.boltdb"
  EXPECT_STATE_CC="$HOME/.local/share/chezmoi/cc-dotfiles-state.boltdb"
  EXPECT_CACHE_DOTFILES="$HOME/.cache/chezmoi/dotfiles"
  EXPECT_CACHE_CC="$HOME/.cache/chezmoi/cc-dotfiles"

  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not on PATH"
}

# dump-config の JSON 出力から指定キーの文字列値を抜く(jq 不使用)。
# JSON として grep/sed 解析するため `--format=json` を明示し、将来 dump-config の
# 既定形式が変わっても解析が壊れないようにする。pipefail 付きの subshell で、
# chezmoi 失敗・キー行欠落(grep miss)を非ゼロ終了として呼び出し側へ伝える
# (サイレントに空成功へ落とさない)。
# 引数: $1=config パス, $2=キー名(例: persistentState / cacheDir)。
_cfgval() {
  (
    set -o pipefail
    chezmoi --config "$1" dump-config --format=json 2>/dev/null \
      | grep "\"$2\"" \
      | sed -E "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"([^\"]*)\".*/\1/"
  )
}

@test "dotfiles template: persistentState resolves to the expected state DB path" {
  run _cfgval "$DOTFILES_TMPL" persistentState
  [ "$status" -eq 0 ]
  [ "$output" = "$EXPECT_STATE_DOTFILES" ]
}

@test "cc-dotfiles template: persistentState resolves to the expected state DB path" {
  run _cfgval "$CC_TMPL" persistentState
  [ "$status" -eq 0 ]
  [ "$output" = "$EXPECT_STATE_CC" ]
}

@test "the two templates use distinct state DBs" {
  local a b
  a="$(_cfgval "$DOTFILES_TMPL" persistentState)"
  b="$(_cfgval "$CC_TMPL" persistentState)"
  [ -n "$a" ]
  [ -n "$b" ]
  [ "$a" != "$b" ]
}

@test "dotfiles template: cacheDir resolves to the expected per-config path" {
  run _cfgval "$DOTFILES_TMPL" cacheDir
  [ "$status" -eq 0 ]
  [ "$output" = "$EXPECT_CACHE_DOTFILES" ]
}

@test "cc-dotfiles template: cacheDir resolves to the expected per-config path" {
  run _cfgval "$CC_TMPL" cacheDir
  [ "$status" -eq 0 ]
  [ "$output" = "$EXPECT_CACHE_CC" ]
}

@test "the two templates use distinct cache dirs" {
  local a b
  a="$(_cfgval "$DOTFILES_TMPL" cacheDir)"
  b="$(_cfgval "$CC_TMPL" cacheDir)"
  [ -n "$a" ]
  [ -n "$b" ]
  [ "$a" != "$b" ]
}

@test "regression: legacy persistentStateAbsPath form yields empty (guards the state checks)" {
  # 誤キー(旧形式)を模した一時 config。chezmoi は未知キーを黙殺するため
  # persistentState は空文字で出力される(行自体は存在するので grep は当たる)。
  # 上の完全一致アサートが実際に分離を検出している証。
  local broken="$BATS_TEST_TMPDIR/broken.toml"
  cat >"$broken" <<'TOML'
sourceDir = "/no/such/dir"
[chezmoi]
persistentStateAbsPath = "~/.local/share/chezmoi/dotfiles-state.boltdb"
[data]
TOML
  run _cfgval "$broken" persistentState
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "regression: cacheDir under [chezmoi] falls back to the shared default (guards the cache checks)" {
  # cacheDir をトップレベルでなく [chezmoi] 配下に誤置すると、未知キーとして黙殺され
  # 共有既定 ~/.cache/chezmoi に落ちる(config ごとの分離が効かない)。完全一致アサートが
  # この誤りを検出できることを固定する。
  local broken="$BATS_TEST_TMPDIR/broken-cache.toml"
  cat >"$broken" <<'TOML'
sourceDir = "/no/such/dir"
[chezmoi]
cacheDir = "~/.cache/chezmoi/dotfiles"
[data]
TOML
  run _cfgval "$broken" cacheDir
  [ "$status" -eq 0 ]
  [ "$output" = "$HOME/.cache/chezmoi" ]
  [ "$output" != "$EXPECT_CACHE_DOTFILES" ]
}
