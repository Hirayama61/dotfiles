#!/usr/bin/env bash
#
# demo.sh — 撮影用ショーケース。Panda 配色で統一した tmux セッション "demo" を
# 構築し attach する。実情報・秘匿ゼロのキュレート素材だけを表示する。
#
# 設計方針:
#   - 専用セッション名 "demo" のみを扱う。他セッションには一切触れない。
#   - 配色は単一ソース home/.chezmoidata.yaml の Panda パレットから読む
#     (新規の色定義を作らない)。nvim/tig/eza/fzf は既存の適用済み設定を流用。
#   - 全ペインが静止する(スピナー/プログレスを撮影フレームに残さない)。
#   - fastfetch / bat 等が無くても落ちない(graceful fallback)。
#   - LG DualUp 等の縦長画面前提。高さ配分は比率指定(解像度ハードコードなし)。
#
# 使い方:
#   bin/demo.sh          セッション構築 + attach(mise run demo)
#   bin/demo.sh kill     セッション撤収(mise run demo:kill)

set -euo pipefail

SESSION="demo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEMO_DIR="$SCRIPT_DIR/demo"
PALETTE_FILE="$REPO_ROOT/home/.chezmoidata.yaml"
SHOWCASE_DIR="$DEMO_DIR/showcase"

# ─── サブコマンド: kill ───────────────────────────────────────────────
# "demo" セッションだけを対象にする。has-session で存在確認してから kill。
if [[ "${1:-}" == "kill" ]]; then
  if tmux has-session -t "=$SESSION" 2>/dev/null; then
    tmux kill-session -t "=$SESSION"
    echo "撤収: tmux セッション '$SESSION' を削除しました"
  else
    echo "セッション '$SESSION' は存在しません(何もしません)"
  fi
  exit 0
fi

