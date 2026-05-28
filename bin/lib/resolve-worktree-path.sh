#!/usr/bin/env bash
# resolve-worktree-path.sh — フラット worktree のパス導出を単一情報源化する純関数ライブラリ。
#
# 「どこに worktree を作るか」(origin URL → host/owner/repo → ~/worktrees/.../<branch>)は
# worktree 並行作業ワークフローの核であり、bin/wt.sh(素手作成を強制する正規パス)と
# cc-dotfiles の WorktreeCreate hook(Claude Code ネイティブ worktree のリダイレクト)の
# 双方で同一でなければならない。両者がこの lib を source し同じ関数を呼ぶことで drift を
# 構造的に防ぐ(決定: Decisions/2026-05-29-Workflow機能の採用方針とworktree統合.md = a1)。
#
# 責務境界: ここは純粋なパス導出のみ(副作用なし)。git remote get-url の I/O は行うが、
# worktree 作成・冪等検出・二重 checkout ガード・ブランチ解決は呼び出し側(wt.sh)が持つ。
# WorktreeCreate hook は「配置先パスを返すだけ」で git worktree add は Claude Code 本体が
# 実行するため、hook はこの lib の純関数だけを使う。
#
# bash 3.2 互換(macOS 既定): 連想配列(declare -A)・`grep -P`・`${var,,}` を使わない。
# パラメータ展開によるパースのみで外部コマンド依存を最小化する。
#
# set -euo pipefail はトップに置かない(source 時に呼び出し元シェルの set 状態を汚染する)。
# 関数は呼び出し元が非 strict でも自衛する(空ガード / 2>/dev/null)。strict 化は直接実行
# ガード内でのみ行う(cc-dotfiles の resolve-repo-key.sh / resolve-git-target.sh と同作法)。

