#!/usr/bin/env zsh
# tmux popup から worktree / ghq repo を fzf で選び、新 window(Enter)か pane 横分割(C-s)で開く。
# tmux bind: prefix+T (worktree) / prefix+G (repo)。
#
# 旧 zsh ZLE widget(ghq_fzf_repo=^g^g / gwq_fzf_worktree=^g^w)を tmux に一本化したもの。
# ZLE widget はシェルのプロンプト上でしか動かないが、tmux prefix は TUI(Claude Code 等)
# 実行中でも tmux が先に奪うので、どの画面からでも同じキーで呼べる(これが寄せた理由)。
#
# popup はあくまで finder の見た目。選択した瞬間に popup は閉じ(display-popup -E)、実体の
# window/pane を開く。tmux の popup は window/pane に「昇格」できないため、選択を起点に
# new-window / split-window する形にしている。
#
# worktree 列挙は gwq list ではなく ~/worktrees の生 FS から(path しか要らず高速)。naming は
# wt.sh / WorktreeCreate hook が強制するので FS は gwq と等価な真実。再帰 glob は使わず
# worktree root(.git を持つ dir)で降下を止める(node_modules 等を走査して遅くなるのを防ぐ)。

emulate -L zsh
set -o pipefail

local mode=$1
[[ $mode == worktree || $mode == repo ]] || { print -u2 "usage: jump.sh worktree|repo"; exit 1 }

# --- 候補生成: "可視表示<TAB>絶対パス" を配列に積む(path は隠しフィールド)---
local -a lines=()
if [[ $mode == worktree ]]; then
  local base=$HOME/worktrees
  local -a leaves=() pending=( $base/*/*/*(/N) )   # host/owner/repo の namespace dir 群
  local d
  while (( ${#pending} )); do
    d=$pending[1]; shift pending
    if [[ -e $d/.git ]]; then leaves+=( $d ); else pending+=( $d/*(/N) ); fi
  done
  (( ${#leaves} )) || { print -u2 "worktree が見つかりません ($base)"; exit 0 }
  # branch を最大表示幅で右パディングし ⟨repo⟩ 列を揃える(m フラグ=表示幅基準。全角でもずれない)。
  local p rel repo branch b
  local -i maxb=0 i
  local -a branches=() repos=() paths=()
  for p in $leaves; do
    rel=${p#$base/}
    local -a parts=( "${(@s:/:)rel}" )
    repo=$parts[3]
    branch=${(j:/:)parts[4,-1]}
    branches+=( "$branch" ); repos+=( "$repo" ); paths+=( "$p" )
    (( ${(m)#branch} > maxb )) && maxb=${(m)#branch}
  done
  for (( i = 1; i <= ${#branches}; i++ )); do
    b=$branches[i]
    lines+=( "${(mr:$maxb:)b}  ⟨$repos[i]⟩"$'\t'"$paths[i]" )
  done
else
  # ghq list -p の絶対パスから ghq root を剥がし、相対パス(host/owner/repo 等)で扱う。
  # parts 決め打ちだと root 直下(local/repo)で ghq の dir 名が見出しに混ざるため root prefix を剥がす。複数 root 対応。
  local listing
  listing=$(ghq list -p) || { tmux display-message "ghq list に失敗しました"; exit 1 }
  [[ -n $listing ]] || { tmux display-message "ghq リポジトリが見つかりません"; exit 1 }
  local -a roots=( ${(f)"$(ghq root --all 2>/dev/null)"} )
  (( ${#roots} )) || roots=( "$(ghq root)" )
  local p r rel e group repo prev="" best
  local -a entries=()
  for p in ${(f)listing}; do
    # 最長一致の root を剥がす(ネストした root /a と /a/b で短い方を剥がすと rel が崩れるため)。
    best=""
    for r in $roots; do [[ $p == $r/* && ${#r} -gt ${#best} ]] && best=$r; done
    rel=$p
    [[ -n $best ]] && rel=${p#$best/}
    entries+=( "$rel"$'\t'"$p" )
  done
  # 相対パスでソートして同一 owner を隣接させ、host/owner 見出しを 1 回だけ出して repo をインデント表示する。
  # 見出し行は fzf で選択不可にできないため隠し path(2 列目)を空にして選択時 no-op にする(後段 target 空 → 何もしない)。
  for e in ${(o)entries}; do
    rel=${e%%$'\t'*}; p=${e#*$'\t'}
    if [[ $rel != */* ]]; then
      lines+=( "$rel"$'\t'"$p" )      # root 直下(親なし)repo は見出しを出さずそのまま
      prev=""
      continue
    fi
    group=${rel%/*}
    repo=${rel##*/}
    if [[ $group != $prev ]]; then
      lines+=( "$group/"$'\t' )       # 見出し(path 空 → no-op)
      prev=$group
    fi
    lines+=( "  $repo"$'\t'"$p" )
  done
fi

# --- preview(worktree=tig 風 git log + status / repo=README or tree)。{2}=path は fzf が単引用符化済 ---
local preview
if [[ $mode == worktree ]]; then
  preview='git -C {2} log -n 20 --color=always --date=relative --pretty=format:"%C(green)%<(14,trunc)%ad%C(reset) %C(cyan)%<(14,trunc)%an%C(reset) %s" 2>/dev/null; echo; echo; git -C {2} -c color.status=always status -sb 2>/dev/null'
else
  preview='bat --color=always --style=header,grid --line-range :80 {2}/README.md 2>/dev/null || eza --icons --tree --level=2 {2} 2>/dev/null || ls -la {2}'
fi

# --- fzf: Enter=window / C-s=pane(--expect で押下キーを 1 行目に返す)---
local out key sel target
out=$(
  print -rl -- $lines | fzf --layout=reverse \
    --delimiter='\t' --with-nth=1 --nth=1 \
    --expect=ctrl-s \
    --header='enter=window   C-s=pane' \
    --preview "$preview" --preview-window=right,60%
) || exit 0
[[ -n $out ]] || exit 0
key=${out%%$'\n'*}        # "" (enter) または "ctrl-s"
sel=${out#*$'\n'}         # 選択行(表示<TAB>path)
target=${sel##*$'\t'}     # 隠しフィールド = 絶対パス
[[ -n $target ]] || exit 0

if [[ $key == ctrl-s ]]; then
  tmux split-window -h -c "$target"
else
  tmux new-window -c "$target"
fi
