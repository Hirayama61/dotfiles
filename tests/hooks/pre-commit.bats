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

# 一致行は staged 内容そのもの。secretlint 側と対称に落とさないと、こちらだけ
# ESC を通してブロック表示を偽装できる。
@test "terminal control characters are stripped from the sensitive-word match output" {
  write_words 'SECRET_TOKEN'
  stage_file config.txt "$(printf 'SECRET_TOKEN=abc\033[2Kspoofed')"
  run_precommit
  [ "$status" -eq 1 ]
  [[ "$output" == *"spoofed"* ]]
  [[ "$output" != *$'\033'* ]]
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
  [[ "$output" == *"exit 1"* ]]
}

# 走らなかったコミットを通すと、ガードが効いていないことに誰も気付けない。
# 非 0 は検出と実行失敗を区別せず止める。
@test "secretlint execution failure (exit 2) also blocks the commit" {
  enable_secretlint 2
  write_words 'NOSUCHSECRET_XYZ'
  stage_file note.txt "hello"
  run_precommit
  [ "$status" -eq 1 ]
  [[ "$output" == *"exit 2"* ]]
}

@test "secretlint clean run (exit 0) passes without warning" {
  enable_secretlint 0
  write_words 'NOSUCHSECRET_XYZ'
  stage_file note.txt "hello"
  run_precommit
  [ "$status" -eq 0 ]
  [[ "$output" != *"secretlint"* ]]
}

# 設定不在は「検査できない」であって「検出した」ではない。dotfiles 未適用の
# マシンでコミットを止めないため、ここだけは警告して素通しする。
@test "missing ~/.secretlintrc.json warns and skips the scan" {
  enable_secretlint 1
  rm -f "$HOME/.secretlintrc.json"
  write_words 'NOSUCHSECRET_XYZ'
  stage_file note.txt "hello"
  run_precommit
  [ "$status" -eq 0 ]
  [[ "$output" == *".secretlintrc.json がありません"* ]]
}

@test "secretlint receives the staged paths, the rc path and the guard options" {
  enable_secretlint 0
  fake_secretlint_reporting 0 ''
  write_words 'NOSUCHSECRET_XYZ'
  stage_file note.txt "hello"
  run_precommit
  [ "$status" -eq 0 ]
  run cat "$BATS_TEST_TMPDIR/secretlint-argv"
  [[ "$output" == *"--secretlintrc $HOME/.secretlintrc.json"* ]]
  # 除外リストを固定しないと、リポ直下の .secretlintignore に ** を書くだけで
  # ガードが無音で全無効化される(rc を固定した理由がそのまま残る)。
  [[ "$output" == *"--secretlintignore /dev/null"* ]]
  [[ "$output" == *"--no-gitignore"* ]]
  [[ "$output" == *"--no-glob"* ]]
  [[ "$output" == *"-- note.txt"* ]]
}

# 何が引っかかったか分からないと直しようがないので、検出内容を握り潰さない。
@test "detection output is forwarded to the developer" {
  enable_secretlint 1
  fake_secretlint_reporting 1 'note.txt 1:7 error [GITHUB_TOKEN] found'
  write_words 'NOSUCHSECRET_XYZ'
  stage_file note.txt "hello"
  run_precommit
  [ "$status" -eq 1 ]
  [[ "$output" == *"[GITHUB_TOKEN] found"* ]]
}

# 出力は staged ファイルの内容由来。ESC を通すと直後のブロック表示を偽装できる。
@test "terminal control characters are stripped from the forwarded output" {
  enable_secretlint 1
  fake_secretlint_reporting 1 'note.txt \033[2Kspoofed'
  write_words 'NOSUCHSECRET_XYZ'
  stage_file note.txt "hello"
  run_precommit
  [ "$status" -eq 1 ]
  [[ "$output" == *"spoofed"* ]]
  [[ "$output" != *$'\033'* ]]
}

# git mv してから秘密を書き足す経路。機密語ガード(ACMR)と対象を揃える。
@test "renamed files are included in the scan" {
  enable_secretlint 0
  fake_secretlint_reporting 0 ''
  write_words 'NOSUCHSECRET_XYZ'
  # 1 行ファイルを rename すると git は類似度を取れず A + D として記録するため、
  # R を落としても ACM で拾えてしまい R の扱いを固定できない。R と判定される
  # 程度の行数を持たせる。追加行が無いと機密語ガードの早期 return で hook ごと
  # 終わるので、rename に内容変更も伴わせる(秘密を書き足す実際の経路と同じ形)。
  printf 'line %s\n' 1 2 3 4 5 6 7 8 9 10 >"$REPO/old.txt"
  git -C "$REPO" add old.txt
  commit_repo "seed"
  git -C "$REPO" mv old.txt new.txt
  printf 'line %s\n' 1 2 3 4 5 6 7 8 9 10 11 >"$REPO/new.txt"
  git -C "$REPO" add new.txt

  run git -C "$REPO" diff --cached --name-status
  [[ "$output" == R* ]]

  run_precommit
  [ "$status" -eq 0 ]
  run cat "$BATS_TEST_TMPDIR/secretlint-argv"
  [[ "$output" == *"new.txt"* ]]
}
