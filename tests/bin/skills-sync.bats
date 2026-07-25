#!/usr/bin/env bats
# bin/skills-sync.sh の E2E(hermetic)。
#
# スクリプトは MANIFEST を自身の親ディレクトリ相対で解決するため、一時 repo
# ($BATS_TEST_TMPDIR/fake-repo)へ複製して manifest を制御する。ghq は PATH shim 化し
# (get=noop / root=fake root)、HOME も一時側へ差し替えるため本物の ~/.claude には
# 一切触れない。検証の焦点:
#   - ローカル進化ソース(~/.claude-evolution/active)の symlink 作成
#   - 作成側の衝突ガード(宛先が実体なら WARN + skip。chezmoi 実体を壊さない)
#   - --local-only(ghq 同期・prune の全スキップ)
#   - prune の非破壊条件(failed>0 / --local-only で抑止)
#   - 管理外エントリの検出(報告のみ。削除も exit code 変更もしない)
#   - --check(宣言 ↔ symlink の照合。ghq 非呼出・副作用ゼロ・欠落で exit 1)

setup() {
  export TEST_HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$TEST_HOME"
  export HOME="$TEST_HOME"

  # スクリプトを一時 repo へ複製(manifest 制御のため)。
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  FAKE_REPO="$BATS_TEST_TMPDIR/fake-repo"
  mkdir -p "$FAKE_REPO/bin"
  install -m 755 "$REPO_ROOT/bin/skills-sync.sh" "$FAKE_REPO/bin/skills-sync.sh"
  : >"$FAKE_REPO/ext-skills.txt"

  # ghq shim: get は noop、root は fake root を返す。
  export FAKE_GHQ_ROOT="$BATS_TEST_TMPDIR/ghq"
  mkdir -p "$FAKE_GHQ_ROOT"
  local shim="$BATS_TEST_TMPDIR/shim"
  mkdir -p "$shim"
  cat >"$shim/ghq" <<'SH'
#!/usr/bin/env bash
case "${1:-}" in
  get) exit 0 ;;
  root) printf '%s\n' "$FAKE_GHQ_ROOT" ;;
  *) exit 0 ;;
esac
SH
  chmod +x "$shim/ghq"
  export PATH="$shim:$PATH"
  export GHQ_TRACE="$BATS_TEST_TMPDIR/ghq-called"
  SHIM_DIR="$shim"

  # chezmoi ソース(cc-dotfiles)も一時側へ向ける。既定では作らない = 実 repo を見に
  # 行かせないまま「repo 不在」経路になる。
  export CC_DOTFILES_DIR="$BATS_TEST_TMPDIR/cc-dotfiles"
  CC_SKILLS="$CC_DOTFILES_DIR/home/dot_claude/skills"
  CC_AGENTS="$CC_DOTFILES_DIR/home/dot_claude/agents"

  SYNC="$FAKE_REPO/bin/skills-sync.sh"
  SKILLS_DIR="$HOME/.claude/skills"
  AGENTS_DIR="$HOME/.claude/agents"
  EVOLVE="$HOME/.claude-evolution"
}

_seed_cc_source() { mkdir -p "$CC_SKILLS" "$CC_AGENTS"; }

# 出力照合。macOS 同梱の bash 3.2 は set -e で [[ ]] の失敗を無視するため、末尾以外に
# 置いた [[ ]] アサーションは空振りする。関数呼び出しなら失敗が伝播する。
_has() { case "$2" in *"$1"*) return 0 ;; *) return 1 ;; esac; }
_lacks() { case "$2" in *"$1"*) return 1 ;; *) return 0 ;; esac; }

# ghq が呼ばれたら $GHQ_TRACE に痕跡を残す shim へ差し替える(--check の非呼出検証用)。
_trace_ghq() {
  cat >"$SHIM_DIR/ghq" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$GHQ_TRACE"
exit 0
SH
  chmod +x "$SHIM_DIR/ghq"
}

_seed_active_skill() {
  mkdir -p "$EVOLVE/active/skills/$1"
  printf '# %s\n' "$1" >"$EVOLVE/active/skills/$1/SKILL.md"
}