# origin URL を "host/owner/repo" の3要素にパースし、改行区切り3行で返す(host \n owner \n repo)。
# git@host:owner/repo(.git) と [scheme://[user@]host[:port]/]owner/repo(.git) の両対応。
# パース不能(空 URL / 形式不明 / owner/repo 2 セグメント未満)なら何も出力せず return 1。
parse_origin_url() {
  local url="${1:-}"
  [[ -z "$url" ]] && return 1

  local host path rest
  url="${url%.git}" # 末尾 .git を除去
  if [[ "$url" == git@*:* ]]; then
    # SCP 風: git@host:owner/repo
    host="${url#git@}"
    host="${host%%:*}"
    path="${url#*:}"
  elif [[ "$url" == ssh://* || "$url" == https://* || "$url" == http://* ]]; then
    # URL 風: scheme://[user@]host[:port]/owner/repo
    rest="${url#*://}"
    rest="${rest#*@}" # user@ があれば除去
    host="${rest%%/*}"
    host="${host%%:*}" # host:port があれば port 除去
    path="${rest#*/}"
  else
    return 1
  fi

  # path は owner/repo を期待(2 セグメント以上必須)。
  [[ "$path" != */* ]] && return 1
  local owner repo
  owner="${path%%/*}"
  repo="${path#*/}"
  [[ -z "$host" || -z "$owner" || -z "$repo" ]] && return 1

  printf '%s\n%s\n%s\n' "$host" "$owner" "$repo"
}

# branch 名がパス構築に安全かを検証する(パストラバーサル防止)。安全なら return 0、
# 危険なら return 1(無出力)。branch は target パスの末尾セグメント群になるため、
# `..` による親への脱出・絶対パス化・ホーム展開・制御文字を遮断する。
# bash 3.2 互換: パラメータ展開と `case` のみ(grep / 正規表現に依存しない)。
# 注: `/` 自体は許可する(gwq naming でサブディレクトリになる正規の挙動)。
_branch_is_safe_for_path() {
  local b="${1:-}"
  [[ -z "$b" ]] && return 1
  # 先頭 / (絶対パス化)・先頭 ~ (ホーム展開)を拒否。
  case "$b" in
  /* | "~"*) return 1 ;;
  esac
  # `//` 連続(空セグメント)を拒否。
  case "$b" in
  *//*) return 1 ;;
  esac
  # `..` をパスセグメントとして含むものを拒否:
  #   ".." 単体 / 先頭 "../" / 末尾 "/.." / 中間 "/../"。
  case "$b" in
  ".." | "../"* | *"/.." | *"/../"*) return 1 ;;
  esac
  # 制御文字・改行を拒否(printf %q ではなく case で NL/TAB/CR を素朴に検出)。
  # bash 3.2: $'\n' 等は使えるので case パターンに直接埋める。
  case "$b" in
  *$'\n'* | *$'\r'* | *$'\t'*) return 1 ;;
  esac
  return 0
}

# host/owner/repo/branch から gwq naming に一致するフラット目標パスを組む。
# WT_BASEDIR = gwq config [worktree].basedir、NAMING = [naming].template の展開:
#   template: {{.Host}}/{{.Owner}}/{{.Repository}}/{{.Branch}}
# gwq config.toml の basedir / template と一致させて維持すること。
# ブランチ名の "/" はサブディレクトリになる(gwq と同挙動)。
# 引数のいずれかが空なら return 1。
# branch 名が `..`/絶対パス等で WT_BASEDIR 外へ脱出しうる場合も return 1(F-001 対策)。
worktree_target_path() {
  local host="${1:-}" owner="${2:-}" repo="${3:-}" branch="${4:-}"
  [[ -z "$host" || -z "$owner" || -z "$repo" || -z "$branch" ]] && return 1
  # host/owner/repo は origin URL 由来だが、branch は呼び出し側引数で最も信頼できないため
  # ここでパストラバーサルを遮断する(両経路=wt.sh / WorktreeCreate hook の choke point)。
  _branch_is_safe_for_path "$branch" || return 1
  local wt_basedir="$HOME/worktrees"
  local target="$wt_basedir/$host/$owner/$repo/$branch"
  # 防御の二重化: 算出 target が必ず WT_BASEDIR 配下に収まることを接頭辞一致で確認する。
  # `..` 遮断(上)で論理的には担保済みだが、host/owner/repo 側の想定外値も含め最終ガードする。
  case "$target" in
  "$wt_basedir"/*) ;;
  *) return 1 ;;
  esac
  printf '%s\n' "$target"
}

# repo dir と branch から ~/worktrees/<host>/<owner>/<repo>/<branch> を導出する高水準関数。
# repo_dir(省略時はカレント)で `git -C` を使い origin URL を取得 → parse → target を組む。
# origin 無し / git 外 / パース不能 / branch 空 のいずれでも何も出力せず return 1(呼び出し側が
# 安全フォールバックを決める)。
resolve_worktree_path() {
  local branch="${1:-}" repo_dir="${2:-.}"
  [[ -z "$branch" ]] && return 1

  local origin_url
  origin_url="$(git -C "$repo_dir" remote get-url origin 2>/dev/null || true)"
  [[ -z "$origin_url" ]] && return 1

  local parsed host owner repo
  parsed="$(parse_origin_url "$origin_url")" || return 1
  # 改行区切り3行を read で分解(bash 3.2 互換)。
  { IFS= read -r host && IFS= read -r owner && IFS= read -r repo; } <<EOF
$parsed
EOF
  worktree_target_path "$host" "$owner" "$repo" "$branch"
}

# 直接実行時は resolve_worktree_path のCLIとして振る舞う(単体テスト用)。
# Usage: resolve-worktree-path.sh <branch> [<repo-dir>]
if [[ "${BASH_SOURCE[0]:-}" == "${0}" ]]; then
  set -euo pipefail
  resolve_worktree_path "${1:-}" "${2:-.}"
fi
