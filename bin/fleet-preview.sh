#!/usr/bin/env bash
# fleet-preview.sh — claude-fleet タスク一覧のプレビュー描画。
#
# home-claude-drive(cc-dotfiles 管理の統括 skill)が書く fleet 状態ディレクトリ
# (1 タスク = 1 JSON)を読み、人間向けの一覧表を描画する。tmux ホーム window の
# 右 pane で常駐させる想定(トークンを消費しない素のシェル)。
#
# path 解決とスキーマの正典は home-claude-drive/SKILL.md §2(跨リポ契約)。
# 本スクリプトは canon の逐語ミラー: FLEET_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/claude-fleet"
#
# 読み取り専用: 壊れ JSON・読取中に消えたファイル(glob→mv race)は skip して
# stderr に警告 1 行/ファイル(fail-open)。隔離・修復は home 側の専権で、ここでは行わない。
# JSON はエージェント由来の untrusted テキストとして扱い、描画前に jq の [[:cntrl:]] で
# 制御文字(C0/C1/DEL。フィールド内タブ含む)を除去する(端末エスケープ注入と
# TSV 列ずれの防止。クラス内の \uXXXX は jq の Oniguruma が解釈しない実測により POSIX クラスを使う)。
#
# 出力契約: 描画は stdout、診断・警告は stderr。
# 表示順: waiting-human(赤・最上段)→ running → blocked → backlog。done/ は表示しない。
# 既知の見た目制限: printf のパディングはバイト幅のため、日本語 title で列がずれる。
#
# 依存: jq(runtime は system jq を想定。macOS 15+ 同梱。無ければ明示エラー)。
set -euo pipefail

PROG="${0##*/}"
FLEET_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/claude-fleet"
INTERVAL="${FLEET_PREVIEW_INTERVAL:-2}"

usage() {
  echo "Usage: $PROG [--once] [--help]"
}

print_help() {
  usage
  cat <<'EOF'

claude-fleet のタスク状態(1 タスク = 1 JSON)を一覧描画する。

オプション:
  --once    1 回描画して終了する(既定は 2 秒間隔で再描画し続ける)
  -h, --help このヘルプを表示する

環境変数:
  XDG_STATE_HOME          状態ディレクトリの基点(既定 ~/.local/state)
  FLEET_PREVIEW_INTERVAL  再描画間隔秒(正の整数。既定 2)

例:
  fleet-preview.sh          # tmux の右 pane で常駐させる
  fleet-preview.sh --once   # 現在の一覧を 1 回だけ出す
EOF
}

ONCE=0
for arg in "$@"; do
  case "$arg" in
  -h | --help)
    print_help
    exit 0
    ;;
  --once) ONCE=1 ;;
  -*)
    echo "$PROG: 不明なオプション: $arg" >&2
    usage >&2
    exit 1
    ;;
  *)
    echo "$PROG: 引数は取らない: $arg" >&2
    usage >&2
    exit 1
    ;;
  esac
done

case "$INTERVAL" in
"" | 0 | *[!0-9]*)
  echo "$PROG: FLEET_PREVIEW_INTERVAL は正の整数にする: '$INTERVAL'" >&2
  exit 1
  ;;
esac

if ! command -v jq >/dev/null 2>&1; then
  echo "$PROG: jq が必要(macOS 15+ に同梱。無ければ mise か brew で導入)" >&2
  exit 1
fi

# 経過時間の人間表示(bash 3.2 互換・BSD date)。updated_at は ISO8601。
# TZ オフセット込みで解釈する(+HH:MM は %z が読める +HHMM へ、Z は +0000 へ変換)。
# パース不能は "?"(fail-open)。
age_of() {
  t="$1"
  case "$t" in
  *Z) t="${t%Z}+0000" ;;
  *[+-][0-9][0-9]:[0-9][0-9]) t="${t%:*}${t##*:}" ;;
  esac
  epoch="$(date -j -f '%Y-%m-%dT%H:%M:%S%z' "$t" '+%s' 2>/dev/null || echo "")"
  if [ -z "$epoch" ]; then
    # オフセット無しの素朴な形はローカル TZ 解釈にフォールバック
    epoch="$(date -j -f '%Y-%m-%dT%H:%M:%S' "${1%%+*}" '+%s' 2>/dev/null || echo "")"
  fi
  if [ -z "$epoch" ]; then
    echo "?"
    return 0
  fi
  diff=$(($(date '+%s') - epoch))
  if [ "$diff" -lt 0 ]; then
    echo "?"
  elif [ "$diff" -lt 3600 ]; then
    echo "$((diff / 60))m"
  elif [ "$diff" -lt 86400 ]; then
    echo "$((diff / 3600))h"
  else
    echo "$((diff / 86400))d"
  fi
}

# 全タスクを 1 パスで TSV 化する(1 ファイル 1 jq。壊れ JSON の警告は 1 描画 1 回/ファイル)。
# 列: status \t repo \t title \t window_name \t next_action \t ctx \t updated_at
collect_rows() {
  for f in "$FLEET_DIR"/tasks/*.json; do
    [ -e "$f" ] || continue
    jq -r '[(.status // "?"), (.repo // "-"), (.title // "-"), (.window_name // "-"),
            (.next_action // "-"), ((.context_pct // "?") | tostring), (.updated_at // "")]
      | map(if type == "string" then gsub("[[:cntrl:]]"; "") else . end)
      | @tsv' "$f" 2>/dev/null || {
      echo "$PROG: 読めない JSON を skip: $f" >&2
      continue
    }
  done
}

# ROWS から 1 status 分を描画する。$1 = status、$2 = マーク、$3 = 色コード("" で無色)。
print_bucket() {
  status="$1" mark="$2" color="$3"
  reset=""
  [ -n "$color" ] && reset="$(printf '\033[0m')"
  printf '%s\n' "$ROWS" | while IFS="$(printf '\t')" read -r st repo title wname naction ctx updated; do
    [ "$st" = "$status" ] || continue
    printf '%s%s %-14s %-24s %-22s %-28s %4s%% %5s%s\n' \
      "$color" "$mark" "$repo" "$title" "${wname:--}" "${naction:--}" "${ctx:-?}" \
      "$(age_of "${updated:-}")" "$reset"
  done
}

render() {
  if [ ! -d "$FLEET_DIR/tasks" ]; then
    echo "claude-fleet: タスクなし($FLEET_DIR/tasks 未作成)"
    return 0
  fi
  ROWS="$(collect_rows)"
  echo "claude-fleet  $(date '+%H:%M:%S')"
  printf '%s\n' '─────────────────────────────────────────────────────────────────────────'
  printf '  %-14s %-24s %-22s %-28s %5s %5s\n' repo title window next_action 'ctx%' upd
  print_bucket waiting-human '!' "$(printf '\033[31m')"
  print_bucket running '>' ''
  print_bucket blocked 'x' "$(printf '\033[33m')"
  print_bucket backlog '.' "$(printf '\033[2m')"
}

if [ "$ONCE" -eq 1 ]; then
  render
  exit 0
fi

trap 'exit 0' INT TERM
while :; do
  printf '\033[2J\033[H'
  render
  sleep "$INTERVAL"
done
