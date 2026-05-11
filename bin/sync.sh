#!/usr/bin/env bash
# 削除自動化付き chezmoi apply ラッパー
#
# Usage: bin/sync.sh <chezmoi-config-path> <name>
#
# 動作:
#   1. 現在の chezmoi managed 出力を取得
#   2. 前回 snapshot との diff から、ソースから消えたパスを検出
#   3. 該当する $HOME 内の target を削除
#   4. snapshot を更新
#   5. chezmoi apply を実行

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <chezmoi-config-path> <name>" >&2
  exit 1
fi

CONFIG="$1"
NAME="$2"
SNAPSHOT_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles"
SNAPSHOT="$SNAPSHOT_DIR/${NAME}-managed.txt"

mkdir -p "$SNAPSHOT_DIR"

NEW=$(mktemp)
trap 'rm -f "$NEW"' EXIT

chezmoi --config "$CONFIG" managed > "$NEW"

if [[ -f "$SNAPSHOT" ]]; then
  comm -23 <(sort "$SNAPSHOT") <(sort "$NEW") | while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    target="$HOME/$f"
    if [[ -e "$target" || -L "$target" ]]; then
      echo "[$NAME] orphan removed: $target"
      rm -f "$target"
    fi
  done
fi

cp "$NEW" "$SNAPSHOT"
chezmoi --config "$CONFIG" apply
