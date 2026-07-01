#!/bin/sh
set -eu

ROOT=$(unset CDPATH; cd "$(dirname "$0")/.." && pwd -P)
HELPER="$ROOT/shell/agent-worktree-helpers.sh"
PASS_COUNT=0
FAIL_COUNT=0

unset WORKTREE_ROOT WT_BASE_BRANCH WT_BRANCH_PREFIX WT_SETUP_HOOK
unset WT_NO_SETUP WT_NO_TITLE WT_PLAN_ARCHIVE WT_PLAN_FILES WT_NO_PLAN

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
  bash -c '. "$1"; for fn in wt wtco wtrm wtls wtpr wttitle wtplan; do declare -F "$fn" >/dev/null || exit 1; done' sh "$HELPER"
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
    WT_NO_PLAN=1 wtrm >/dev/null
    test "$PWD" = "$MAIN"
  '

  [ ! -d "$feature_dir" ]
  result=$?
  rm -rf "$tmp"
  return "$result"
}

test_wtrm_refuses_named_worktree_without_plan_files() {
  tmp=$(new_tmp_dir)
  origin="$tmp/origin.git"
  main="$tmp/main"
  workroot="$tmp/worktrees"
  feature_dir="$workroot/main/feature-by-name"
  output_file="$tmp/wtrm.out"

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

  HELPER="$HELPER" MAIN="$main" WORKTREE_ROOT="$workroot" FEATURE_DIR="$feature_dir" OUT="$output_file" bash -c '
    set -e
    . "$HELPER"
    cd "$MAIN"
    wt feature-by-name >/dev/null
    cd "$MAIN"
    if wtrm feature-by-name >"$OUT" 2>&1; then
      exit 1
    fi
    grep -q "plan: no configured planning files found" "$OUT"
    grep -q "wtrm: planning archive did not complete; worktree was not removed" "$OUT"
    test "$PWD" = "$MAIN"
    test -d "$FEATURE_DIR"
  '

  [ -d "$feature_dir" ]
  result=$?
  rm -rf "$tmp"
  return "$result"
}

test_wtrm_removes_planless_worktree_with_explicit_override() {
  tmp=$(new_tmp_dir)
  origin="$tmp/origin.git"
  main="$tmp/main"
  workroot="$tmp/worktrees"
  feature_dir="$workroot/main/feature-no-plan"

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
    wt feature-no-plan >/dev/null
    cd "$MAIN"
    WT_NO_PLAN=1 wtrm feature-no-plan >/dev/null
    test "$PWD" = "$MAIN"
  '

  [ ! -d "$feature_dir" ]
  result=$?
  rm -rf "$tmp"
  return "$result"
}

test_wtrm_refuses_when_plan_archive_fails() {
  tmp=$(new_tmp_dir)
  origin="$tmp/origin.git"
  main="$tmp/main"
  workroot="$tmp/worktrees"
  feature_dir="$workroot/main/feature-plan-fail"
  archive_file="$tmp/plan-archive"
  output_file="$tmp/wtrm.out"

  git init --bare "$origin" >/dev/null
  git init "$main" >/dev/null
  git -C "$main" config user.name "Test User"
  git -C "$main" config user.email "test@example.com"
  printf 'hello\n' >"$main/README.md"
  printf 'task_plan.md\n' >"$main/.gitignore"
  git -C "$main" add README.md .gitignore
  git -C "$main" commit -m initial >/dev/null
  git -C "$main" branch -M main
  git -C "$main" remote add origin "$origin"
  git -C "$main" push -u origin main >/dev/null 2>&1
  printf 'not a directory\n' >"$archive_file"

  HELPER="$HELPER" MAIN="$main" WORKTREE_ROOT="$workroot" WT_PLAN_ARCHIVE="$archive_file" \
    FEATURE_DIR="$feature_dir" OUT="$output_file" WT_BRANCH_PREFIX='' WT_NO_SETUP=1 bash -c '
    set -e
    . "$HELPER"
    cd "$MAIN"
    wt feature-plan-fail >/dev/null
    printf "my plan\n" > task_plan.md
    if wtrm >"$OUT" 2>&1; then
      exit 1
    fi
    grep -q "plan: could not create archive directory" "$OUT"
    grep -q "wtrm: planning archive did not complete; worktree was not removed" "$OUT"
    test -d "$FEATURE_DIR"
  '

  result=$?
  rm -rf "$tmp"
  return "$result"
}

test_wtco_rejects_missing_name() {
  output=$(bash -c '. "$1"; wtco' sh "$HELPER" 2>&1) && return 1
  printf '%s\n' "$output" | grep -q 'usage: wtco <branch>'
}