# ─── Panda パレット読み込み(単一ソース) ─────────────────────────────
# yq 非依存。`name: { hex: "#xxxxxx"` 形式を grep で1行ずつ拾う。
# パレットが読めない場合のみ安全な既定値へフォールバック(撮影は継続可能)。
palette_hex() {
  local role="$1" def="$2" hex=""
  # bash 3.2 の BASH_REMATCH は {n} 量化子で不安定なため grep -oE で抽出する。
  if [[ -r "$PALETTE_FILE" ]]; then
    hex="$(grep -E "^[[:space:]]*${role}:[[:space:]]*\{[[:space:]]*hex:" \
      "$PALETTE_FILE" 2>/dev/null | head -1 \
      | grep -oE '#[0-9a-fA-F]{6}' | head -1 || true)"
  fi
  if [[ -n "$hex" ]]; then
    printf '%s' "$hex"
  else
    printf '%s' "$def"
  fi
}

P_BG="$(palette_hex bg "#242526")"
P_FG="$(palette_hex fg "#e6e6e6")"
P_SUBTLE="$(palette_hex subtle "#676b79")"
P_PINK="$(palette_hex pink "#ff75b5")"
P_MINT="$(palette_hex mint "#19f9d8")"
P_ORANGE="$(palette_hex orange "#ffb86c")"
P_RED="$(palette_hex red "#ff4b82")"
P_BLUE="$(palette_hex blue "#45a9f9")"
P_CYAN="$(palette_hex cyan "#6fc1ff")"

# hex "#rrggbb" → "r;g;b"(truecolor SGR 用)
hex_rgb() {
  local h="${1#\#}"
  printf '%d;%d;%d' "0x${h:0:2}" "0x${h:2:2}" "0x${h:4:2}"
}

ESC=$'\033'
sgr() { printf '%s[%sm' "$ESC" "$1"; }
RESET="$(sgr 0)"
FG_FG="$(sgr "38;2;$(hex_rgb "$P_FG")")"
FG_SUBTLE="$(sgr "38;2;$(hex_rgb "$P_SUBTLE")")"
FG_PINK="$(sgr "38;2;$(hex_rgb "$P_PINK")")"
FG_MINT="$(sgr "38;2;$(hex_rgb "$P_MINT")")"
FG_ORANGE="$(sgr "38;2;$(hex_rgb "$P_ORANGE")")"
FG_RED="$(sgr "38;2;$(hex_rgb "$P_RED")")"
FG_BLUE="$(sgr "38;2;$(hex_rgb "$P_BLUE")")"
FG_CYAN="$(sgr "38;2;$(hex_rgb "$P_CYAN")")"

# Panda 配色でプレーンテキストへ静的に色を付け、固定ファイルへ書き出す。
# 行頭マーカで役割を判定するだけ(実行時に色計算しない=撮影で完全再現)。
colorize() {
  local src="$1" dst="$2"
  : > "$dst"
  while IFS= read -r raw || [[ -n "$raw" ]]; do
    case "$raw" in
      '@ '*)            printf '%s%s%s\n'  "$FG_PINK"   "$raw" "$RESET" >> "$dst" ;;
      '> '*)            printf '%s%s%s\n'  "$FG_CYAN"   "$raw" "$RESET" >> "$dst" ;;
      '* '*)            printf '%s%s%s\n'  "$FG_MINT"   "$raw" "$RESET" >> "$dst" ;;
      '$ '*)            printf '%s%s%s\n'  "$FG_SUBTLE" "$raw" "$RESET" >> "$dst" ;;
      *PASS*|*'ok  '*|*passing*|*'ALL GREEN'*)
                        printf '%s%s%s\n'  "$FG_MINT"   "$raw" "$RESET" >> "$dst" ;;
      *FAIL*|*failing*|*error*)
                        printf '%s%s%s\n'  "$FG_RED"    "$raw" "$RESET" >> "$dst" ;;
      *'  + '*|*' + '*) printf '%s%s%s\n'  "$FG_MINT"   "$raw" "$RESET" >> "$dst" ;;
      *'  ~ '*|*' ~ '*) printf '%s%s%s\n'  "$FG_ORANGE" "$raw" "$RESET" >> "$dst" ;;
      '  '[0-9]*|*kB*)  printf '%s%s%s\n'  "$FG_BLUE"   "$raw" "$RESET" >> "$dst" ;;
      *)                printf '%s%s%s\n'  "$FG_FG"     "$raw" "$RESET" >> "$dst" ;;
    esac
  done < "$src"
}

# ─── ダミー git 履歴(tig / eza 用ショーケース) ──────────────────────
# 初回のみ生成。実情報・秘匿を含まない固定の履歴。撮影で映って自然な内容。
build_showcase() {
  [[ -d "$SHOWCASE_DIR/.git" ]] && return 0
  rm -rf "$SHOWCASE_DIR"
  mkdir -p "$SHOWCASE_DIR/src" "$SHOWCASE_DIR/test"

  # 隔離された撮影専用リポ。ユーザのグローバル設定(Conventional Commits
  # 強制 commit-msg hook / GPG 署名 / テンプレート)に依存しないよう、
  # hooksPath を無効化し identity をローカル固定する。
  _git() {
    git -C "$SHOWCASE_DIR" \
      -c core.hooksPath=/dev/null \
      -c commit.gpgsign=false \
      -c user.email="demo@example.invalid" \
      -c user.name="Demo Bot" \
      -c init.templateDir= \
      "$@"
  }

  _git init -q -b main

  _commit() { # $1=msg  (内容は素材ファイルから派生)
    GIT_AUTHOR_DATE="2026-05-0${commit_n} 09:0${commit_n}:00" \
    GIT_COMMITTER_DATE="2026-05-0${commit_n} 09:0${commit_n}:00" \
      _git commit -q --no-verify -m "$1"
    commit_n=$((commit_n + 1))
  }
  commit_n=1

  cp "$DEMO_DIR/sample.ts" "$SHOWCASE_DIR/src/palette.ts"
  printf 'export const VERSION = "0.1.0";\n' > "$SHOWCASE_DIR/src/index.ts"
  _git add -A; _commit "feat: scaffold palette-engine"

  printf '# palette-engine\n\nA tiny deterministic palette engine.\n' \
    > "$SHOWCASE_DIR/README.md"
  _git add -A; _commit "docs: add README"

  printf 'import { parseHex } from "../src/palette";\n// fixtures\n' \
    > "$SHOWCASE_DIR/test/hex.test.ts"
  _git add -A; _commit "test: cover parseHex edge cases"

  _git checkout -q -b feature/contrast
  printf '\nexport const MIN_CONTRAST = 0.4;\n' >> "$SHOWCASE_DIR/src/palette.ts"
  _git add -A; _commit "feat: dark-on-bright contrast guard"

  _git checkout -q main
  GIT_AUTHOR_DATE="2026-05-05 09:05:00" GIT_COMMITTER_DATE="2026-05-05 09:05:00" \
    _git merge -q --no-ff --no-verify feature/contrast \
      -m "chore: merge contrast guard into main"
  printf 'export const VERSION = "0.2.0";\n' > "$SHOWCASE_DIR/src/index.ts"
  commit_n=6
  _git add -A; _commit "chore: bump to 0.2.0"
  _git tag v0.2.0
}

