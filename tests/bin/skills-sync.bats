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

  SYNC="$FAKE_REPO/bin/skills-sync.sh"
  SKILLS_DIR="$HOME/.claude/skills"
  AGENTS_DIR="$HOME/.claude/agents"
  EVOLVE="$HOME/.claude-evolution"
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
  [[ "$output" == *"linked=0"* ]]
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
  [[ "$output" == *"WARN"* ]]
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
  [[ "$output" == *"階層が symlink"* ]]
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
  [[ "$output" == *"不正な manifest 行"* ]]
}

@test "full: manifest line with traversal is rejected (WARN + no link, prune suppressed)" {
  printf 'owner/repo:../../evil\n' >"$FAKE_REPO/ext-skills.txt"
  mkdir -p "$SKILLS_DIR" "$BATS_TEST_TMPDIR/keep"
  ln -s "$BATS_TEST_TMPDIR/keep" "$SKILLS_DIR/keep-me"
  run "$SYNC"
  [ "$status" -eq 1 ]
  [[ "$output" == *"不正な manifest 行"* ]]
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
  [[ "$output" == *"repo 外を指す skill"* ]]
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
  [[ "$output" == *"prune を抑止"* ]]
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

@test "rejects unknown flag" {
  run "$SYNC" --nonsense
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage"* ]]
}