test_real_wtco_flow() {
  tmp=$(new_tmp_dir)
  origin="$tmp/origin.git"
  main="$tmp/main"
  workroot="$tmp/worktrees"

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

  git -C "$main" checkout -b teammate/feature >/dev/null 2>&1
  printf 'work\n' >>"$main/README.md"
  git -C "$main" commit -am feature >/dev/null
  git -C "$main" push -u origin teammate/feature >/dev/null 2>&1
  git -C "$main" checkout main >/dev/null 2>&1
  git -C "$main" branch -D teammate/feature >/dev/null 2>&1

  HELPER="$HELPER" MAIN="$main" WORKTREE_ROOT="$workroot" bash -c '
    set -e
    . "$HELPER"
    cd "$MAIN"
    wtco teammate/feature >/dev/null
    test "$PWD" -ef "$WORKTREE_ROOT/main/teammate-feature"
    test "$(git branch --show-current)" = "teammate/feature"
  '
  result=$?
  rm -rf "$tmp"
  return "$result"
}

test_setup_hook_runs() {
  tmp=$(new_tmp_dir)
  origin="$tmp/origin.git"
  main="$tmp/main"
  workroot="$tmp/worktrees"

  git init --bare "$origin" >/dev/null
  git init "$main" >/dev/null
  git -C "$main" config user.name "Test User"
  git -C "$main" config user.email "test@example.com"
  printf 'hello\n' >"$main/README.md"
  printf '#!/bin/sh\ntouch hook-ran\n' >"$main/.worktree-setup"
  chmod +x "$main/.worktree-setup"
  git -C "$main" add README.md .worktree-setup
  git -C "$main" commit -m initial >/dev/null
  git -C "$main" branch -M main
  git -C "$main" remote add origin "$origin"
  git -C "$main" push -u origin main >/dev/null 2>&1

  HELPER="$HELPER" MAIN="$main" WORKTREE_ROOT="$workroot" bash -c '
    set -e
    . "$HELPER"
    cd "$MAIN"
    wt with-hook >/dev/null
    test -f hook-ran
  '
  result=$?
  rm -rf "$tmp"
  return "$result"
}

test_plan_archive_and_restore() {
  tmp=$(new_tmp_dir)
  origin="$tmp/origin.git"
  main="$tmp/main"
  workroot="$tmp/worktrees"
  archive="$tmp/plan-archive"

  git init --bare "$origin" >/dev/null
  git init "$main" >/dev/null
  git -C "$main" config user.name "Test User"
  git -C "$main" config user.email "test@example.com"
  printf 'hi\n' >"$main/README.md"
  printf 'task_plan.md\n.planning/\n' >"$main/.gitignore"
  git -C "$main" add README.md .gitignore
  git -C "$main" commit -m initial >/dev/null
  git -C "$main" branch -M main
  git -C "$main" remote add origin "$origin"
  git -C "$main" push -u origin main >/dev/null 2>&1

  HELPER="$HELPER" MAIN="$main" WORKTREE_ROOT="$workroot" WT_PLAN_ARCHIVE="$archive" \
    WT_BRANCH_PREFIX='' WT_NO_SETUP=1 bash -c '
    set -e
    . "$HELPER"
    cd "$MAIN"
    wt feature-plan >/dev/null
    printf "my plan\n" > task_plan.md
    mkdir -p .planning && printf "notes\n" > .planning/notes.md
    wtrm >/dev/null
    test -f "$WT_PLAN_ARCHIVE/main/feature-plan/task_plan.md"
    test -f "$WT_PLAN_ARCHIVE/main/feature-plan/.planning/notes.md"
    git -C "$MAIN" branch -D feature-plan >/dev/null
    cd "$MAIN"
    wt feature-plan >/dev/null
    test "$(cat task_plan.md)" = "my plan"
    test -f .planning/notes.md
  '
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
run_test "wtrm refuses named worktree without plan files" test_wtrm_refuses_named_worktree_without_plan_files
run_test "wtrm removes planless worktree with explicit override" test_wtrm_removes_planless_worktree_with_explicit_override
run_test "wtrm refuses when plan archive fails" test_wtrm_refuses_when_plan_archive_fails
run_test "wtco rejects missing branch" test_wtco_rejects_missing_name
run_test "real wtco flow" test_real_wtco_flow
run_test "setup hook runs in fresh worktree" test_setup_hook_runs
run_test "plan archive + restore" test_plan_archive_and_restore

if [ "$FAIL_COUNT" -ne 0 ]; then
  printf '%s test(s) failed\n' "$FAIL_COUNT" >&2
  exit 1
fi

printf '%s test(s) passed\n' "$PASS_COUNT"
