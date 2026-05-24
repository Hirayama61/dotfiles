#!/usr/bin/env bash
# フラット worktree ヘルパ — worktree 並行作業ワークフローの決定的部分を固める。
#
# Usage: bin/wt.sh <branch> [<base-ref>]
#
# 動作:
#   1. git リポ内(メイン clone でも worktree でも、共有 .git を操作)で実行される前提。
#      origin の URL を host/owner/repo にパースする。
#   2. gwq naming(~/worktrees/<host>/<owner>/<repo>/<branch>)に一致するフラット
#      目標パスを算出する。basedir(~/worktrees)と template はこのスクリプトに直書きで
#      結合している(下の WT_BASEDIR / NAMING コメント参照)。gwq config.toml の
#      [worktree].basedir / [naming].template と一致させて維持すること。
#   3. 冪等 + 二重 checkout ガード: 当該ブランチが算出パスで checkout 済みならその
#      パスを stdout に出して exit 0。別パスで checkout 済みなら naming ドリフトとして中断。
#   4. ブランチ解決:
#        - ローカルに存在        → git worktree add <path> <branch>
#        - remote に実在         → git fetch → git worktree add <path> --track -b <branch> origin/<branch>
#                                  (追跡 ref が無くても ls-remote で確認。未 fetch の
#                                   リモートブランチ=未取得の PR ブランチを取りこぼさないため。)
#        - 新規                  → base-ref(無ければ HEAD)から git worktree add <path> -b <branch> <base>
#      (gwq add は base-ref/--track 非対応なので raw git を使う。これが本スクリプトに固める核心。)
#   5. ネストガード: 算出パスが現リポ作業ツリー内に来る場合は拒否。親は mkdir -p。
#
# 出力: worktree の絶対パスを stdout に1行のみ。診断・エラーは stderr。
#       例: cd "$(bin/wt.sh feature/x)"

set -euo pipefail

# ── 引数チェック ───────────────────────────────────────
if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 <branch> [<base-ref>]" >&2
  exit 1
fi

BRANCH="$1"
BASE_REF="${2:-}"

if [[ -z "$BRANCH" ]]; then
  echo "wt.sh: ブランチ名が空です。" >&2
  exit 1
fi

# ── git リポ内か確認 ──────────────────────────────────
if ! git rev-parse --git-dir &>/dev/null; then
  echo "wt.sh: git リポジトリ内で実行してください。" >&2
  exit 1
fi

# ── origin URL を host/owner/repo にパース ────────────
# git@host:owner/repo(.git) と https://host/owner/repo(.git) の両対応。
ORIGIN_URL="$(git remote get-url origin 2>/dev/null || true)"
if [[ -z "$ORIGIN_URL" ]]; then
  echo "wt.sh: origin リモートがありません。host/owner/repo を解決できません。" >&2
  exit 1
fi

# scheme/credential を剥がして host/path を取り出す。
url="$ORIGIN_URL"
url="${url%.git}" # 末尾 .git を除去
if [[ "$url" == git@*:* ]]; then
  # SCP 風: git@host:owner/repo
  host="${url#git@}"
  host="${host%%:*}"
  path="${url#*:}"
