#!/usr/bin/env bash
# 削除自動化付き chezmoi apply ラッパー
#
# Usage: bin/sync.sh <chezmoi-config-path> <name> [--force]
#
# 動作:
#   1. 現在の chezmoi managed 出力を取得
#   2. 前回 snapshot との diff から、ソースから消えたパスを検出
#   3. 該当する $HOME 内の target を削除
#   4. snapshot を更新
#   5. chezmoi apply を実行
#
# --force: chezmoi apply に --force を渡す。Claude Code のように
#          アプリ自身が target を書き換える設定(cc-dotfiles の
#          ~/.claude/settings.json 等)向け。テンプレートを常に正とし、
#          管理外変更の確認プロンプトを出さず上書きする。

set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: $0 <chezmoi-config-path> <name> [--force]" >&2
  exit 1
fi

CONFIG="$1"
NAME="$2"
FORCE="${3:-}"

if [[ -n "$FORCE" && "$FORCE" != "--force" ]]; then
  echo "Unknown 3rd argument: $FORCE (only --force is supported)" >&2
  exit 1
fi

# config が読めないと chezmoi managed が空を返し、下流の orphan 削除が前回 snapshot の
# 全行を $HOME から rm -rf する事故になる(#17)。config 不在では apply も成立しないので
# 削除前に早期 abort する。
if [[ ! -f "$CONFIG" || ! -r "$CONFIG" ]]; then
  echo "[$NAME] config が存在しないか読み取れません: $CONFIG" >&2
  echo "[$NAME] orphan 削除・apply を中止(snapshot は保全)。" >&2
  exit 2
fi

SNAPSHOT_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles"
SNAPSHOT="$SNAPSHOT_DIR/${NAME}-managed.txt"

mkdir -p "$SNAPSHOT_DIR"

# source-aware: cwd が NAME と同じ repo の作業ツリー(worktree 含む)なら
# その toplevel を --source に渡し、worktree 内の編集も apply/diff が読めるようにする。
# managed(削除自動化 snapshot)と apply の双方に同一 SOURCE_ARGS を渡すこと。
# 片方だけに付けると snapshot と apply の source が食い違い、誤った orphan 削除を招く。
# ヘルパーは値(toplevel パス)のみ返すので --source "$_src" と引用付きで組む(空白/グロブ安全)。
# 配列展開は ${a[@]+...} で空ガードする(macOS 既定 bash 3.2 では set -u 下で
# 空配列の "${a[@]}" が unbound variable で落ちるため)。
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
SOURCE_ARGS=()
_src="$("$SCRIPT_DIR/chezmoi-source.sh" "$NAME")"
[[ -n "$_src" ]] && SOURCE_ARGS=(--source "$_src")

NEW=$(mktemp)
trap 'rm -f "$NEW"' EXIT

if ! chezmoi --config "$CONFIG" "${SOURCE_ARGS[@]+"${SOURCE_ARGS[@]}"}" managed > "$NEW"; then
  echo "[$NAME] chezmoi managed が非0終了。orphan 削除・apply を中止(snapshot は保全)。" >&2
  exit 3
fi

# managed が空になるのは「全ファイルが管理対象から消えた」ではなく、ほぼ常に chezmoi の
# 読み取り失敗 or source 解決失敗(source-aware #16)である。空のまま下流に進むと前回
# snapshot の全行が orphan 扱いになり、.config 等のディレクトリエントリごと $HOME から
# rm -rf される(#17)。dotfiles/cc-dotfiles はどちらも正当に空にならないため、0 行 = 失敗と
# みなして削除も snapshot 上書きも apply も一切せず abort する。
if [[ ! -s "$NEW" ]]; then
  echo "[$NAME] chezmoi managed が空。config 不在/読み取り失敗/source 解決失敗の可能性。" >&2
  echo "[$NAME] orphan 削除・apply を中止(snapshot は保全)。" >&2
  exit 4
fi

if [[ -f "$SNAPSHOT" ]]; then
  # 深い順(reverse sort)に処理。managed ディレクトリ(chezmoi externals 等)
  # も orphan になり得るため、子を先に消してから親ディレクトリごと除去する。
  comm -23 <(sort "$SNAPSHOT") <(sort "$NEW") | sort -r | while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    # chezmoi managed は $HOME 相対パスのみ返す前提。rm -rf は不可逆なので、
    # 仕様変更や source 異常で先頭 /(絶対パス)や .. コンポーネント(親への脱出)が
    # 混じった行は $HOME 外を壊しうる。防御的に skip する(#17)。
    case "$f" in .|..) echo "[$NAME] orphan skipped (dot entry): $f" >&2; continue ;; esac
    case "$f" in /*) echo "[$NAME] orphan skipped (absolute path): $f" >&2; continue ;; esac
    case "/$f/" in */../*) echo "[$NAME] orphan skipped (parent traversal): $f" >&2; continue ;; esac
    target="$HOME/$f"
    [[ "$target" == "$HOME" || "$target" == "/" ]] && continue
    if [[ -e "$target" || -L "$target" ]]; then
      echo "[$NAME] orphan removed: $target"
      rm -rf -- "$target"
    fi
  done
fi

cp "$NEW" "$SNAPSHOT"
chezmoi --config "$CONFIG" "${SOURCE_ARGS[@]+"${SOURCE_ARGS[@]}"}" apply ${FORCE:+--force}