# ─── ペインランナー生成(全て静止する) ──────────────────────────────
#
# send-keys に複雑なクオート文字列を流すと壊れやすい(&& / | / バックスラッシュ)。
# そこで各ペインの中身を専用 bash スクリプト($DEMO_DIR/.pane-*.sh)へ書き出し、
# tmux からは `respawn-pane -k bash <file>` で「そのファイルを実行するだけ」に
# する。これでクオート事故ゼロ、撮影 100% 再現、シェルプロンプトも出ない。
#
# 静止ビューアは末尾で `read -r -d ''`(NUL 待ち=実質無限停止)し、カーソルを
# 隠す。スピナー/プログレス/プロンプトが撮影フレームに残らない。

# 末尾に付ける「静止」フッタ(ファイルへ追記する)
emit_hold() {
  {
    printf 'printf "\\033[?25l"\n'                       # カーソル非表示
    printf 'read -r -d "" _ </dev/tty 2>/dev/null || '   # NUL 待ち=静止
    printf 'while :; do sleep 3600; done\n'               # 念のため恒久停止
  } >> "$1"
}

# nvim: 既存ユーザ設定(Panda + LSP)で sample.ts を開く。無ければ素 cat 静止。
gen_pane_nvim() {
  local f="$DEMO_DIR/.pane-nvim.sh"
  if command -v nvim >/dev/null 2>&1; then
    printf '#!/usr/bin/env bash\nexec nvim %q\n' "$DEMO_DIR/sample.ts" > "$f"
  else
    printf '#!/usr/bin/env bash\nclear\ncat %q\n' "$DEMO_DIR/sample.ts" > "$f"
    emit_hold "$f"
  fi
  printf '%s' "$f"
}

gen_pane_transcript() {
  # mock の桁合わせ地獄と resume の可搬性問題を避けた方式: 撮影者は
  # Cmd+V → Enter するだけで本物の Claude Code TUI が動く画面になる。
  local f="$DEMO_DIR/.pane-transcript.sh"
  local a="$DEMO_DIR/.claude-transcript.ansi"
  local c="$DEMO_DIR/.clip.txt"
  local oneline                          # 貼って Enter 一発で通すため1行化
  oneline="$(tr '\n' ' ' < "$DEMO_DIR/claude-prompt.txt" \
    | tr -s ' ' | sed 's/^ *//; s/ *$//')"
  # 位置プロンプト指定で対話セッション起動。--model は documented full-name。
  printf 'claude --model claude-haiku-4-5 "%s"' "$oneline" > "$c"
  {
    printf '%s# 撮影手順 ─ クリップボードにコピー済み。このペインで Cmd+V → Enter%s\n\n' \
      "$FG_SUBTLE" "$RESET"
    printf '%s' "$FG_MINT"
    cat "$c"
    printf '%s\n' "$RESET"
  } > "$a"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'clear\n'
    printf 'pbcopy < %q 2>/dev/null || true\n' "$c"
    printf 'cat %q\n' "$a"
    printf 'exec "${SHELL:-/bin/zsh}" -i\n'
  } > "$f"
  printf '%s' "$f"
}

