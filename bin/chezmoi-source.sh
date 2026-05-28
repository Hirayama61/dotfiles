#!/usr/bin/env bash
# chezmoi-source.sh — source-aware な chezmoi --source 引数を解決する単一情報源。
#
# Usage: bin/chezmoi-source.sh <name>
#   <name> = 論理 repo キー(dotfiles / cc-dotfiles)。bin/sync.sh の NAME 引数と揃える。
#
# 出力(stdout, 改行なし):
#   - cwd の論理 repo キーが <name> と一致するとき: "--source <toplevel>"
#     ($PWD が属する git 作業ツリー(main clone or worktree)の root を source に渡す)。
#   - 一致しない / non-git / 引数なし: 空文字(呼び出し側は toml の sourceDir に fallback)。
#
# 設計意図:
#   chezmoi の sourceDir(toml)は main clone を指す。worktree 内で編集しても in-place では
#   読めないため、cwd が当該 repo の作業ツリーなら --source にその toplevel を渡し、
#   worktree 内の編集を apply/diff が読めるようにする(source-aware)。
#   別 repo(cc-dotfiles 等)の文脈で誤って dotfiles config を流しても、cwd の repo キーが
#   NAME と一致しなければ source を上書きしないので誤爆しない(toml fallback)。
#
# repo 同一性の判定:
#   resolve-repo-key.sh(doc-gravity / MOC の単一情報源)と同じ写像をインライン複製する。
#   git --git-common-dir を絶対化し、その親ディレクトリの basename を論理 repo キーとする。
#   common-dir は worktree でも main clone の .git を指すため、worktree でも main repo の
#   basename(dotfiles / cc-dotfiles)を返す。一方 --show-toplevel は worktree では branch leaf を
#   返すので、source 値はこちらを使う(同一性判定 = common-dir 親 basename / source 値 = toplevel)。
#   ※ 外部依存(~/.claude/hooks/lib/resolve-repo-key.sh)は持たない(自前計算)。

set -euo pipefail

NAME="${1:-}"
[[ -z "$NAME" ]] && exit 0

# cwd が git 作業ツリーでなければ source 上書きせず fallback。
toplevel="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || true)"
[[ -z "$toplevel" ]] && exit 0

# 論理 repo キー = git-common-dir(絶対化)の親 basename。
common_dir="$(git -C "$PWD" rev-parse --git-common-dir 2>/dev/null || true)"
[[ -z "$common_dir" ]] && exit 0
case "$common_dir" in
/*) ;;
*) common_dir="$PWD/$common_dir" ;;
esac
repo_root="$(cd "$common_dir/.." 2>/dev/null && pwd -P || true)"
[[ -z "$repo_root" ]] && exit 0
repo_key="$(basename -- "$repo_root")"

# cwd の repo キーが NAME と一致するときだけ source を上書きする。
if [[ "$repo_key" == "$NAME" ]]; then
  printf -- '--source %s' "$toplevel"
fi
