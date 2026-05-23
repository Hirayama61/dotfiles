#!/bin/sh
# ウィンドウ全体にフル幅/フル高の新バンド(行/列)を1本追加し、トップレベルの
# バンドどうしを均等化する。各バンド内の sub 分割(例: 1行の中の 2|3)は保持。
# select-layout even-* はウィンドウ全体をフラット化して sub 分割を壊すため使わない。
#
# 使い方: split-even.sh h   (フル高の列バンドを追加 / 列を均等幅)
#         split-even.sh v   (フル幅の行バンドを追加 / 行を均等高)

set -eu

dir="${1:-}"
case "$dir" in
  h|v) ;;
  *) echo "usage: split-even.sh h|v" >&2; exit 2 ;;
esac

# 分割元アクティブペインの実パスを解決する。
# run-shell 配下では #{pane_current_path} を shell が展開しないため tmux に解決させる。
src_pane=$(tmux display-message -p '#{pane_id}')
src_path=$(tmux display-message -p -t "$src_pane" '#{pane_current_path}')

# -f: ウィンドウ全幅/全高のフルバンドを追加(アクティブペインの sub 分割に閉じない)。
if [ "$dir" = h ]; then
  tmux split-window -fh -c "$src_path" -t "$src_pane"
else
  tmux split-window -fv -c "$src_path" -t "$src_pane"
fi

# 全ペインをトップレベルのバンドにグルーピングして均等化する。
# v(行を均等高): 同じ (pane_top,pane_bottom) を共有するペイン群 = 1 行バンド。
# h(列を均等幅): 同じ (pane_left,pane_right) を共有するペイン群 = 1 列バンド。
# 各バンドの代表ペイン 1 つを start 昇順に並べ、最後以外を resize して端を動かすと、
# バンド境界に追従して同バンド内の他ペイン(2|3 等)もサイズ・配置を保ったまま追従する。
# span = max(end)-min(start)+1(全ペイン横断)、content = span-(バンド間区切り n-1 本)、
# target = int(content/n) を最後以外の代表に適用し、最後のバンドが余りを吸収する。
#
# 限界: (top,bottom)/(left,right) グルーピングは各バンドがフル幅/フル高の前提で正しい。
# -f 運用ならトップレベルは常にフルバンドになり妥当だが、フル幅でない複雑なネストでは
# 行/列バンドと一致しない場合がある。
cmds=$(tmux list-panes -F '#{pane_id} #{pane_left} #{pane_right} #{pane_top} #{pane_bottom}' \
  | awk -v dir="$dir" '
    {
      id=$1; left=$2+0; right=$3+0; top=$4+0; bottom=$5+0
      if (dir == "v") { key = top "," bottom; start = top;  end = bottom }
      else            { key = left "," right; start = left; end = right }
      # 各バンドの代表ペイン(最初に見つけた1つ)だけ記録。
      if (!(key in seen)) {
        seen[key] = 1
        n++
        ids[n] = id; starts[n] = start; ends[n] = end
      }
      # span 算出用に全ペイン横断の最小 start / 最大 end を持つ。
      if (gotminmax == 0) { minstart = start; maxend = end; gotminmax = 1 }
      if (start < minstart) minstart = start
      if (end > maxend) maxend = end
    }
    END {
      if (n < 2) exit 0
      # バンド代表を start 昇順にソート(単純挿入ソート、n は小さい)。
      for (i = 2; i <= n; i++) {
        ks = starts[i]; ke = ends[i]; kid = ids[i]
        j = i - 1
        while (j >= 1 && starts[j] > ks) {
          starts[j+1]=starts[j]; ends[j+1]=ends[j]; ids[j+1]=ids[j]
          j--
        }
        starts[j+1]=ks; ends[j+1]=ke; ids[j+1]=kid
      }
      span = maxend - minstart + 1
      content = span - (n - 1)
      target = int(content / n)
      if (target < 1) exit 0
      flag = (dir == "v") ? "-y" : "-x"
      # 最後のバンド以外の代表を resize(最後が余りを吸収)。
      for (i = 1; i < n; i++) {
        print ids[i] " " flag " " target
      }
    }')

# awk が算出した resize を適用する。
if [ -n "$cmds" ]; then
  printf '%s\n' "$cmds" | while read -r pid flag size; do
    [ -n "$pid" ] || continue
    tmux resize-pane -t "$pid" "$flag" "$size"
  done
fi
