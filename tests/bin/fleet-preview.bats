#!/usr/bin/env bats
# fleet-preview.sh の描画契約を固定する。
#
# hermetic: XDG_STATE_HOME を $BATS_TEST_TMPDIR 配下に差し替え、実 ~/.local/state に
# 触れない(スクリプトの実解決 ${XDG_STATE_HOME:-$HOME/.local/state}/claude-fleet を
# 経由することの検証を兼ねる)。fixture の JSON スキーマは home-claude-drive/SKILL.md §2
# (cc-dotfiles)が正典 — フィールドを変える時は跨リポで揃えること。
#
# 検証: --help の stdout/stderr 分離 / --once の表示順(waiting-human 先頭)/
# 壊れ JSON の skip + stderr 警告 / 状態 dir 不在の fail-open。

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
  SCRIPT="$REPO_ROOT/bin/fleet-preview.sh"
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  TASKS="$XDG_STATE_HOME/claude-fleet/tasks"
  mkdir -p "$TASKS"
}

write_task() {
  # $1=id $2=status $3=title
  cat >"$TASKS/$1.json" <<EOF
{
  "id": "$1",
  "title": "$3",
  "repo": "dotfiles",
  "branch": "feat/x",
  "worktree": "",
  "tmux_window": "@1",
  "window_name": "$1",
  "tmux_pane": "%1",
  "status": "$2",
  "phase": "impl",
  "context_pct": 10,
  "next_action": "act-$1",
  "updated_at": "2026-07-22T12:00:00+09:00"
}
EOF
}

@test "--help: help goes to stdout, nothing to stderr, exit 0" {
  run --separate-stderr bash "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  [ -z "$stderr" ]
}

@test "unknown option: usage goes to stderr, exit 1" {
  run --separate-stderr bash "$SCRIPT" --bogus
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"Usage:"* ]]
}

@test "--once: waiting-human renders before running (top placement)" {
  write_task aaa-running running "走行中タスク"
  write_task zzz-waiting waiting-human "判断待ちタスク"
  run --separate-stderr bash "$SCRIPT" --once
  [ "$status" -eq 0 ]
  [[ "$output" == *"判断待ちタスク"* ]]
  [[ "$output" == *"走行中タスク"* ]]
  wait_line="$(printf '%s\n' "$output" | grep -n '判断待ちタスク' | cut -d: -f1 | head -1)"
  run_line="$(printf '%s\n' "$output" | grep -n '走行中タスク' | cut -d: -f1 | head -1)"
  [ "$wait_line" -lt "$run_line" ]
}

@test "--once: broken JSON is skipped with exactly one stderr warning, valid tasks still render" {
  write_task ok-task running "正常タスク"
  echo '{ broken' >"$TASKS/broken.json"
  run --separate-stderr bash "$SCRIPT" --once
  [ "$status" -eq 0 ]
  [[ "$output" == *"正常タスク"* ]]
  [ "$(printf '%s\n' "$stderr" | grep -c 'broken.json')" -eq 1 ]
}

@test "--once: control chars (ESC) in JSON strings are stripped before rendering" {
  printf '%s\n' '{"id":"esc","title":"a\u001b[31mEVILb","repo":"dotfiles","status":"running","window_name":"esc","next_action":"n","context_pct":1,"updated_at":"2026-07-22T12:00:00+09:00"}' >"$TASKS/esc.json"
  run --separate-stderr bash "$SCRIPT" --once
  [ "$status" -eq 0 ]
  [[ "$output" == *"a[31mEVILb"* ]]
  esc_char="$(printf '\033')"
  [[ "$output" != *"${esc_char}[31m"* ]]
}

@test "invalid FLEET_PREVIEW_INTERVAL fails fast with a clear error" {
  run --separate-stderr env FLEET_PREVIEW_INTERVAL=0 bash "$SCRIPT" --once
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"FLEET_PREVIEW_INTERVAL"* ]]
}

@test "--once: missing tasks dir is fail-open (no error, empty notice)" {
  rm -rf "$XDG_STATE_HOME"
  run --separate-stderr bash "$SCRIPT" --once
  [ "$status" -eq 0 ]
  [[ "$output" == *"タスクなし"* ]]
}

@test "--once: done tasks are not rendered" {
  write_task done-task done "完了タスク"
  write_task live-task running "生存タスク"
  run --separate-stderr bash "$SCRIPT" --once
  [ "$status" -eq 0 ]
  [[ "$output" == *"生存タスク"* ]]
  [[ "$output" != *"完了タスク"* ]]
}

@test "--once: empty string fields (undispatched backlog) keep column alignment" {
  cat >"$TASKS/empty-fields.json" <<'JSON'
{"id":"empty-fields","title":"backlog-task","repo":"dotfiles","branch":"","worktree":"","tmux_window":"","window_name":"","tmux_pane":"","status":"backlog","phase":"idea","context_pct":0,"next_action":"act-empty","updated_at":"2026-07-22T12:00:00+09:00"}
JSON
  run --separate-stderr bash "$SCRIPT" --once
  [ "$status" -eq 0 ]
  row="$(printf '%s\n' "$output" | grep 'backlog-task')"
  [[ "$row" == *"act-empty"* ]]
  # 旧バグ: 空 window_name の潰れで右の列が左へずれ込み、生 timestamp が行に露出する
  [[ "$row" != *"2026-07-22T"* ]]
  [[ "$row" == *" - "* ]]
  [[ "$row" == *"0%"* ]]
}