_seed_active_agent() {
  mkdir -p "$EVOLVE/active/agents"
  printf '# %s\n' "$1" >"$EVOLVE/active/agents/$1.md"
}

_seed_ext_skill() { # <owner/repo> <subdir> <name>
  mkdir -p "$FAKE_GHQ_ROOT/github.com/$1/$2/$3"
  printf '# %s\n' "$3" >"$FAKE_GHQ_ROOT/github.com/$1/$2/$3/SKILL.md"
}

@test "local-only: evolution dir absent is normal (exit 0, no links)" {
  run "$SYNC" --local-only
  [ "$status" -eq 0 ]
  _has 'linked=0' "$output"
}

@test "local-only: links active skill into ~/.claude/skills" {
  _seed_active_skill my-learned
  run "$SYNC" --local-only
  [ "$status" -eq 0 ]
  [ -L "$SKILLS_DIR/my-learned" ]
  [ -f "$SKILLS_DIR/my-learned/SKILL.md" ]
}

@test "local-only: links active agent into ~/.claude/agents" {
  _seed_active_agent my-agent
  run "$SYNC" --local-only
  [ "$status" -eq 0 ]
  [ -L "$AGENTS_DIR/my-agent.md" ]
}

@test "local-only: collision guard keeps chezmoi real dir intact (WARN + exit 1)" {
  mkdir -p "$SKILLS_DIR/self-review"
  printf 'real\n' >"$SKILLS_DIR/self-review/SKILL.md"
  _seed_active_skill self-review
  run "$SYNC" --local-only
  [ "$status" -eq 1 ]
  _has 'WARN' "$output"
  [ ! -L "$SKILLS_DIR/self-review" ]
  [ "$(cat "$SKILLS_DIR/self-review/SKILL.md")" = "real" ]
}

@test "local-only: collision guard keeps real agent file intact" {
  mkdir -p "$AGENTS_DIR"
  printf 'real-agent\n' >"$AGENTS_DIR/delegate.md"
  _seed_active_agent delegate
  run "$SYNC" --local-only
  [ "$status" -eq 1 ]
  [ ! -L "$AGENTS_DIR/delegate.md" ]
  [ "$(cat "$AGENTS_DIR/delegate.md")" = "real-agent" ]
}

@test "local-only: never prunes existing unrelated symlinks" {
  mkdir -p "$SKILLS_DIR" "$BATS_TEST_TMPDIR/elsewhere"
  ln -s "$BATS_TEST_TMPDIR/elsewhere" "$SKILLS_DIR/ext-thing"
  _seed_active_skill my-learned
  run "$SYNC" --local-only
  [ "$status" -eq 0 ]
  [ -L "$SKILLS_DIR/ext-thing" ]
}

@test "full: manifest skill + local active both linked, stale symlink pruned" {
  _seed_ext_skill owner/repo skills ext-skill
  printf 'owner/repo\n' >"$FAKE_REPO/ext-skills.txt"
  _seed_active_skill my-learned
  mkdir -p "$SKILLS_DIR" "$BATS_TEST_TMPDIR/stale"
  ln -s "$BATS_TEST_TMPDIR/stale" "$SKILLS_DIR/stale-skill"
  run "$SYNC"
  [ "$status" -eq 0 ]
  [ -L "$SKILLS_DIR/ext-skill" ]
  [ -L "$SKILLS_DIR/my-learned" ]
  [ ! -e "$SKILLS_DIR/stale-skill" ]
}

@test "full: prune does not touch real (non-symlink) skill dirs" {
  mkdir -p "$SKILLS_DIR/obsidian-memory"
  printf 'real\n' >"$SKILLS_DIR/obsidian-memory/SKILL.md"
  run "$SYNC"
  [ "$status" -eq 0 ]
  [ -d "$SKILLS_DIR/obsidian-memory" ]
  [ ! -L "$SKILLS_DIR/obsidian-memory" ]
}

@test "full: agent prune removes stale evolution-owned symlink, keeps active one" {
  _seed_active_agent my-agent
  mkdir -p "$AGENTS_DIR"
  ln -s "$EVOLVE/active/agents/removed-agent.md" "$AGENTS_DIR/removed-agent.md"
  run "$SYNC"
  [ "$status" -eq 0 ]
  [ -L "$AGENTS_DIR/my-agent.md" ]
  [ ! -L "$AGENTS_DIR/removed-agent.md" ]
}

