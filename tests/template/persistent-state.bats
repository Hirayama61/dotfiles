#!/usr/bin/env bats
# template/*.toml の chezmoi state 分離設定の検証。
#
# 複数 chezmoi config を並列 apply する運用では、state DB(boltdb)を config ごとに
# 分離する必要がある。分離はトップレベルキー `persistentState` で行う。旧実装は
# `[chezmoi]` テーブル配下の `persistentStateAbsPath`(chezmoi に存在しないキー)で、
# 未知キーは黙殺され全 config が既定の共有 state を奪い合ってロック競合していた。
# ここでは template を実際に `chezmoi --config` へ渡し、dump-config の persistentState が
#   (1) dotfiles で非空
#   (2) cc-dotfiles で非空
#   (3) 両者で互いに異なる
# ことを固定する。jq は CI で未 pin のため使わず、grep/sed で値を抜く。
# dump-config は読み取り専用(state DB を生成しない)で sourceDir 不在でも動くため、
# 実マシンの state を汚さない。~ 展開だけ一時 HOME に閉じ込める。

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  DOTFILES_TMPL="$REPO_ROOT/template/dotfiles.toml"
  CC_TMPL="$REPO_ROOT/template/cc-dotfiles.toml"

  # ~ 展開を一時ディレクトリへ閉じ込め、実 $HOME を汚さない。
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"

  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not on PATH"
}

# dump-config の JSON 出力から persistentState の値を抜く(jq 不使用)。
_pstate() {
  chezmoi --config "$1" dump-config 2>/dev/null \
    | grep '"persistentState"' \
    | sed -E 's/.*"persistentState"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/'
}

@test "dotfiles template: persistentState is non-empty" {
  run _pstate "$DOTFILES_TMPL"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "cc-dotfiles template: persistentState is non-empty" {
  run _pstate "$CC_TMPL"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "the two templates use distinct state DBs" {
  local a b
  a="$(_pstate "$DOTFILES_TMPL")"
  b="$(_pstate "$CC_TMPL")"
  [ -n "$a" ]
  [ -n "$b" ]
  [ "$a" != "$b" ]
}

@test "regression: legacy persistentStateAbsPath form yields empty (guards the checks above)" {
  # 誤キー(旧形式)を模した一時 config。chezmoi は未知キーを黙殺するため
  # persistentState は空になる — 上の非空アサートが実際に分離を検出している証。
  local broken="$BATS_TEST_TMPDIR/broken.toml"
  cat >"$broken" <<'TOML'
sourceDir = "/no/such/dir"
[chezmoi]
persistentStateAbsPath = "~/.local/share/chezmoi/dotfiles-state.boltdb"
[data]
TOML
  run _pstate "$broken"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
