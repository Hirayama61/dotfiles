#!/usr/bin/env bash
# agent skill / agent を ~/.claude へ symlink 同期する。ソースは 2 系統:
#   1. 外部 skill … ext-skills.txt の宣言に従い ghq get -u で取得して symlink
#   2. ローカル進化 … ~/.claude-evolution/active/ の承認済み skill/agent を symlink
#      (candidates/ は対象外 = 人間ゲート前の候補は決して効力を持たない)
#
# 実行: mise run skills:sync
#       bin/skills-sync.sh --local-only   (ローカル進化のみ反映。ghq 同期と prune を
#                                          スキップする evolve-gate 承認経路用の軽量モード)
#
# マニフェスト集合 + ローカル進化集合から外れた symlink は prune する(全量同期時のみ)。
#
# chezmoi 非干渉:
#   - prune は [[ -L ]] で symlink のみ対象とし、chezmoi 管理の実体 skill ディレクトリ
#     (obsidian-memory 等)・実体 agent ファイルには触れない。
#   - 作成側も link_safe で「宛先が実体(非 symlink)なら WARN + skip」する。ln -sfn は
#     実ファイル宛先を symlink で上書き置換し、実ディレクトリ宛先にはその内部へ作るため、
#     prune 側の [[ -L ]] だけでは chezmoi 実体の破壊経路を塞げない。

set -euo pipefail

SKILLS_DIR="$HOME/.claude/skills"
AGENTS_DIR="$HOME/.claude/agents"
# ローカル進化ディレクトリ(git 管理外・マシンローカル)。パスは固定で、規約の正典は
# cc-dotfiles の skills/evolve/SKILL.md(env override を置かないのは、hook の候補数走査・
# evolve/evolve-gate・本スクリプトの 4 参照箇所の乖離を防ぐため)。
EVOLVE_DIR="$HOME/.claude-evolution"
MANIFEST="$(cd "$(dirname "$0")/.." && pwd)/ext-skills.txt"

LOCAL_ONLY=0
if [[ "${1:-}" == "--local-only" ]]; then
  LOCAL_ONLY=1