@test "full: agent prune leaves symlinks not owned by evolution dir" {
  mkdir -p "$AGENTS_DIR" "$BATS_TEST_TMPDIR/manual"
  printf 'manual\n' >"$BATS_TEST_TMPDIR/manual/hand.md"
  ln -s "$BATS_TEST_TMPDIR/manual/hand.md" "$AGENTS_DIR/hand.md"
  run "$SYNC"
  [ "$status" -eq 0 ]
  [ -L "$AGENTS_DIR/hand.md" ]
}

@test "local-only: symlink entries inside active/ are ignored (candidates stay inert)" {
  mkdir -p "$EVOLVE/candidates/skills/sneaky" "$EVOLVE/active/skills"
  printf '# sneaky\n' >"$EVOLVE/candidates/skills/sneaky/SKILL.md"
  ln -s "$EVOLVE/candidates/skills/sneaky" "$EVOLVE/active/skills/sneaky"
  run "$SYNC" --local-only
  [ "$status" -eq 0 ]
  [ ! -e "$SKILLS_DIR/sneaky" ]
}

@test "local-only: active/skills dir itself being a symlink is fully skipped" {
  mkdir -p "$EVOLVE/candidates/skills/sneaky" "$EVOLVE/active"
  printf '# sneaky\n' >"$EVOLVE/candidates/skills/sneaky/SKILL.md"
  ln -s "$EVOLVE/candidates/skills" "$EVOLVE/active/skills"
  run "$SYNC" --local-only
  [ "$status" -eq 1 ]
  _has '階層が symlink' "$output"
  [ ! -e "$SKILLS_DIR/sneaky" ]
}

@test "local-only: names outside ^[a-z0-9-]+$ (e.g. .prev leftovers) are not linked" {
  _seed_active_skill my-learned
  mkdir -p "$EVOLVE/active/skills/my-learned.prev"
  printf '# old\n' >"$EVOLVE/active/skills/my-learned.prev/SKILL.md"
  run "$SYNC" --local-only
  [ "$status" -eq 0 ]
  [ -L "$SKILLS_DIR/my-learned" ]
  [ ! -e "$SKILLS_DIR/my-learned.prev" ]
}

@test "full: manifest line with leading dash is rejected" {
  printf -- '-shallow/repo\n' >"$FAKE_REPO/ext-skills.txt"
  run "$SYNC"
  [ "$status" -eq 1 ]
  _has '不正な manifest 行' "$output"
}

@test "full: manifest line with traversal is rejected (WARN + no link, prune suppressed)" {
  printf 'owner/repo:../../evil\n' >"$FAKE_REPO/ext-skills.txt"
  mkdir -p "$SKILLS_DIR" "$BATS_TEST_TMPDIR/keep"
  ln -s "$BATS_TEST_TMPDIR/keep" "$SKILLS_DIR/keep-me"
  run "$SYNC"
  [ "$status" -eq 1 ]
  _has '不正な manifest 行' "$output"
  [ -L "$SKILLS_DIR/keep-me" ]
}

@test "full: manifest without trailing newline still processes last line" {
  _seed_ext_skill owner/repo skills ext-skill
  printf '%s' 'owner/repo' >"$FAKE_REPO/ext-skills.txt"
  run "$SYNC"
  [ "$status" -eq 0 ]
  [ -L "$SKILLS_DIR/ext-skill" ]
}

@test "full: single skill via symlinked intermediate dir escaping repo is skipped" {
  # skills2 が repo 外を指す symlink 中間ディレクトリ(中に正当な SKILL.md を含む)。
  # leaf 検査は素通りするため、実体パス封じ込めで repo 外 WARN skip されることを固定する。
  mkdir -p "$BATS_TEST_TMPDIR/outside/ext-skill"
  printf '# ext-skill\n' >"$BATS_TEST_TMPDIR/outside/ext-skill/SKILL.md"
  mkdir -p "$FAKE_GHQ_ROOT/github.com/owner/repo"
  ln -s "$BATS_TEST_TMPDIR/outside" "$FAKE_GHQ_ROOT/github.com/owner/repo/skills2"
  printf 'owner/repo:skills2\n' >"$FAKE_REPO/ext-skills.txt"
  run "$SYNC"
  [ "$status" -eq 1 ]
  _has 'repo 外を指す skill' "$output"
  [ ! -e "$SKILLS_DIR/ext-skill" ]
}

