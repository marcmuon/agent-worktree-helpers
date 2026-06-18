#!/bin/sh
set -eu

ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd -P)
HELPER="$ROOT/shell/agent-worktree-helpers.sh"
PASS_COUNT=0
FAIL_COUNT=0

ok() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf 'ok - %s\n' "$1"
}

not_ok() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf 'not ok - %s\n' "$1" >&2
}

run_test() {
  name=$1
  shift

  if "$@"; then
    ok "$name"
  else
    not_ok "$name"
  fi
}

new_tmp_dir() {
  mktemp -d "${TMPDIR:-/tmp}/awh-test.XXXXXX"
}

test_functions_load_in_bash() {
  bash -c '. "$1"; declare -F wt >/dev/null; declare -F wtrm >/dev/null; declare -F wtls >/dev/null; declare -F wtpr >/dev/null' sh "$HELPER"
}

test_wt_rejects_missing_name() {
  output=$(bash -c '. "$1"; wt' sh "$HELPER" 2>&1) && return 1
  printf '%s\n' "$output" | grep -q 'usage: wt <name>'
}

test_wt_rejects_spaces() {
  output=$(bash -c '. "$1"; wt "has space"' sh "$HELPER" 2>&1) && return 1
  printf '%s\n' "$output" | grep -q 'names with spaces are not supported'
}

test_wtrm_refuses_outside_git_repo() {
  tmp=$(new_tmp_dir)
  output=$(cd "$tmp" && bash -c '. "$1"; wtrm' sh "$HELPER" 2>&1) && {
    rm -rf "$tmp"
    return 1
  }
  rm -rf "$tmp"
  printf '%s\n' "$output" | grep -q 'not inside a Git repository'
}

test_wtrm_refuses_main_checkout() {
  tmp=$(new_tmp_dir)
  git init "$tmp/repo" >/dev/null
  output=$(cd "$tmp/repo" && bash -c '. "$1"; wtrm' sh "$HELPER" 2>&1) && {
    rm -rf "$tmp"
    return 1
  }
  rm -rf "$tmp"
  printf '%s\n' "$output" | grep -q 'refusing to remove the main checkout'
}

test_installer_dry_run_is_non_mutating() {
  tmp=$(new_tmp_dir)
  home="$tmp/home"
  rc="$home/.zshrc"
  mkdir -p "$home"
  printf '# existing rc\n' >"$rc"

  HOME="$home" SHELL=/bin/zsh sh "$ROOT/install.sh" --rc-file "$rc" --dry-run >/dev/null

  [ "$(cat "$rc")" = "# existing rc" ] && [ ! -e "$home/.agent-worktree-helpers" ]
  result=$?
  rm -rf "$tmp"
  return "$result"
}

test_installer_is_idempotent() {
  tmp=$(new_tmp_dir)
  home="$tmp/home"
  rc="$home/.zshrc"
  mkdir -p "$home"
  printf '# existing rc\n' >"$rc"

  HOME="$home" SHELL=/bin/zsh sh "$ROOT/install.sh" --rc-file "$rc" >/dev/null
  HOME="$home" SHELL=/bin/zsh sh "$ROOT/install.sh" --rc-file "$rc" >/dev/null

  count=$(grep -c '^# >>> agent-worktree-helpers >>>$' "$rc")
  [ "$count" -eq 1 ] &&
    [ -f "$home/.agent-worktree-helpers/agent-worktree-helpers.sh" ] &&
    ls "$home"/.zshrc.agent-worktree-helpers.bak.* >/dev/null 2>&1
  result=$?
  rm -rf "$tmp"
  return "$result"
}

test_uninstaller_removes_block_and_files() {
  tmp=$(new_tmp_dir)
  home="$tmp/home"
  rc="$home/.zshrc"
  mkdir -p "$home"
  printf '# existing rc\n' >"$rc"

  HOME="$home" SHELL=/bin/zsh sh "$ROOT/install.sh" --rc-file "$rc" >/dev/null
  HOME="$home" SHELL=/bin/zsh sh "$ROOT/uninstall.sh" --rc-file "$rc" --remove-files >/dev/null

  ! grep -q '^# >>> agent-worktree-helpers >>>$' "$rc" &&
    [ ! -e "$home/.agent-worktree-helpers" ] &&
    ls "$home"/.zshrc.agent-worktree-helpers.bak.* >/dev/null 2>&1
  result=$?
  rm -rf "$tmp"
  return "$result"
}

test_real_worktree_flow() {
  tmp=$(new_tmp_dir)
  origin="$tmp/origin.git"
  main="$tmp/main"
  workroot="$tmp/worktrees"
  feature_dir="$workroot/main/feature-one"

  git init --bare "$origin" >/dev/null
  git init "$main" >/dev/null
  git -C "$main" config user.name "Test User"
  git -C "$main" config user.email "test@example.com"
  printf 'hello\n' >"$main/README.md"
  git -C "$main" add README.md
  git -C "$main" commit -m initial >/dev/null
  git -C "$main" branch -M main
  git -C "$main" remote add origin "$origin"
  git -C "$main" push -u origin main >/dev/null 2>&1

  HELPER="$HELPER" MAIN="$main" WORKTREE_ROOT="$workroot" bash -c '
    set -e
    . "$HELPER"
    cd "$MAIN"
    wt feature-one >/dev/null
    test "$PWD" = "$WORKTREE_ROOT/main/feature-one"
    test "$(git branch --show-current)" = "feature-one"
  '

  HELPER="$HELPER" FEATURE_DIR="$feature_dir" bash -c '
    set -e
    . "$HELPER"
    cd "$FEATURE_DIR"
    printf dirty >> README.md
    if wtrm >/dev/null 2>&1; then
      exit 1
    fi
  '

  git -C "$feature_dir" reset --hard >/dev/null

  HELPER="$HELPER" FEATURE_DIR="$feature_dir" MAIN="$main" bash -c '
    set -e
    . "$HELPER"
    cd "$FEATURE_DIR"
    wtrm >/dev/null
    test "$PWD" = "$MAIN"
  '

  [ ! -d "$feature_dir" ]
  result=$?
  rm -rf "$tmp"
  return "$result"
}

run_test "functions load in bash" test_functions_load_in_bash
run_test "wt rejects missing name" test_wt_rejects_missing_name
run_test "wt rejects names with spaces" test_wt_rejects_spaces
run_test "wtrm refuses outside a Git repo" test_wtrm_refuses_outside_git_repo
run_test "wtrm refuses from main checkout" test_wtrm_refuses_main_checkout
run_test "installer dry-run is non-mutating" test_installer_dry_run_is_non_mutating
run_test "installer is idempotent" test_installer_is_idempotent
run_test "uninstaller removes block and files" test_uninstaller_removes_block_and_files
run_test "real wt/wtrm worktree flow" test_real_worktree_flow

if [ "$FAIL_COUNT" -ne 0 ]; then
  printf '%s test(s) failed\n' "$FAIL_COUNT" >&2
  exit 1
fi

printf '%s test(s) passed\n' "$PASS_COUNT"
