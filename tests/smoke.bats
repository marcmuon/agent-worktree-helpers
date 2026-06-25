#!/usr/bin/env bats

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  HELPER="$ROOT/shell/agent-worktree-helpers.sh"
}

@test "functions load in bash" {
  bash -c '. "$1"; for fn in wt wtco wtrm wtls wtpr wttitle wtplan; do declare -F "$fn" >/dev/null || exit 1; done' sh "$HELPER"
}

@test "wtco rejects missing branch" {
  run bash -c '. "$1"; wtco' sh "$HELPER"
  [ "$status" -ne 0 ]
  [[ "$output" == *"usage: wtco <branch>"* ]]
}

@test "wt rejects missing name" {
  run bash -c '. "$1"; wt' sh "$HELPER"
  [ "$status" -ne 0 ]
  [[ "$output" == *"usage: wt <name>"* ]]
}

@test "wt rejects names with spaces" {
  run bash -c '. "$1"; wt "has space"' sh "$HELPER"
  [ "$status" -ne 0 ]
  [[ "$output" == *"names with spaces are not supported"* ]]
}

@test "wtrm refuses outside a Git repo" {
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/awh-bats.XXXXXX")"
  run bash -c 'cd "$1"; . "$2"; wtrm' sh "$tmp" "$HELPER"
  rm -rf "$tmp"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not inside a Git repository"* ]]
}

@test "installer is idempotent" {
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/awh-bats.XXXXXX")"
  home="$tmp/home"
  rc="$home/.zshrc"
  mkdir -p "$home"
  printf '# existing rc\n' >"$rc"

  HOME="$home" SHELL=/bin/zsh sh "$ROOT/install.sh" --rc-file "$rc"
  HOME="$home" SHELL=/bin/zsh sh "$ROOT/install.sh" --rc-file "$rc"

  count="$(grep -c '^# >>> agent-worktree-helpers >>>$' "$rc")"
  rm -rf "$tmp"
  [ "$count" -eq 1 ]
}