@test "local-only: works without ghq on PATH" {
  local shim2="$BATS_TEST_TMPDIR/noghq-bin"
  mkdir -p "$shim2"
  local c p
  for c in bash sh env cat grep sed tr cut basename dirname mkdir rm ln readlink pwd chmod; do
    p="$(command -v "$c" 2>/dev/null)" || continue
    ln -sf "$p" "$shim2/$c"
  done
  _seed_active_skill my-learned
  run env PATH="$shim2" "$SYNC" --local-only
  [ "$status" -eq 0 ]
  [ -L "$SKILLS_DIR/my-learned" ]
}

@test "full: failed sync (bad manifest path) suppresses prune" {
  printf 'owner/repo/skills/no-such-skill\n' >"$FAKE_REPO/ext-skills.txt"
  mkdir -p "$SKILLS_DIR" "$BATS_TEST_TMPDIR/keep"
  ln -s "$BATS_TEST_TMPDIR/keep" "$SKILLS_DIR/keep-me"
  run "$SYNC"
  [ "$status" -eq 1 ]
  _has 'prune を抑止' "$output"
  [ -L "$SKILLS_DIR/keep-me" ]
}

@test "full: collision failure also suppresses prune (wanted incomplete)" {
  mkdir -p "$SKILLS_DIR/self-review"
  printf 'real\n' >"$SKILLS_DIR/self-review/SKILL.md"
  _seed_active_skill self-review
  mkdir -p "$BATS_TEST_TMPDIR/keep"
  ln -s "$BATS_TEST_TMPDIR/keep" "$SKILLS_DIR/keep-me"
  run "$SYNC"
  [ "$status" -eq 1 ]
  [ -L "$SKILLS_DIR/keep-me" ]
}

@test "unmanaged: real skill dir with no chezmoi source is reported, never removed" {
  _seed_cc_source
  mkdir -p "$SKILLS_DIR/hand-placed"
  printf 'real\n' >"$SKILLS_DIR/hand-placed/SKILL.md"
  run "$SYNC"
  [ "$status" -eq 0 ]
  _has '管理外' "$output"
  _has 'unmanaged=1' "$output"
  [ -d "$SKILLS_DIR/hand-placed" ]
  [ "$(cat "$SKILLS_DIR/hand-placed/SKILL.md")" = "real" ]
}

@test "unmanaged: real skill dir backed by chezmoi source is not reported" {
  _seed_cc_source
  mkdir -p "$CC_SKILLS/obsidian-memory" "$SKILLS_DIR/obsidian-memory"
  printf 'real\n' >"$SKILLS_DIR/obsidian-memory/SKILL.md"
  run "$SYNC"
  [ "$status" -eq 0 ]
  _has 'unmanaged=0' "$output"
  _lacks '管理外' "$output"
}

@test "unmanaged: real agent file with no chezmoi source is reported, never removed" {
  _seed_cc_source
  mkdir -p "$AGENTS_DIR"
  printf 'hand\n' >"$AGENTS_DIR/hand.md"
  run "$SYNC"
  [ "$status" -eq 0 ]
  _has 'unmanaged=1' "$output"
  [ -f "$AGENTS_DIR/hand.md" ]
  [ ! -L "$AGENTS_DIR/hand.md" ]
}

@test "unmanaged: detection is skipped when cc-dotfiles source is absent" {
  # 未 clone は正規の状態。数値 0 を出すと「検査して 0 件」と区別が付かないため、
  # スキップしたことがサマリーから読み取れることを固定する。
  mkdir -p "$SKILLS_DIR/hand-placed"
  printf 'real\n' >"$SKILLS_DIR/hand-placed/SKILL.md"
  run "$SYNC"
  [ "$status" -eq 0 ]
  _has 'unmanaged=skipped(' "$output"
  _lacks 'unmanaged=0' "$output"
  _lacks 'WARN: 管理外' "$output"
}