gen_pane_runlog() {
  local f="$DEMO_DIR/.pane-runlog.sh"
  colorize "$DEMO_DIR/run.log" "$DEMO_DIR/.run.ansi"
  printf '#!/usr/bin/env bash\nclear\ncat %q\n' "$DEMO_DIR/.run.ansi" > "$f"
  emit_hold "$f"
  printf '%s' "$f"
}

# tig: 対話 TUI を log graph 静止で開く。無ければ git log graph を静止表示。
gen_pane_tig() {
  local f="$DEMO_DIR/.pane-tig.sh"
  if command -v tig >/dev/null 2>&1; then
    printf '#!/usr/bin/env bash\ncd %q\nexec tig --all\n' "$SHOWCASE_DIR" > "$f"
  else
    printf '#!/usr/bin/env bash\nclear\ngit -C %q -c core.hooksPath=/dev/null log --graph --oneline --all --decorate --color=always\n' \
      "$SHOWCASE_DIR" > "$f"
    emit_hold "$f"
  fi
  printf '%s' "$f"
}

# eza: --tree --icons --git で showcase を静止表示。無ければ find で代替。
gen_pane_eza() {
  local f="$DEMO_DIR/.pane-eza.sh"
  if command -v eza >/dev/null 2>&1; then
    printf '#!/usr/bin/env bash\nclear\ncd %q\neza --tree --icons --git --level=3 --color=always\n' \
      "$SHOWCASE_DIR" > "$f"
  else
    printf '#!/usr/bin/env bash\nclear\ncd %q\nfind . -not -path "*/.git/*" | sort\n' \
      "$SHOWCASE_DIR" > "$f"
  fi
  emit_hold "$f"
  printf '%s' "$f"
}

# システム情報: fastfetch → 無ければ Panda 配色の簡易パネルにフォールバック。
gen_pane_sysinfo() {
  local f="$DEMO_DIR/.pane-sysinfo.sh"
  if command -v fastfetch >/dev/null 2>&1; then
    printf '#!/usr/bin/env bash\nfastfetch\n' > "$f"
  else
    local a="$DEMO_DIR/.sysinfo.ansi"
    {
      printf '%s  ╭───────────────────────────╮%s\n'  "$FG_PINK"   "$RESET"
      printf '%s  │%s   palette-engine showcase  %s│%s\n' \
        "$FG_PINK" "$FG_MINT" "$FG_PINK" "$RESET"
      printf '%s  ╰───────────────────────────╯%s\n'  "$FG_PINK"   "$RESET"
      printf '%s   host   %s%s\n'   "$FG_SUBTLE" "${FG_FG}demo-machine"      "$RESET"
      printf '%s   os     %s%s\n'   "$FG_SUBTLE" "${FG_FG}macOS"            "$RESET"
      printf '%s   shell  %s%s\n'   "$FG_SUBTLE" "${FG_FG}zsh"              "$RESET"
      printf '%s   editor %s%s\n'   "$FG_SUBTLE" "${FG_CYAN}neovim"         "$RESET"
      printf '%s   theme  %s%s\n'   "$FG_SUBTLE" "${FG_MINT}Panda"          "$RESET"
      printf '%s   ●%s ●%s ●%s ●%s ●%s ●%s\n' \
        "$FG_PINK" "$FG_MINT" "$FG_ORANGE" "$FG_RED" "$FG_BLUE" "$FG_CYAN" "$RESET"
    } > "$a"
    printf '#!/usr/bin/env bash\nclear\ncat %q\n' "$a" > "$f"
  fi
  emit_hold "$f"
  printf '%s' "$f"
}

# ─── セッション構築 ──────────────────────────────────────────────────
build_showcase

