#!/usr/bin/env bats
# pre-commit の E2E。PR-D1 で採用した findings の再現入力を固定する:
# E-C1(不正 ERE fail-closed)/ E-C2(CRLF)/ E-H1(shfmt 失敗ガード)/ E-H2(追加行限定)。
# スコープは機密語ガードと shfmt ガード段。secretlint / shellcheck の block 経路は
# hermetic shim では skip される(本 PR の対象外。実ツールでの検証は mise run lint が担う)。

load ../helpers/common

setup() {
  setup_repo
}

@test "no words file: passes" {
  rm -f "$HOME/.config/git/sensitive-words.txt"
  stage_file note.txt "hello"
  run_precommit
  [ "$status" -eq 0 ]
}

@test "no sensitive word in added lines: passes" {
  write_words 'SECRET_TOKEN'
  stage_file note.txt "just a normal note"
  run_precommit
  [ "$status" -eq 0 ]
}

@test "adding a line containing a secret is blocked" {
  write_words 'SECRET_TOKEN'
  stage_file config.txt "SECRET_TOKEN=abc123"
  run_precommit
  [ "$status" -eq 1 ]
}

@test "E-H2: removing a line containing a secret is not blocked (added lines only)" {
  write_words 'SECRET_TOKEN'
  printf '%s\n' "SECRET_TOKEN=abc123" "keep=1" >"$REPO/config.txt"
  git -C "$REPO" add config.txt
  commit_repo "seed"
  printf '%s\n' "keep=1" >"$REPO/config.txt"
  git -C "$REPO" add config.txt
  run_precommit
  [ "$status" -eq 0 ]
}

@test "E-H2: a secret only in the diff header path is not matched" {
  write_words 'topsecret'
  stage_file "dir/topsecret/note.txt" "harmless content"
  run_precommit
  [ "$status" -eq 0 ]
}

@test "E-C2: CRLF in words file still blocks" {
  write_words 'SECRET_TOKEN\r\n'
  stage_file config.txt "SECRET_TOKEN=abc123"
  run_precommit
  [ "$status" -eq 1 ]
}

@test "E-C1: invalid regex pattern aborts fail-closed" {
  write_words 'foo(bar'
  stage_file note.txt "hello world"
  run_precommit
  [ "$status" -eq 1 ]
  [[ "$output" == *"不正な正規表現"* ]]
}

@test "E-H1: shfmt failure on a .sh warns and does not crash silently" {
  fake_tool shfmt 1
  write_words 'NOSUCHSECRET_XYZ'
  stage_file bad.sh 'echo hi'
  run_precommit
  [[ "$output" == *"整形に失敗"* ]]
  [ "$status" -eq 0 ]
}

@test "E-H1: shfmt success re-stages the formatted file" {
  fake_shfmt_rewrites
  write_words 'NOSUCHSECRET_XYZ'
  stage_file ok.sh 'echo hi'
  run_precommit
  [ "$status" -eq 0 ]
  [[ "$output" != *"整形に失敗"* ]]
  # 整形結果が staged に再反映されている(git add 経路)ことを観測する。
  run git -C "$REPO" show :ok.sh
  [[ "$output" == *"FORMATTED"* ]]
}