@test "unmanaged: presence changes neither prune count nor exit code" {
  _seed_cc_source
  mkdir -p "$SKILLS_DIR" "$BATS_TEST_TMPDIR/stale"
  ln -s "$BATS_TEST_TMPDIR/stale" "$SKILLS_DIR/stale-skill"
  run "$SYNC"
  [ "$status" -eq 0 ]
  _has 'pruned=1' "$output"
  _has 'unmanaged=0' "$output"

  mkdir -p "$SKILLS_DIR/hand-placed"
  ln -s "$BATS_TEST_TMPDIR/stale" "$SKILLS_DIR/stale-skill"
  run "$SYNC"
  [ "$status" -eq 0 ]
  _has 'pruned=1' "$output"
  _has 'unmanaged=1' "$output"
}

@test "check: declared symlink in place -> exit 0 without calling ghq" {
  _seed_ext_skill owner/repo skills ext-skill
  printf 'owner/repo/skills/ext-skill\n' >"$FAKE_REPO/ext-skills.txt"
  mkdir -p "$SKILLS_DIR"
  ln -s "$FAKE_GHQ_ROOT/github.com/owner/repo/skills/ext-skill" "$SKILLS_DIR/ext-skill"
  _trace_ghq
  run "$SYNC" --check
  [ "$status" -eq 0 ]
  _has 'checked=1 missing=0' "$output"
  [ ! -e "$GHQ_TRACE" ]
}

@test "check: missing symlink -> exit 1 naming the skill, without calling ghq" {
  _seed_ext_skill owner/repo skills ext-skill
  printf 'owner/repo/skills/ext-skill\n' >"$FAKE_REPO/ext-skills.txt"
  _trace_ghq
  run "$SYNC" --check
  [ "$status" -eq 1 ]
  _has 'missing: ext-skill' "$output"
  [ ! -e "$GHQ_TRACE" ]
}

@test "check: dangling symlink counts as missing" {
  printf 'owner/repo/skills/ext-skill\n' >"$FAKE_REPO/ext-skills.txt"
  mkdir -p "$SKILLS_DIR"
  ln -s "$BATS_TEST_TMPDIR/gone/ext-skill" "$SKILLS_DIR/ext-skill"
  run "$SYNC" --check
  [ "$status" -eq 1 ]
  _has 'missing: ext-skill' "$output"
}

@test "check: creates nothing and prunes nothing" {
  printf 'owner/repo/skills/ext-skill\n' >"$FAKE_REPO/ext-skills.txt"
  mkdir -p "$SKILLS_DIR" "$BATS_TEST_TMPDIR/stale"
  ln -s "$BATS_TEST_TMPDIR/stale" "$SKILLS_DIR/stale-skill"
  run "$SYNC" --check
  [ "$status" -eq 1 ]
  [ -L "$SKILLS_DIR/stale-skill" ]
  [ ! -e "$AGENTS_DIR" ]
}

@test "check: does not create the skills dir when it is absent" {
  printf 'owner/repo/skills/ext-skill\n' >"$FAKE_REPO/ext-skills.txt"
  run "$SYNC" --check
  [ "$status" -eq 1 ]
  [ ! -e "$SKILLS_DIR" ]
}

@test "check: multi-form declarations are counted as skipped, not silently ignored" {
  printf 'owner/repo\n' >"$FAKE_REPO/ext-skills.txt"
  _trace_ghq
  run "$SYNC" --check
  [ "$status" -eq 0 ]
  _has 'checked=0' "$output"
  _has 'skipped=1' "$output"
  [ ! -e "$GHQ_TRACE" ]
}

@test "check: invalid manifest line is reported and exits 1" {
  printf -- '-shallow/repo\n' >"$FAKE_REPO/ext-skills.txt"
  run "$SYNC" --check
  [ "$status" -eq 1 ]
  _has 'invalid: -shallow/repo' "$output"
}

