#!/usr/bin/env bash
# 外部 agent skill を ext-skills.txt の宣言に従って同期する。
#
# 実行: mise run skills:sync
#
# 各 repo を ghq get -u で取得/更新し、その skills サブディレクトリ配下の
# 各 skill(SKILL.md を持つもの)を ~/.claude/skills/<name> へ symlink する。
# マニフェスト集合から外れた symlink は prune する。
#
# chezmoi 非干渉: 手動 symlink は chezmoi managed に現れず sync.sh の orphan
# 判定にも入らない。prune は [[ -L ]] で symlink のみ対象とし、chezmoi 管理の
# 実体 skill ディレクトリ(obsidian-memory 等)には触れない。

set -euo pipefail

command -v ghq &>/dev/null || {
  echo "ghq not found. mise install で ghq を取得してから再実行してください。" >&2
  exit 1
}

SKILLS_DIR="$HOME/.claude/skills"
MANIFEST="$(cd "$(dirname "$0")/.." && pwd)/ext-skills.txt"

[[ -f "$MANIFEST" ]] || {
  echo "manifest not found: $MANIFEST" >&2
  exit 1
}

mkdir -p "$SKILLS_DIR"

# wanted: マニフェスト由来 skill 名の集合(改行区切り文字列で保持)。
# 連想配列(declare -A)は bash 4+ 専用で macOS 標準の bash 3.2 では動かないため使わない。
wanted=""
linked=0
pruned=0

while IFS= read -r line; do
  line="${line%%#*}"
  line="$(echo "$line" | xargs)"
  [[ -z "$line" ]] && continue

  repo="${line%%:*}"
  subdir="${line#*:}"
  [[ "$subdir" == "$line" ]] && subdir="skills"

  ghq get -u "$repo"

  src_root="$(ghq root)/github.com/$repo/$subdir"
  [[ -d "$src_root" ]] || {
    echo "skip (no subdir): $repo/$subdir" >&2
    continue
  }

  for skill in "$src_root"/*/; do
    [[ -f "$skill/SKILL.md" ]] || continue
    name="$(basename "$skill")"
    ln -sfn "${skill%/}" "$SKILLS_DIR/$name"
    wanted="$wanted$name"$'\n'
    linked=$((linked + 1))
    echo "linked: $name -> ${skill%/}"
  done
done <"$MANIFEST"

for entry in "$SKILLS_DIR"/*; do
  [[ -L "$entry" ]] || continue
  name="$(basename "$entry")"
  grep -qxF "$name" <<<"$wanted" && continue
  rm -f "$entry"
  pruned=$((pruned + 1))
  echo "pruned: $name"
done

echo
echo "skills:sync 完了 — linked=$linked pruned=$pruned (skills dir: $SKILLS_DIR)"
