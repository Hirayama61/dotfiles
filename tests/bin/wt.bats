#!/usr/bin/env bats
# bin/wt.sh のフラグ処理(hermetic)。
#
# 検証の焦点は「-/-- 始まりトークンをブランチ名として扱わない」ことと、その出力先の契約:
#   - stdout は worktree パス(または --help のヘルプ)だけ、診断・エラーは stderr
#   - --help / -h は exit 0 で stdout に Usage、worktree/ブランチを作らない
#   - 未知フラグは exit 1 で stderr に Usage、stdout は空
#   - 上記はフラグが第2引数でも(全引数走査するため)同じく効く
#   - 正当なブランチ名は for ループを素通りし worktree が作られる(本流の回帰ガード)
# フラグ処理は git チェックより前なので一時 repo でも git リポ外でも成立する。
# HOME を一時側へ差し替え、worktree も一時 HOME 配下に落ちるため実 ~/worktrees を汚さない。

bats_require_minimum_version 1.5.0 # run --separate-stderr のため

setup() {
  export TEST_HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$TEST_HOME"
  export HOME="$TEST_HOME"

  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  WT="$REPO_ROOT/bin/wt.sh"

  export REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO"
  git -C "$REPO" init -q
  git -C "$REPO" config user.email test@example.com
  git -C "$REPO" config user.name test
  git -C "$REPO" remote add origin https://github.com/test/repo.git
  git -C "$REPO" commit -q --allow-empty -m init
}

# repo に main worktree 以外が増えていない & ブランチが初期の1本のままなことを確認
# (回帰時は -/-- 始まりトークンがブランチ化して本数が増える)。
assert_no_worktree_created() {
  [ "$(git -C "$REPO" worktree list --porcelain | grep -c '^worktree ')" -eq 1 ]
  [ "$(git -C "$REPO" for-each-ref --format='x' refs/heads | grep -c x)" -eq 1 ]
}

@test "--help: exit 0, Usage to stdout, stderr empty, no worktree" {
  run --separate-stderr bash -c "cd '$REPO' && '$WT' --help"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: "* ]]
  [[ "$output" == *"<branch>"* ]]
  [[ "$output" == *'cd "$(bin/wt.sh feature/x)"'* ]]
  [ -z "$stderr" ]
  assert_no_worktree_created
}

@test "-h: exit 0, Usage to stdout, stderr empty" {
  run --separate-stderr bash -c "cd '$REPO' && '$WT' -h"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: "* ]]
  [ -z "$stderr" ]
  assert_no_worktree_created
}

@test "--help works outside a git repo (before git checks)" {
  run --separate-stderr bash -c "cd '$BATS_TEST_TMPDIR' && '$WT' --help"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: "* ]]
  [ -z "$stderr" ]
}

@test "--help is recognized in a non-first position too" {
  run --separate-stderr bash -c "cd '$REPO' && '$WT' somebranch --help"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: "* ]]
  assert_no_worktree_created
}

@test "unknown flag: exit 1, Usage to stderr, stdout empty, no worktree" {
  run --separate-stderr bash -c "cd '$REPO' && '$WT' --frobnicate"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"不明なオプション"* ]]
  [[ "$stderr" == *"Usage: "* ]]
  [ -z "$output" ]
  assert_no_worktree_created
}

@test "unknown flag is rejected in a non-first position too" {
  run --separate-stderr bash -c "cd '$REPO' && '$WT' somebranch --frobnicate"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"不明なオプション"* ]]
  [ -z "$output" ]
  assert_no_worktree_created
}

@test "no args: exit 1, Usage to stderr, stdout empty" {
  run --separate-stderr bash -c "cd '$REPO' && '$WT'"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"Usage: "* ]]
  [ -z "$output" ]
}

@test "valid branch: passes the flag loop and creates a worktree (stdout = path only)" {
  # ローカルブランチを先に作り、リモート探索(ネットワーク)を回避してローカル分岐へ入れる。
  git -C "$REPO" branch feature/x
  run --separate-stderr bash -c "cd '$REPO' && '$WT' feature/x"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_HOME/worktrees/github.com/test/repo/feature/x" ]
  [ -d "$output" ]
}
