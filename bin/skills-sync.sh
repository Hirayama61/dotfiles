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
# 同名 skill が両ソースにある場合は後段のローカル進化が勝つ(意図した優先順位。
# 上書き時は link_safe が NOTE を出す)。
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
# WARN + failed 計上で skip する(呼び出し側は `|| continue`)。ln 失敗も failed に
# 計上する(握ると部分同期のまま成功終了し prune まで走る)。
link_safe() {
  local src="$1" dst="$2"
  if [[ -e "$dst" && ! -L "$dst" ]]; then
    echo "WARN: 宛先が実体(chezmoi 管理の疑い)のため skip(名前衝突): $dst" >&2
    failed=$((failed + 1))
    return 1
  fi
  if [[ -L "$dst" && "$(readlink "$dst")" != "$src" ]]; then
    echo "NOTE: 既存 symlink を別ソースで上書き: $dst" >&2
  fi
  if ! ln -sfn "$src" "$dst"; then
    echo "WARN: symlink 作成に失敗: $dst" >&2
    failed=$((failed + 1))
    return 1
  fi
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
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    # 前後空白のトリム。xargs は不対の引用符を含む行で異常終了し set -e で sync 全体が
    # 落ちるため、パラメータ展開で行う。
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
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

    # manifest はリポ内ファイルで PR 経由の改変がありうる。spec の形式検証(各セグメント
    # 先頭は英数字 = フラグ注入 `-` 始まりと `.` 単独セグメントを排除)で ghq root 外への
    # 脱出を、`..` 拒否で skillpath/subdir のトラバーサルを塞ぐ。
    if [[ ! "$spec" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._-]*$ || "$spec" == *..* ||
      "${skillpath:-}" == *..* || "${subdir:-}" == *..* ]]; then
      echo "WARN: 不正な manifest 行のため skip: $line" >&2
      failed=$((failed + 1))
      continue
    fi

    # 外部要因(ネットワーク断・upstream 消滅)でスクリプト全体を即死させず、この行だけ
    # 失敗扱いにする(failed>0 で prune 抑止に乗るため安全)。
    if ! ghq get -u "$spec"; then
      echo "WARN: ghq get に失敗: $spec" >&2
      failed=$((failed + 1))
      continue
    fi
    repo_root="$(ghq root)/github.com/$spec"

    if [[ "$mode" == "single" ]]; then
      skill_dir="$repo_root/$skillpath"
      # 外部リポが仕込んだ symlink skill は拒否する(clone された symlink を辿ると
      # リポ外のローカルファイルが skill コンテンツとしてモデルに読まれる)。
      if [[ -L "$skill_dir" || -L "$skill_dir/SKILL.md" ]]; then
        echo "WARN: symlink skill のため skip: $spec/$skillpath" >&2
        failed=$((failed + 1))
        continue
      fi
      # leaf の symlink 検査だけでは skillpath 中間ディレクトリが symlink の場合に
      # repo_root 外を指せる。実体パス(cd + pwd -P、BSD 互換で realpath 非依存)で
      # repo_root 配下への封じ込めを確認する。
      resolved="$(cd "$skill_dir" 2>/dev/null && pwd -P || true)"
      repo_real="$(cd "$repo_root" 2>/dev/null && pwd -P || true)"
      if [[ -z "$resolved" || -z "$repo_real" || "$resolved" != "$repo_real/"* ]]; then
        echo "WARN: repo 外を指す skill のため skip: $spec/$skillpath" >&2
        failed=$((failed + 1))
        continue
      fi
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
      if [[ -L "${skill%/}" || -L "$skill/SKILL.md" ]]; then
        echo "WARN: symlink skill のため skip: $spec/$subdir/$(basename "$skill")" >&2
        continue
      fi
      # 中間ディレクトリ / subdir 自体が symlink だと entry の実体が repo_root 外を
      # 指せる。single モードと同じく repo_root の実体パスを境界に封じ込める(src_root は
      # symlink だと解決先へ逃げるため境界に使えない)。multi は既存の symlink skip と
      # 同じく行全体 failed にはせず WARN + continue(0 link なら後段でまとめて failed)。
      resolved="$(cd "${skill%/}" 2>/dev/null && pwd -P || true)"
      repo_real="$(cd "$repo_root" 2>/dev/null && pwd -P || true)"
      if [[ -z "$resolved" || -z "$repo_real" || "$resolved" != "$repo_real/"* ]]; then
        echo "WARN: repo 外を指す skill のため skip: $spec/$subdir/$(basename "$skill")" >&2
        continue
      fi
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
# symlink 経由で candidates/ が効力を持つ経路を、エントリ単位 + 親階層の両方で塞ぐ
# (「candidates は効力を持たない」の実装側担保)。名前は evolve の規約 ^[a-z0-9-]+$ に
# 一致するものだけ link する(evolve-gate の退避 .prev や不正名を有効化しない)。
evolve_dirs_ok=1
for d in "$EVOLVE_DIR" "$EVOLVE_DIR/active" "$EVOLVE_DIR/active/skills" "$EVOLVE_DIR/active/agents"; do
  if [[ -L "$d" ]]; then
    echo "WARN: ローカル進化の階層が symlink のため全 skip: $d" >&2
    failed=$((failed + 1))
    evolve_dirs_ok=0
    break
  fi
done
if [[ "$evolve_dirs_ok" -eq 1 ]]; then
  shopt -s nullglob
  for skill in "$EVOLVE_DIR"/active/skills/*/; do
    [[ -L "${skill%/}" || -L "$skill/SKILL.md" ]] && continue
    [[ -f "$skill/SKILL.md" ]] || continue
    name="$(basename "$skill")"
    [[ "$name" =~ ^[a-z0-9-]+$ ]] || {
      echo "WARN: 名前規約外のためスキップ(local): $name" >&2
      continue
    }
    link_safe "${skill%/}" "$SKILLS_DIR/$name" || continue
    wanted="$wanted$name"$'\n'
    linked=$((linked + 1))
    echo "linked(local): $name -> ${skill%/}"
  done
  agents_seen=0
  for agent in "$EVOLVE_DIR"/active/agents/*.md; do
    [[ -f "$agent" && ! -L "$agent" ]] || continue
    name="$(basename "$agent")"
    [[ "${name%.md}" =~ ^[a-z0-9-]+$ ]] || {
      echo "WARN: 名前規約外のためスキップ(local-agent): $name" >&2
      continue
    }
    [[ "$agents_seen" -eq 0 ]] && mkdir -p "$AGENTS_DIR" && agents_seen=1
    link_safe "$agent" "$AGENTS_DIR/$name" || continue
    wanted_agents="$wanted_agents$name"$'\n'
    linked=$((linked + 1))
    echo "linked(local-agent): $name -> $agent"
  done
  shopt -u nullglob
fi

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
    grep -qxF -- "$name" <<<"$wanted" && continue
    rm -f "$entry"
    pruned=$((pruned + 1))
    echo "pruned: $name"
  done
  # agents の prune は「リンク先がローカル進化配下の symlink」に限定する(手動作成や
  # 別ツール由来の agent symlink を管轄外として刈らない。skills 側より管轄を狭く取る)。
  if [[ -d "$AGENTS_DIR" ]]; then
    for entry in "$AGENTS_DIR"/*; do
      [[ -L "$entry" ]] || continue
      case "$(readlink "$entry")" in
      "$EVOLVE_DIR"/*) ;;
      *) continue ;;
      esac
      name="$(basename "$entry")"
      grep -qxF -- "$name" <<<"$wanted_agents" && continue
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