elif [[ $# -gt 0 ]]; then
  echo "Usage: $0 [--local-only]" >&2
  exit 1
fi

mkdir -p "$SKILLS_DIR"

# wanted: 同期ソース由来の skill / agent 名の集合(改行区切り文字列で保持)。
# 連想配列(declare -A)は bash 4+ 専用で macOS 標準の bash 3.2 では動かないため使わない。
wanted=""
wanted_agents=""
linked=0
pruned=0
failed=0

# 衝突ガード付き symlink 作成。宛先が実体(非 symlink)なら chezmoi 管理の疑いとして
# WARN + failed 計上で skip する(呼び出し側は `|| continue`)。
link_safe() {
  local src="$1" dst="$2"
  if [[ -e "$dst" && ! -L "$dst" ]]; then
    echo "WARN: 宛先が実体(chezmoi 管理の疑い)のため skip(名前衝突): $dst" >&2
    failed=$((failed + 1))
    return 1
  fi
  ln -sfn "$src" "$dst"
}

# ── ソース 1: 外部 skill(ext-skills.txt)。--local-only では丸ごとスキップ ──
if [[ "$LOCAL_ONLY" -eq 0 ]]; then
  command -v ghq &>/dev/null || {
    echo "ghq not found. mise install で ghq を取得してから再実行してください。" >&2
    exit 1
  }
  [[ -f "$MANIFEST" ]] || {
    echo "manifest not found: $MANIFEST" >&2
    exit 1
  }

  # 各行を 3 形態で解釈する(ヘッダコメント参照):
  #   A. owner/repo:subdir          コロンあり。subdir 直下を複数 symlink
  #   B. owner/repo/path/to/skill   コロンなし & 3 セグメント以上。1 ディレクトリを単体 symlink
  #   C. owner/repo                 コロンなし & 2 セグメント。subdir 既定 skills で複数 symlink
  # ghq get の対象はいずれも先頭 2 セグメント owner/repo。
  while IFS= read -r line; do
    line="${line%%#*}"
    line="$(echo "$line" | xargs)"
    [[ -z "$line" ]] && continue

    mode="multi"
    skillpath=""
    if [[ "$line" == *:* ]]; then
      spec="${line%%:*}"
      subdir="${line#*:}"
    else
      # スラッシュ以外を除去して区切り数を数える(連想配列不要の bash 3.2 互換)。
      slashes="${line//[!\/]/}"
      if [[ ${#slashes} -ge 2 ]]; then
        owner="${line%%/*}"
        rest="${line#*/}"
        spec="$owner/${rest%%/*}"
        skillpath="${rest#*/}"
        skillpath="${skillpath%/}"
        mode="single"
      else
        spec="$line"
        subdir="skills"
      fi
    fi

    ghq get -u "$spec"
    repo_root="$(ghq root)/github.com/$spec"

    if [[ "$mode" == "single" ]]; then
      skill_dir="$repo_root/$skillpath"
      # 明示指定が取れない=upstream のパス移動など陳腐化の兆候。無言 skip だと
      # prune で既存 symlink が消えても気づけないため WARN + 失敗計上する。
      [[ -f "$skill_dir/SKILL.md" ]] || {
        echo "WARN: SKILL.md なし(パス陳腐化の疑い): $spec/$skillpath" >&2
        failed=$((failed + 1))
        continue
      }
      name="$(basename "$skill_dir")"
      link_safe "$skill_dir" "$SKILLS_DIR/$name" || continue
      wanted="$wanted$name"$'\n'
      linked=$((linked + 1))
      echo "linked: $name -> $skill_dir"
      continue
    fi

    src_root="$repo_root/$subdir"
    [[ -d "$src_root" ]] || {
      echo "WARN: subdir なし(パス陳腐化の疑い): $spec/$subdir" >&2
      failed=$((failed + 1))
      continue
    }

    # subdir 内の個々の SKILL.md 不在は(他が取れていれば)正常。だが行全体で
    # 0 link はこの repo から1つも取れていない=異常として WARN + 失敗計上する。
    linked_here=0
    for skill in "$src_root"/*/; do
      [[ -f "$skill/SKILL.md" ]] || continue
      name="$(basename "$skill")"
      link_safe "${skill%/}" "$SKILLS_DIR/$name" || continue
      wanted="$wanted$name"$'\n'
      linked=$((linked + 1))
      linked_here=$((linked_here + 1))
      echo "linked: $name -> ${skill%/}"
    done
    [[ "$linked_here" -eq 0 ]] && {
      echo "WARN: skill を1つも link できず(パス陳腐化の疑い): $spec/$subdir" >&2
      failed=$((failed + 1))
    }
  done <"$MANIFEST"
fi

# ── ソース 2: ローカル進化(~/.claude-evolution/active)──
# ディレクトリ不在・空は正常(まだ何も承認されていないマシン)。failed 計上しない。
shopt -s nullglob
for skill in "$EVOLVE_DIR"/active/skills/*/; do
  [[ -f "$skill/SKILL.md" ]] || continue
  name="$(basename "$skill")"
  link_safe "${skill%/}" "$SKILLS_DIR/$name" || continue
  wanted="$wanted$name"$'\n'
  linked=$((linked + 1))
  echo "linked(local): $name -> ${skill%/}"
done
agents_seen=0
for agent in "$EVOLVE_DIR"/active/agents/*.md; do
  [[ "$agents_seen" -eq 0 ]] && mkdir -p "$AGENTS_DIR" && agents_seen=1
  name="$(basename "$agent")"
  link_safe "$agent" "$AGENTS_DIR/$name" || continue
  wanted_agents="$wanted_agents$name"$'\n'
  linked=$((linked + 1))
  echo "linked(local-agent): $name -> $agent"
done
shopt -u nullglob

# ── prune(全量同期時のみ)──
# 同期失敗(failed>0)があると wanted が不完全=本来 link されるべき skill が
# 欠けている。この状態で prune すると、陳腐化したパスの skill を「不要」と誤認して
# 既存 symlink を破壊する。失敗時は prune を丸ごと抑止し、manifest 修正後の再実行に
# 委ねる(sync.sh の空 managed ガードと同型の破壊防止)。
# --local-only でも抑止する(外部 skill の wanted が空のままなので prune すると
# ext-skills 由来 symlink を全滅させる)。
if [[ "$LOCAL_ONLY" -eq 1 ]]; then
  : # prune しない(承認経路の軽量モード。退役反映は次回の全量同期に委ねる)
elif [[ "$failed" -gt 0 ]]; then
  echo "WARN: 同期失敗あり。symlink 破壊を避けるため prune を抑止しました(この実行では退役させた skill の削除反映も保留)。manifest を修正して再実行してください。" >&2
else
  for entry in "$SKILLS_DIR"/*; do
    [[ -L "$entry" ]] || continue
    name="$(basename "$entry")"
    grep -qxF "$name" <<<"$wanted" && continue
    rm -f "$entry"
    pruned=$((pruned + 1))
    echo "pruned: $name"
  done
  # agents は symlink 供給源がローカル進化のみ。skills と同じ [[ -L ]] 限定 prune。
  if [[ -d "$AGENTS_DIR" ]]; then
    for entry in "$AGENTS_DIR"/*; do
      [[ -L "$entry" ]] || continue
      name="$(basename "$entry")"
      grep -qxF "$name" <<<"$wanted_agents" && continue
      rm -f "$entry"
      pruned=$((pruned + 1))
      echo "pruned(agent): $name"
    done
  fi
fi

echo
echo "skills:sync 完了 — linked=$linked pruned=$pruned failed=$failed (skills dir: $SKILLS_DIR)"

[[ "$failed" -gt 0 ]] && exit 1
exit 0
