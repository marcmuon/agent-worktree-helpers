# shellcheck shell=bash
# Source this file from bash or zsh.

_awh_err() {
  printf '%s\n' "$*" >&2
}

_awh_abs_path() {
  [ -n "${1:-}" ] || return 1
  (cd "$1" 2>/dev/null && pwd -P)
}

_awh_git_root() {
  local repo

  repo=$(git rev-parse --show-toplevel 2>/dev/null) || {
    _awh_err "agent-worktree-helpers: not inside a Git repository"
    return 1
  }

  printf '%s\n' "$repo"
}

_awh_common_dir() {
  local repo common

  repo=$1
  common=$(git -C "$repo" rev-parse --git-common-dir 2>/dev/null) || return 1

  case "$common" in
    /*) _awh_abs_path "$common" ;;
    *) _awh_abs_path "$repo/$common" ;;
  esac
}

_awh_main_worktree() {
  local repo

  repo=$1
  git -C "$repo" worktree list --porcelain |
    awk '/^worktree / { sub(/^worktree /, ""); print; exit }'
}

_awh_same_repo_worktree() {
  local repo candidate repo_common candidate_common

  repo=$1
  candidate=$2

  [ -d "$candidate" ] || return 1
  git -C "$candidate" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1

  repo_common=$(_awh_common_dir "$repo") || return 1
  candidate_common=$(_awh_common_dir "$candidate") || return 1

  [ "$repo_common" = "$candidate_common" ]
}

_awh_validate_branch_name() {
  local command_name branch_name

  command_name=$1
  branch_name=$2

  if [ -z "$branch_name" ]; then
    _awh_err "usage: $command_name <name>"
    return 2
  fi

  case "$branch_name" in
    *[[:space:]]*)
      _awh_err "$command_name: names with spaces are not supported: $branch_name"
      return 2
      ;;
  esac

  if ! git check-ref-format --branch "$branch_name" >/dev/null 2>&1; then
    _awh_err "$command_name: not a valid branch name: $branch_name"
    return 2
  fi
}

_awh_cd_existing_worktree() {
  local repo dir

  repo=$1
  dir=$2

  if _awh_same_repo_worktree "$repo" "$dir"; then
    printf 'agent-worktree-helpers: entering existing worktree: %s\n' "$dir"
    cd "$dir" || return 1
    return 0
  fi

  _awh_err "agent-worktree-helpers: target exists but is not a worktree for this repo: $dir"
  return 1
}

# Run a per-worktree setup hook inside the freshly created worktree (cwd).
# $1 is the source checkout the command was run from, exported as WT_SOURCE so
# the hook can copy gitignored files (e.g. .env) out of it. Skipped when
# WT_NO_SETUP=1. The hook is the repo-root file ".worktree-setup" (must be
# executable) or whatever WT_SETUP_HOOK points at. A non-zero hook warns but
# does not unwind the worktree you are now standing in.
_awh_run_setup_hook() {
  local src hook

  src=$1

  [ "${WT_NO_SETUP:-0}" = "1" ] && return 0

  hook=
  if [ -n "${WT_SETUP_HOOK:-}" ] && [ -x "${WT_SETUP_HOOK}" ]; then
    hook=$WT_SETUP_HOOK
  elif [ -x "./.worktree-setup" ]; then
    hook="./.worktree-setup"
  fi

  [ -n "$hook" ] || return 0

  printf 'worktree setup: running %s\n' "$hook"
  WT_SOURCE="$src" "$hook" "$src" ||
    _awh_err "worktree setup: $hook exited non-zero (continuing anyway)"
}

# Title the terminal tab "<repo>:<branch>" so parallel worktree tabs are
# distinguishable. No-ops when not writing to a TTY, or when WT_NO_TITLE=1.
_awh_set_title() {
  local repo main base branch

  [ "${WT_NO_TITLE:-0}" = "1" ] && return 0
  [ -t 1 ] || return 0

  repo=$(git rev-parse --show-toplevel 2>/dev/null) || return 0
  main=$(_awh_main_worktree "$repo" 2>/dev/null)
  if [ -n "$main" ]; then
    base=$(basename "$main")
  else
    base=$(basename "$repo")
  fi
  branch=$(git -C "$repo" branch --show-current 2>/dev/null)
  [ -n "$branch" ] || branch=detached

  printf '\033]2;%s\007' "$base:$branch"
}

wttitle() {
  _awh_set_title
}

wt() {
  local name repo main repo_name root base dir parent prefix branch

  if [ "$#" -ne 1 ]; then
    _awh_err "usage: wt <name>"
    return 2
  fi

  name=$1
  _awh_validate_branch_name "wt" "$name" || return $?

  prefix=${WT_BRANCH_PREFIX:-}
  if [ -n "$prefix" ]; then
    branch="$prefix/$name"
  else
    branch="$name"
  fi
  _awh_validate_branch_name "wt" "$branch" || return $?

  repo=$(_awh_git_root) || return 1
  main=$(_awh_main_worktree "$repo") || return 1
  repo_name=$(basename "$main")
  root=${WORKTREE_ROOT:-"$HOME/Projects/worktrees"}
  base=${WT_BASE_BRANCH:-main}
  dir="$root/$repo_name/$name"
  parent=$(dirname "$dir")

  if [ -e "$dir" ]; then
    _awh_cd_existing_worktree "$repo" "$dir"
    return $?
  fi

  if git -C "$repo" show-ref --verify --quiet "refs/heads/$branch"; then
    _awh_err "wt: branch already exists: $branch"
    _awh_err "wt: choose a new name, or remove the old branch manually if it is no longer needed."
    return 1
  fi

  if ! git -C "$repo" remote get-url origin >/dev/null 2>&1; then
    _awh_err "wt: remote 'origin' was not found"
    return 1
  fi

  mkdir -p "$parent" || return 1

  printf 'wt: fetching origin...\n'
  git -C "$repo" fetch origin || return 1

  if ! git -C "$repo" rev-parse --verify --quiet "origin/$base" >/dev/null; then
    _awh_err "wt: origin/$base was not found"
    _awh_err "wt: set WT_BASE_BRANCH to your default branch, for example: export WT_BASE_BRANCH=master"
    return 1
  fi

  git -C "$repo" worktree add -b "$branch" "$dir" "origin/$base" || return 1
  cd "$dir" || return 1
  printf 'wt: now on %s in %s\n' "$branch" "$dir"
  _awh_run_setup_hook "$main"
  _awh_set_title
}

# Check out an EXISTING branch (yours from elsewhere, or a teammate's) into its
# own worktree. Unlike wt, which creates a new branch off origin/<base>, wtco
# adopts <branch> from origin and tracks it. Slashes in the branch name are
# flattened for the directory (teammate/feature -> teammate-feature).
wtco() {
  local arg branch repo main repo_name root safe dir parent

  if [ "$#" -ne 1 ]; then
    _awh_err "usage: wtco <branch>"
    return 2
  fi

  arg=$1
  branch=${arg#origin/}
  _awh_validate_branch_name "wtco" "$branch" || return $?

  repo=$(_awh_git_root) || return 1
  main=$(_awh_main_worktree "$repo") || return 1
  repo_name=$(basename "$main")
  root=${WORKTREE_ROOT:-"$HOME/Projects/worktrees"}
  safe=$(printf '%s' "$branch" | tr '/' '-')
  dir="$root/$repo_name/$safe"
  parent=$(dirname "$dir")

  if [ -e "$dir" ]; then
    _awh_cd_existing_worktree "$repo" "$dir"
    return $?
  fi

  if ! git -C "$repo" remote get-url origin >/dev/null 2>&1; then
    _awh_err "wtco: remote 'origin' was not found"
    return 1
  fi

  mkdir -p "$parent" || return 1

  if git -C "$repo" show-ref --verify --quiet "refs/heads/$branch"; then
    printf 'wtco: checking out existing local branch: %s\n' "$branch"
    git -C "$repo" worktree add "$dir" "$branch" || return 1
  else
    printf 'wtco: fetching origin %s...\n' "$branch"
    if ! git -C "$repo" fetch origin "+$branch:refs/remotes/origin/$branch"; then
      _awh_err "wtco: could not fetch branch from origin: $branch"
      _awh_err "wtco: pass an existing remote branch name, for example: wtco teammate/feature"
      return 1
    fi
    git -C "$repo" worktree add --track -b "$branch" "$dir" "origin/$branch" || return 1
  fi

  cd "$dir" || return 1
  printf 'wtco: now on %s in %s\n' "$branch" "$dir"
  _awh_run_setup_hook "$main"
  _awh_set_title
}

wtls() {
  local repo

  repo=$(_awh_git_root) || return 1
  git -C "$repo" worktree list
}

wtrm() {
  local repo main repo_abs main_abs dirty branch

  repo=$(_awh_git_root) || return 1
  main=$(_awh_main_worktree "$repo") || return 1
  repo_abs=$(_awh_abs_path "$repo") || return 1
  main_abs=$(_awh_abs_path "$main") || return 1

  if [ "$repo_abs" = "$main_abs" ]; then
    _awh_err "wtrm: refusing to remove the main checkout: $main_abs"
    return 1
  fi

  dirty=$(git -C "$repo" status --short)
  if [ -n "$dirty" ]; then
    _awh_err "wtrm: refusing to remove a dirty worktree:"
    printf '%s\n' "$dirty" >&2
    return 1
  fi

  branch=$(git -C "$repo" branch --show-current 2>/dev/null || true)

  cd "$main_abs" || return 1
  git -C "$main_abs" worktree remove "$repo_abs" || return 1
  git -C "$main_abs" worktree prune || return 1

  printf 'wtrm: removed worktree: %s\n' "$repo_abs"
  if [ -n "$branch" ]; then
    printf 'wtrm: branch was not deleted. To delete it manually, run: git branch -D %s\n' "$branch"
  fi
}

wtpr() {
  local pr repo main repo_name root dir branch parent

  if [ "$#" -ne 1 ]; then
    _awh_err "usage: wtpr <pr-number>"
    return 2
  fi

  pr=$1
  case "$pr" in
    '' | *[!0-9]*)
      _awh_err "wtpr: PR number must be numeric"
      return 2
      ;;
  esac

  repo=$(_awh_git_root) || return 1
  main=$(_awh_main_worktree "$repo") || return 1
  repo_name=$(basename "$main")
  root=${WORKTREE_ROOT:-"$HOME/Projects/worktrees"}
  dir="$root/$repo_name/pr-$pr"
  branch="review/pr-$pr"
  parent=$(dirname "$dir")

  if [ -e "$dir" ]; then
    _awh_cd_existing_worktree "$repo" "$dir"
    return $?
  fi

  if ! git -C "$repo" remote get-url origin >/dev/null 2>&1; then
    _awh_err "wtpr: remote 'origin' was not found"
    return 1
  fi

  mkdir -p "$parent" || return 1

  printf 'wtpr: fetching origin pull/%s/head...\n' "$pr"
  git -C "$repo" fetch origin "pull/$pr/head" || {
    _awh_err "wtpr: could not fetch pull/$pr/head from origin"
    _awh_err "wtpr: this shortcut expects a GitHub-style origin remote."
    return 1
  }

  git -C "$repo" worktree add -B "$branch" "$dir" FETCH_HEAD || return 1
  cd "$dir" || return 1
  printf 'wtpr: now in %s\n' "$dir"
  _awh_run_setup_hook "$main"
  _awh_set_title
}
