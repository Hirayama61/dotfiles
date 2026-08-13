#!/usr/bin/env bats
# pre-push の E2E。この hook はグローバル側の検査を持たず、core.hooksPath の
# グローバル設定で git がバイパスするリポ固有 hook を代わりに起動するのが役割。
# 委譲先の優先順(husky → lefthook → .git/hooks)と、引数・stdin・終了コードが
# そのまま引き継がれることを固定する。

load ../helpers/common

setup() {
  setup_repo
}

# 実行された事実と受け取った引数を出力するローカル hook を置く。
write_local_hook() {
  local path="$1" label="$2" exit_code="${3:-0}"
  mkdir -p "$(dirname "$REPO/$path")"
  cat >"$REPO/$path" <<SH
#!/bin/sh
echo "$label \$1 \$2"
cat
exit $exit_code
SH
  chmod +x "$REPO/$path"
}

@test "no local hook: passes without blocking the push" {
  run_prepush
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "husky pre-push is executed" {
  write_local_hook .husky/pre-push HUSKY
  run_prepush
  [ "$status" -eq 0 ]
  [[ "$output" == *"HUSKY"* ]]
}

@test "local .git/hooks/pre-push is executed" {
  write_local_hook .git/hooks/pre-push LOCAL
  run_prepush
  [ "$status" -eq 0 ]
  [[ "$output" == *"LOCAL"* ]]
}

@test "husky takes precedence over .git/hooks" {
  write_local_hook .husky/pre-push HUSKY
  write_local_hook .git/hooks/pre-push LOCAL
  run_prepush
  [[ "$output" == *"HUSKY"* ]]
  [[ "$output" != *"LOCAL"* ]]
}

@test "lefthook runs when its config exists" {
  printf 'pre-push:\n' >"$REPO/lefthook.yml"
  cat >"$MISE_SHIM_DIR/lefthook" <<'SH'
#!/usr/bin/env bash
echo "LEFTHOOK $*"
SH
  chmod +x "$MISE_SHIM_DIR/lefthook"
  run_prepush
  [ "$status" -eq 0 ]
  [[ "$output" == *"LEFTHOOK run pre-push"* ]]
}

@test "remote name and url are passed through to the local hook" {
  write_local_hook .git/hooks/pre-push LOCAL
  run_prepush
  [[ "$output" == *"LOCAL origin https://example.invalid/repo.git"* ]]
}

# push 対象の ref は stdin 経由でしか渡らない。exec 委譲で fd が引き継がれることを見る。
@test "stdin refs reach the local hook" {
  write_local_hook .git/hooks/pre-push LOCAL
  run_prepush "refs/heads/main 0000 refs/heads/main 1111"
  [[ "$output" == *"refs/heads/main 0000"* ]]
}

@test "a failing local hook blocks the push" {
  write_local_hook .git/hooks/pre-push LOCAL 1
  run_prepush
  [ "$status" -eq 1 ]
}

# linked worktree では --git-dir が .git/worktrees/<名前> を指し hooks/ を持たない。
# 判定を誤ると worktree 内の push で委譲が黙って止まる(このリポは worktree 運用)。
@test "linked worktree: the hook under the common git dir is executed" {
  write_local_hook .git/hooks/pre-push LOCAL
  stage_file seed.txt "hello"
  commit_repo "seed"
  git -C "$REPO" worktree add -q "$BATS_TEST_TMPDIR/wt" -b wt-branch
  run_prepush_at "$BATS_TEST_TMPDIR/wt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"LOCAL"* ]]
}

# lefthook.yml はあるがバイナリが PATH に無い場合。mise 側の解決へ回る。
@test "lefthook resolved through mise when not on PATH" {
  printf 'pre-push:\n' >"$REPO/lefthook.yml"
  cat >"$MISE_SHIM_DIR/lefthook" <<'SH'
#!/usr/bin/env bash
echo "LEFTHOOK_VIA_MISE $*"
SH
  chmod +x "$MISE_SHIM_DIR/lefthook"

  # shim dir が PATH 上にあると command -v lefthook が先に当たる。mise だけを別 dir で
  # PATH に残し、lefthook は mise which/exec 経由でしか解決できない状態にする。
  mise_only="$BATS_TEST_TMPDIR/misebin"
  mkdir -p "$mise_only"
  ln -s "$MISE_SHIM_DIR/mise" "$mise_only/mise"
  export PATH="$mise_only:$(dirname "$(command -v git)"):/usr/bin:/bin"

  run_prepush_at "$REPO"
  [ "$status" -eq 0 ]
  [[ "$output" == *"LEFTHOOK_VIA_MISE run pre-push"* ]]
}

# lefthook.yml はあるがどちらの経路でも見つからない場合は .git/hooks へ落ちる。
@test "falls through to .git/hooks when lefthook is unavailable" {
  printf 'pre-push:\n' >"$REPO/lefthook.yml"
  write_local_hook .git/hooks/pre-push LOCAL
  run_prepush
  [ "$status" -eq 0 ]
  [[ "$output" == *"LOCAL"* ]]
}