@test "check: symlink pointing outside the declared repo is a mismatch, not green" {
  # skill の中身はモデルが読む指示文なので、名前が合っていても向き先が別なら差し替えが
  # 成立する。存在確認だけで緑にしないことを固定する。
  _seed_ext_skill owner/repo skills ext-skill
  mkdir -p "$BATS_TEST_TMPDIR/attacker/ext-skill"
  printf '# other\n' >"$BATS_TEST_TMPDIR/attacker/ext-skill/SKILL.md"
  printf 'owner/repo/skills/ext-skill\n' >"$FAKE_REPO/ext-skills.txt"
  mkdir -p "$SKILLS_DIR"
  ln -s "$BATS_TEST_TMPDIR/attacker/ext-skill" "$SKILLS_DIR/ext-skill"
  _trace_ghq
  run "$SYNC" --check
  [ "$status" -eq 1 ]
  _has 'mismatch: ext-skill' "$output"
  _has 'missing=0 mismatch=1' "$output"
  [ ! -e "$GHQ_TRACE" ]
}

@test "check: a skill overridden by local evolution is not a mismatch" {
  # 同名 skill が両ソースにあるとローカル進化が勝つのは仕様(スクリプト冒頭)。full sync が
  # exit 0 で作る状態を --check が赤にすると、緑の同期直後に恒常的な赤が出る。
  _seed_ext_skill owner/repo skills ext-skill
  _seed_active_skill ext-skill
  printf 'owner/repo/skills/ext-skill\n' >"$FAKE_REPO/ext-skills.txt"
  mkdir -p "$SKILLS_DIR"
  ln -s "$EVOLVE/active/skills/ext-skill" "$SKILLS_DIR/ext-skill"
  run "$SYNC" --check
  [ "$status" -eq 0 ]
  _has 'checked=1 missing=0 mismatch=0' "$output"
  _lacks 'mismatch: ext-skill' "$output"
}

@test "check: evolution hierarchy symlink is a mismatch, matching full sync" {
  # active/skills を candidates/skills へ向けると人間ゲート前の候補が効力を持つ。
  # full sync は全 skip + failed にする状態なので、--check だけ緑にしない。
  _seed_ext_skill owner/repo skills ext-skill
  mkdir -p "$EVOLVE/active" "$EVOLVE/candidates/skills/ext-skill"
  printf '# candidate\n' >"$EVOLVE/candidates/skills/ext-skill/SKILL.md"
  ln -s "$EVOLVE/candidates/skills" "$EVOLVE/active/skills"
  printf 'owner/repo/skills/ext-skill\n' >"$FAKE_REPO/ext-skills.txt"
  mkdir -p "$SKILLS_DIR"
  ln -s "$EVOLVE/active/skills/ext-skill" "$SKILLS_DIR/ext-skill"
  run "$SYNC" --check
  [ "$status" -eq 1 ]
  _has 'mismatch: ext-skill' "$output"
  _has '階層が symlink' "$output"
}

@test "check: single-form line with an empty skill path is invalid, not a broken message" {
  printf 'owner/repo/\n' >"$FAKE_REPO/ext-skills.txt"
  run "$SYNC" --check
  [ "$status" -eq 1 ]
  _has 'invalid: owner/repo/' "$output"
  _lacks 'missing:  ' "$output"
}

@test "check: an invalid line does not contaminate the next valid single-form line" {
  _seed_ext_skill owner/repo skills ext-skill
  printf 'owner/repo:../../evil\nowner/repo/skills/ext-skill\n' >"$FAKE_REPO/ext-skills.txt"
  mkdir -p "$SKILLS_DIR"
  ln -s "$FAKE_GHQ_ROOT/github.com/owner/repo/skills/ext-skill" "$SKILLS_DIR/ext-skill"
  run "$SYNC" --check
  [ "$status" -eq 1 ]
  _has 'invalid: owner/repo:../../evil' "$output"
  _lacks 'invalid: owner/repo/skills/ext-skill' "$output"
  _has 'checked=1 missing=0 mismatch=0 invalid=1' "$output"
}

@test "rejects unknown flag" {
  run "$SYNC" --nonsense
  [ "$status" -eq 1 ]
  _has 'Usage' "$output"
}

@test "rejects more than one flag instead of silently honouring the first" {
  run "$SYNC" --check --local-only
  [ "$status" -eq 1 ]
  _has 'Usage' "$output"
}
