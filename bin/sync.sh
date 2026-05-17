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
SNAPSHOT_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles"
SNAPSHOT="$SNAPSHOT_DIR/${NAME}-managed.txt"

mkdir -p "$SNAPSHOT_DIR"

NEW=$(mktemp)
trap 'rm -f "$NEW"' EXIT

chezmoi --config "$CONFIG" managed > "$NEW"

if [[ -f "$SNAPSHOT" ]]; then
  # 深い順(reverse sort)に処理。managed ディレクトリ(chezmoi externals 等)
  # も orphan になり得るため、子を先に消してから親ディレクトリごと除去する。
  comm -23 <(sort "$SNAPSHOT") <(sort "$NEW") | sort -r | while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    target="$HOME/$f"
    [[ "$target" == "$HOME" || "$target" == "/" ]] && continue
    if [[ -e "$target" || -L "$target" ]]; then
      echo "[$NAME] orphan removed: $target"
      rm -rf -- "$target"
    fi
  done
fi

cp "$NEW" "$SNAPSHOT"
chezmoi --config "$CONFIG" apply ${FORCE:+--force}