# 既存の "demo" のみ作り直す(他名セッションは絶対に触らない)。
if tmux has-session -t "=$SESSION" 2>/dev/null; then
  tmux kill-session -t "=$SESSION"
fi

# レイアウト(縦長最適化・ヒーロ上段型):
#
#   ┌───────────────┬───────────────┐
#   │ ① nvim        │ ② transcript  │   上段 ~50%h
#   ├───────┬───────┴───────┬───────┤
#   │ ③ tig │ ④ eza tree    │ ⑤ sys │   中段 ~30%h
#   ├───────┴───────────────┴───────┤
#   │ ⑥ run.log(全幅)              │   下段 ~20%h
#   └───────────────────────────────┘
#
# 高さ配分は -p(パーセント)で指定。tmux は分割時に「新ペイン側の%」を取る。
# 手順:
#   base(=①, 全画面) を縦に割って下 50% を確保 → そこから 20% を最下段⑥へ。
#   残り 30% 帯が中段。上段①を横割りして②。中段を三分割で ③④⑤。

# ペインは index ではなく安定した pane-id(%N)で扱う。
# 分割のたびに -P -F '#{pane_id}' で「新しく出来たペイン」の id を捕捉する。
# 全幅の帯(下段・中段)を「先に」確保してから横分割するので、
# ⑥ run.log と中段は構造的にフル幅になる(後付け resize 補正は不要)。

tmux new-session -d -s "$SESSION" -n showcase -c "$DEMO_DIR" \
  -x 220 -y 200            # 仮想サイズ。attach 後に実端末へ自動追従。
P_HERO="$(tmux list-panes -t "$SESSION:showcase" -F '#{pane_id}' | head -1)"

# 1) 最下段⑥(全体 ~20%・全幅)を切り出す
P_LOG="$(tmux split-window -v -p 20 -t "$P_HERO" -c "$DEMO_DIR" \
  -P -F '#{pane_id}')"
# 2) 残り上 80% から中段帯(全体 ~30% ≒ 上80%の 37%・全幅)を切り出す
P_MIDL="$(tmux split-window -v -p 37 -t "$P_HERO" -c "$SHOWCASE_DIR" \
  -P -F '#{pane_id}')"
# 3) 上段ヒーロを横割りして ② transcript(上段右)
P_TRANS="$(tmux split-window -h -p 50 -t "$P_HERO" -c "$DEMO_DIR" \
  -P -F '#{pane_id}')"
# 4) 中段帯を三分割: ③ tig / ④ eza / ⑤ sysinfo
P_EZA="$(tmux split-window -h -p 66 -t "$P_MIDL" -c "$SHOWCASE_DIR" \
  -P -F '#{pane_id}')"
P_SYS="$(tmux split-window -h -p 50 -t "$P_EZA" -c "$DEMO_DIR" \
  -P -F '#{pane_id}')"

# 役割割り当て: respawn-pane -k でペインプロセスを生成スクリプトに置換。
# send-keys を使わないのでクオート事故ゼロ・プロンプト非表示・完全再現。
tmux respawn-pane -k -t "$P_HERO"  bash "$(gen_pane_nvim)"
tmux respawn-pane -k -t "$P_TRANS" bash "$(gen_pane_transcript)"
tmux respawn-pane -k -t "$P_MIDL"  bash "$(gen_pane_tig)"
tmux respawn-pane -k -t "$P_EZA"   bash "$(gen_pane_eza)"
tmux respawn-pane -k -t "$P_SYS"   bash "$(gen_pane_sysinfo)"
tmux respawn-pane -k -t "$P_LOG"   bash "$(gen_pane_runlog)"

# カーソルを上段ヒーロ(撮影の主役)へ。
tmux select-pane -t "$P_HERO"

# attach(tmux 内から呼ばれた場合は switch-client)
if [[ -n "${TMUX:-}" ]]; then
  tmux switch-client -t "$SESSION"
else
  tmux attach-session -t "$SESSION"
fi
