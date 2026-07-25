#!/bin/sh
# tmux の session-created hook から呼ばれ、ホーム window に相方(partner)を立てる。
#
# 相方は「作業中に思い出して呼ぶ」skill ではなく「作業を始める前に開く場所」なので、
# 呼び出しを記憶に頼らず tmux の起動側へ埋める(cc-dotfiles の skills/partner 参照)。
#
# 使い方: partner-home.sh <session-id>
#         tmux.conf の set-hook -g session-created から #{q:hook_session} 付きで呼ぶ。
#         セッション名ではなく ID を渡す。run-shell の文字列は sh -c に渡り、tmux の
#         セッション名は空白・;・$( を保持できるため、名前渡しは任意コマンド実行になる。
#         名前は tmux の target としても曖昧(完全一致 → 前方一致 → fnmatch の順で解決)。
#
# 安全側設計: 何が欠けても tmux の起動を止めない(すべて exit 0 の無音素通り)。

set -eu

# 受け取ってよいのはセッション ID($ + 数字)だけ。想定外の形式は素通りする。
session="${1:-}"
case "$session" in
'$'[0-9]*) ;;
*) exit 0 ;;
esac

# 名前は tmux から引き直す(argv 経由なので sh を通らない)。
session_name="$(tmux display-message -p -t "$session" '#{session_name}' 2>/dev/null)" || exit 0

# 作業用でないセッションには立てない。
# popup: tmux.conf の bind e が作る永続シェル。demo: bin/demo.sh の収録用セッション。
case "$session_name" in
popup | demo) exit 0 ;;
esac

command -v claude >/dev/null 2>&1 || exit 0

# skill 実体は別リポ(cc-dotfiles)管理で、両リポの apply は独立している。
[ -r "$HOME/.claude/skills/partner/SKILL.md" ] || exit 0

# 二重生成の防止に window 名は使えない。automatic-rename-format が
# '#{b:pane_current_path}' なので、cwd の basename が home のセッションでは
# 既存 window が自動的に home と名乗る。
if [ "$(tmux show-options -qv -t "$session" @partner_home 2>/dev/null || true)" = 1 ]; then
  exit 0
fi

# -d: 起動直後のフォーカスを奪わない(ユーザーが特定 dir で作業を始める導線を潰さない)。
# exec でシェルを残す: 相方セッションを終了しても window が消えず、同じ場所で立て直せる。
# $SHELL の展開は新 window 側の sh に任せる(ここで埋めると空白入りのパスが語分割される)。
# -l は tmux が通常の window でログインシェルを起動するのに合わせる。
# shellcheck disable=SC2016
tmux new-window -d -t "$session" -n home -c "$HOME" \
  'claude /partner; exec -l "${SHELL:-/bin/sh}"' 2>/dev/null || exit 0

tmux set-option -t "$session" @partner_home 1 2>/dev/null || exit 0
