#!/usr/bin/env bats
# commit-msg(機密語ガード + Conventional Commits 検証)の E2E。
# E-C1(不正 ERE fail-closed)/ E-C2(CRLF)を固定しつつ、CC 検証の現行挙動も characterize する。

load ../helpers/common

setup() {
  setup_repo
}

@test "valid conventional message without secret: passes" {
  write_words 'SECRET_TOKEN'
  run_commitmsg "feat: 新機能を追加"
  [ "$status" -eq 0 ]
}

@test "non-conventional message is blocked (CC validation)" {
  write_words 'SECRET_TOKEN'
  run_commitmsg "just some message"
  [ "$status" -eq 1 ]
}

@test "merge commit message is skipped" {
  write_words 'SECRET_TOKEN'
  run_commitmsg "Merge branch 'main' into feature"
  [ "$status" -eq 0 ]
}

@test "secret in commit message is blocked" {
  write_words 'SECRET_TOKEN'
  run_commitmsg "fix: oops SECRET_TOKEN=abc123"
  [ "$status" -eq 1 ]
}

@test "E-C2: CRLF in words file still blocks message" {
  write_words 'SECRET_TOKEN\r\n'
  run_commitmsg "fix: oops SECRET_TOKEN=abc123"
  [ "$status" -eq 1 ]
}

@test "E-C1: invalid regex pattern aborts fail-closed" {
  write_words 'foo(bar'
  run_commitmsg "feat: normal message"
  [ "$status" -eq 1 ]
  [[ "$output" == *"不正な正規表現"* ]]
}
