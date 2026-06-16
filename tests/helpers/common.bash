#!/usr/bin/env bash
# bats 共通ヘルパ(dotfiles のグローバル git hook)。
#
# pre-commit / commit-msg を、一時 HOME(機密語リストを置く)と一時 git repo
# (staged fixture)で直接起動して検証する。hook は $HOME/.config/git/sensitive-words.txt
# を読むため HOME を差し替える。repo は core.hooksPath を無効化し、hook スクリプトは
# bash で直接起動するため git 本体の hook 機構・再帰には依存しない。
#
# hook は secretlint/shfmt/shellcheck を `mise which|exec` で呼ぶが、実 mise を使うと
# 実 secretlint がテスト fixture を誤検出する等で非 hermetic になる。そこで mise を shim 化し、
# ツールは shim dir に置いた fake からのみ解決する。既定では何も置かない(= 全ツール段は
# `mise which` 失敗で skip)。あるツールの挙動を検証したいテストだけ fake_tool で仕込む。

HELPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HELPER_DIR/../.." && pwd)"
HOOKS_SRC="$REPO_ROOT/home/dot_config/git/hooks"
PRECOMMIT_HOOK="$HOOKS_SRC/private_executable_pre-commit"
COMMITMSG_HOOK="$HOOKS_SRC/private_executable_commit-msg"

setup_repo() {
  export TEST_HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$TEST_HOME/.config/git"
  export HOME="$TEST_HOME"

  # mise shim: which=shim dir に fake があれば成功 / exec=fake を実行 / where=不在。
  export MISE_SHIM_DIR="$BATS_TEST_TMPDIR/shim"
  mkdir -p "$MISE_SHIM_DIR"
  cat >"$MISE_SHIM_DIR/mise" <<'SH'
#!/usr/bin/env bash
cmd="${1:-}"; shift 2>/dev/null || true
case "$cmd" in
  which) [ -x "$MISE_SHIM_DIR/${1:-}" ] ;;
  exec) [ "${1:-}" = "--" ] && shift; t="${1:-}"; shift 2>/dev/null || true; exec "$MISE_SHIM_DIR/$t" "$@" ;;
  where) exit 1 ;;
  *) exit 0 ;;
esac
SH
  chmod +x "$MISE_SHIM_DIR/mise"
  export PATH="$MISE_SHIM_DIR:$PATH"

  export REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO"
  git -C "$REPO" init -q
  git -C "$REPO" config user.email test@example.com
  git -C "$REPO" config user.name test
  # hook 単体を直接起動するため、repo の git 操作では一切 hook を走らせない
  # (グローバル core.hooksPath の巻き込み・再帰を断つ)。存在しない dir を指す。
  git -C "$REPO" config core.hooksPath "$BATS_TEST_TMPDIR/nohooks"
}

# fake_tool <名前> [終了コード]: shim dir に fake ツールを置く(mise which/exec から解決される)。
fake_tool() {
  cat >"$MISE_SHIM_DIR/$1" <<SH
#!/usr/bin/env bash
exit ${2:-0}
SH
  chmod +x "$MISE_SHIM_DIR/$1"
}

# 整形対象ファイル(最終引数)を実際に書き換えて成功する fake shfmt。
# E-H1 の success 分岐(整形後ファイルの再 stage)を観測可能にする。
fake_shfmt_rewrites() {
  cat >"$MISE_SHIM_DIR/shfmt" <<'SH'
#!/usr/bin/env bash
for f; do :; done
printf 'FORMATTED\n' >"$f"
SH
  chmod +x "$MISE_SHIM_DIR/shfmt"
}

# 機密語リストを書く。%b で \r 等のエスケープを解釈する(CRLF テスト用)。
write_words() {
  printf '%b' "$1" >"$HOME/.config/git/sensitive-words.txt"
}

# stage_file <相対パス> <内容(1行)>
stage_file() {
  local path="$1" content="$2"
  mkdir -p "$(dirname "$REPO/$path")"
  printf '%s\n' "$content" >"$REPO/$path"
  git -C "$REPO" add "$path"
}

# fixture の前提作り用コミット(repo の hooks は無効化済みなので素通る)。
commit_repo() {
  git -C "$REPO" commit -q -m "$1"
}

# pre-commit を直接起動。$status / $output を設定。
run_precommit() {
  set +e
  output="$(cd "$REPO" && bash "$PRECOMMIT_HOOK" 2>&1)"
  status=$?
  set -e
}

# run_commitmsg <メッセージ>。一時メッセージファイルを作って commit-msg を起動。
run_commitmsg() {
  printf '%s\n' "$1" >"$BATS_TEST_TMPDIR/COMMIT_MSG"
  set +e
  output="$(cd "$REPO" && bash "$COMMITMSG_HOOK" "$BATS_TEST_TMPDIR/COMMIT_MSG" 2>&1)"
  status=$?
  set -e
}
