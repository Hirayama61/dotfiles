#!/usr/bin/env bats
# pre-commit の E2E。PR-D1 で採用した findings の再現入力を固定する:
# E-C1(不正 ERE fail-closed)/ E-C2(CRLF)/ E-H1(shfmt 失敗ガード)/ E-H2(追加行限定)。
# スコープは機密語ガード / shfmt / secretlint の各段。shellcheck の block 経路は
# hermetic shim では skip される(実ツールでの検証は mise run lint が担う)。

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

@test "E-H2: an added line whose content starts with ++ is still scanned (not mistaken for a header)" {
  # diff 上は `++++SECRET...`。ヘッダ除外を `^+++` で広く取ると誤除外し漏れる(CodeRabbit PR#79)。
  write_words 'SECRET_TOKEN'
  stage_file config.txt "++SECRET_TOKEN=abc123"
  run_precommit
  [ "$status" -eq 1 ]
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

@test "secretlint detection (exit 1) blocks the commit" {
  enable_secretlint 1
  write_words 'NOSUCHSECRET_XYZ'
  stage_file note.txt "hello"
  run_precommit
  [ "$status" -eq 1 ]
  [[ "$output" == *"秘密情報を検出"* ]]
}

# secretlint は .secretlintrc 不在で exit 2 になる。ここを block 扱いにすると
# 設定を置き忘れた全リポでコミットが止まるため、素通しであることを固定する。
@test "secretlint execution failure (exit 2) warns and passes" {
  enable_secretlint 2
  write_words 'NOSUCHSECRET_XYZ'
  stage_file note.txt "hello"
  run_precommit
  [ "$status" -eq 0 ]
  [[ "$output" == *"secretlint を実行できませんでした(exit 2)"* ]]
  [[ "$output" != *"秘密情報を検出"* ]]
}

@test "secretlint clean run (exit 0) passes without warning" {
  enable_secretlint 0
  write_words 'NOSUCHSECRET_XYZ'
  stage_file note.txt "hello"
  run_precommit
  [ "$status" -eq 0 ]
  [[ "$output" != *"secretlint"* ]]
}