elif [[ "$url" == ssh://* || "$url" == https://* || "$url" == http://* ]]; then
  # URL 風: scheme://[user@]host/owner/repo
  rest="${url#*://}"
  rest="${rest#*@}" # user@ があれば除去
  host="${rest%%/*}"
  host="${host%%:*}" # host:port があれば port 除去
  path="${rest#*/}"
else
  echo "wt.sh: origin URL の形式を解釈できません: $ORIGIN_URL" >&2
  exit 1
fi

# path は owner/repo を期待(2 セグメント以上必須)。
if [[ "$path" != */* ]]; then
  echo "wt.sh: origin URL から host/owner/repo を解決できません: $ORIGIN_URL" >&2
  exit 1
fi
owner="${path%%/*}"
repo="${path#*/}"
if [[ -z "$host" || -z "$owner" || -z "$repo" ]]; then
  echo "wt.sh: origin URL から host/owner/repo を解決できません: $ORIGIN_URL" >&2
  exit 1
fi

# ── 目標パスを gwq naming に一致させて算出 ────────────
# WT_BASEDIR = gwq config [worktree].basedir、NAMING = [naming].template の展開。
#   template: {{.Host}}/{{.Owner}}/{{.Repository}}/{{.Branch}}
# ブランチ名の "/" はサブディレクトリになる(gwq と同じ)。
WT_BASEDIR="$HOME/worktrees"
TARGET="$WT_BASEDIR/$host/$owner/$repo/$BRANCH"

# ── ネストガード: 現リポ作業ツリー内に来ないか ────────
TOPLEVEL="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -n "$TOPLEVEL" && "$TARGET" == "$TOPLEVEL"/* ]]; then
  echo "wt.sh: 算出パスが現作業ツリー内です(ネスト禁止): $TARGET" >&2
  exit 1
fi

# ── 既存 worktree 検出(冪等 + 二重 checkout ガード)──
# git worktree list --porcelain を走査し refs/heads/<BRANCH> を checkout 済みの
# worktree パスを探す。git は同一ブランチを複数 worktree で checkout できないため、
# hit すれば唯一の占有先。それが算出 TARGET と一致なら冪等に再利用、別パスなら
# naming ドリフトとして中断する(素手作成や旧 naming の名残を握り潰さない)。
checked_out_at=""
current_wt=""
while IFS= read -r ln; do
  case "$ln" in
  "worktree "*) current_wt="${ln#worktree }" ;;
  "branch refs/heads/$BRANCH") checked_out_at="$current_wt" ;;
  esac
done < <(git worktree list --porcelain)

if [[ -n "$checked_out_at" ]]; then
  if [[ "$checked_out_at" == "$TARGET" ]]; then
    echo "wt.sh: 既存 worktree を再利用: $checked_out_at" >&2
    echo "$checked_out_at"
    exit 0
  fi
  echo "wt.sh: ブランチ '$BRANCH' は別パスで checkout 済みです: $checked_out_at" >&2
  echo "wt.sh: (算出パス $TARGET と不一致。手動で整理してください)" >&2
  exit 1
fi

# ── 親ディレクトリ生成 ────────────────────────────────
mkdir -p "$(dirname "$TARGET")"

# ── ブランチ解決の分岐 ────────────────────────────────
# 順序の意図: ①ローカル存在 ②リモート追跡 ref 既存 or ls-remote でリモート実在
# → fetch+track ③どこにも無い → 新規(base/HEAD)。
# ②の ls-remote は、まだ fetch していないリモートブランチ(典型: 未取得の PR
# ブランチ)を取りこぼさないため。これが無いと「新規」分岐に落ち HEAD から誤った
# 土台で作ってしまう。ネットワーク呼び出しは「新規」候補時のみ走る(許容)。
if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
  # ローカルに存在
  echo "wt.sh: ローカルブランチ '$BRANCH' を worktree 化: $TARGET" >&2
  git worktree add "$TARGET" "$BRANCH" >&2
elif git show-ref --verify --quiet "refs/remotes/origin/$BRANCH" ||
  git ls-remote --exit-code --heads origin "$BRANCH" &>/dev/null; then
  # remote に実在(追跡 ref 既存 or 未 fetch でもリモートにある)。
  # gwq add は --track 非対応なので raw git で追跡ブランチを作る。
  # 既存ブランチは新規作成できないため、base-ref 指定があっても追跡作成を優先する。
  echo "wt.sh: remote ブランチ 'origin/$BRANCH' を fetch して追跡 worktree 化: $TARGET" >&2
  git fetch origin "$BRANCH" >&2
  git worktree add "$TARGET" --track -b "$BRANCH" "origin/$BRANCH" >&2
else
  # 新規(ローカルにも remote にも本当に無い)
  base="${BASE_REF:-HEAD}"
  echo "wt.sh: 新規ブランチ '$BRANCH' を '$base' から作成: $TARGET" >&2
  git worktree add "$TARGET" -b "$BRANCH" "$base" >&2
fi

# ── 成功: 絶対パスを stdout に1行だけ ─────────────────
echo "$TARGET"
