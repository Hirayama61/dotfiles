#!/usr/bin/env bats
# bin/wt.sh のフラグ処理(hermetic)。
#
# 検証の焦点は「-/-- 始まりトークンをブランチ名として扱わない」こと:
#   - --help / -h は exit 0 で stdout に Usage を出し、worktree/ブランチを一切作らない
#   - 未知フラグは exit 1 で stderr に Usage を出し、やはり何も作らない
# フラグ処理は git チェックより前なので、一時 repo でも git リポ外でも成立する。
# HOME を一時側へ差し替え、万一の回帰(実 worktree 作成)でも実 ~/worktrees を汚さない。

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

@test "--help: exit 0, prints Usage to stdout, creates no worktree" {
  run bash -c "cd '$REPO' && '$WT' --help"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: "* ]]
  [[ "$output" == *"<branch>"* ]]
  [[ "$output" == *'cd "$(bin/wt.sh feature/x)"'* ]]
  assert_no_worktree_created
}

@test "-h: exit 0, prints Usage to stdout" {
  run bash -c "cd '$REPO' && '$WT' -h"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: "* ]]
  assert_no_worktree_created
}

@test "--help works outside a git repo (before git checks)" {
  run bash -c "cd '$BATS_TEST_TMPDIR' && '$WT' --help"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: "* ]]
}

@test "unknown flag: exit 1, prints Usage to stderr, creates no worktree" {
  run bash -c "cd '$REPO' && '$WT' --frobnicate 2>&1"
  [ "$status" -eq 1 ]
  [[ "$output" == *"不明なオプション"* ]]
  [[ "$output" == *"Usage: "* ]]
  assert_no_worktree_created
}

@test "no args: exit 1, prints Usage" {
  run bash -c "cd '$REPO' && '$WT' 2>&1"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage: "* ]]
}
