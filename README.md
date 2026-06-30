# agent-worktree-helpers

Terminal tabs are windows. Git worktrees are isolated folders.

`agent-worktree-helpers` is a tiny sourced shell helper for people who run coding agents (Claude Code, Codex, Cursor's CLI, plain you) in terminal tabs. The idea is small:

> **One task — or one agent — per worktree.** Whatever is editing a folder gets a sealed-off, branch-local filesystem, so two tabs never fight over the same working tree.

A Git worktree gives you a second checkout of the *same* repo on its own branch, sharing one `.git`. No second clone, no duplicated history. You keep your main checkout clean and spin up a throwaway folder whenever another tab or agent needs its own space.

It works in Ghostty, iTerm, Terminal, tmux, cmux, and plain bash or zsh. It is not a plugin for any of them.

## Why bother

If you've ever:

- had an agent edit files on the wrong branch because another tab switched it underneath you,
- copied the whole repo into `myapp-2/` for a quick side task and felt gross about it, or
- wanted a planning agent and an implementing agent working at once without stepping on each other,

…that's what this fixes. Each `wt` is a clean room.

## Install

Source the helper from your shell rc file. Manual:

```sh
mkdir -p "$HOME/.agent-worktree-helpers"
cp shell/agent-worktree-helpers.sh "$HOME/.agent-worktree-helpers/agent-worktree-helpers.sh"
printf '%s\n' 'source "$HOME/.agent-worktree-helpers/agent-worktree-helpers.sh"' >> "$HOME/.zshrc"
```

Use `~/.bashrc` for bash. Or use the installer, which backs up your rc file and adds one marked block (and is idempotent):

```sh
sh install.sh --dry-run   # preview
sh install.sh             # install for your detected shell
```

Then open a new tab, or `source` the file in your current one.

## Commands

```sh
wt <name>        # new branch off origin/<base>, in its own worktree, and cd in
wtco <branch>    # check out an EXISTING branch (yours or a teammate's) in a worktree
wtpr <number>    # fetch a GitHub PR into a review worktree
wtrm [name]      # safely remove the current worktree, or a named worktree from main
wtls             # list worktrees
wtplan [branch]  # list archived plans, or print the archive path for a branch
wttitle          # set the tab title to "<repo>:<branch>" (also done automatically)
```

`wt` vs `wtco` is the one distinction worth remembering:

| | creates | use it when |
|---|---|---|
| `wt feature-x` | a **new** branch off `origin/<base>` | you're starting fresh work |
| `wtco teammate/feature` | adopts an **existing** branch from `origin` and tracks it | you're reviewing or continuing someone's branch |

## Use it at three levels

### Level 1 — parallel branches, no clobbering

You just want a second thing in flight without disturbing your current branch.

```sh
cd ~/code/example-app
wt fix-login-race      # creates + enters $WORKTREE_ROOT/example-app/fix-login-race
# ...work, commit, open a PR...
wtrm                   # back to where you were; the worktree is gone
# or, from the main checkout:
wtrm fix-login-race
```

### Level 2 — one agent per worktree

This is the point of the tool. Give each agent its own folder so the *current directory* is the isolation boundary — the thing the agent can see and edit.

```sh
# tab 1 — an implementing agent:
cd ~/code/example-app && wt add-export-button
codex            # or claude, cursor agent, etc. It can only touch this folder.

# tab 2 — review a PR at the same time, fully isolated:
wtpr 1234
claude           # "review this diff vs main"
```

A pattern that works well: a **planning** agent (e.g. Claude) reads the clean main checkout and writes a spec; an **implementing** agent (e.g. Codex) works inside a `wt` worktree from that spec. Different agents, different folders, zero overlap. The tab title (`example-app:add-export-button`) tells you at a glance which branch a given pane will modify.

Rules of thumb:

- One worktree per task; one *writing* agent per worktree.
- Don't let two agents edit the same worktree unless you're deliberately pairing.
- Keep your main checkout for reading and planning, not for agent edits.

### Level 3 — real projects with real dependencies

A fresh worktree only contains *tracked* files. Two things follow, and both are easy to handle.

**Gitignored runtime files are missing.** Your `.env` isn't in Git, so a new worktree won't have it.

**Dependencies can't be shared between worktrees.** A Python `.venv` hardcodes absolute paths in its scripts; `node_modules` contains native, path-bound binaries. Copying or symlinking either across worktrees breaks them in confusing ways. The fix is to install fresh per worktree — which is fast, because package managers (uv, npm, pnpm, …) share a global cache, so you're hardlinking, not re-downloading.

Automate both with a **setup hook**: drop an executable `.worktree-setup` at your repo root and `wt`/`wtco`/`wtpr` will run it inside each new worktree. There's a ready-to-edit template in [`examples/worktree-setup`](examples/worktree-setup):

```sh
#!/bin/sh
set -eu
src=${1:-}                                   # the checkout you ran wt from
[ -f "$src/.env" ] && [ ! -f .env ] && cp "$src/.env" .env
uv sync                                       # or: npm ci / pnpm install / etc.
```

```sh
cp examples/worktree-setup ~/code/example-app/.worktree-setup
chmod +x ~/code/example-app/.worktree-setup
```

Now `wt add-export-button` lands you in a worktree that already has its `.env` and dependencies. Skip it for a one-off with `WT_NO_SETUP=1 wt quick-thing`.

### Level 4 — keep your planning notes across worktree lifecycles

If you run planning agents, their scratch (`task_plan.md`, `.planning/`, …) lives *inside* the worktree — so it dies when you `wtrm`. The helpers carry it for you:

- `wtrm` copies those files to a global archive (`~/worktree-planning/<repo>/<branch>/`) **before** deleting the worktree.
- `wt` / `wtco` / `wtpr` restore them when you recreate a worktree on the **same branch** — pick up exactly where you left off.
- `wtplan` lists what's archived; `wtplan <branch>` prints its path, e.g. `cursor "$(wtplan you/feature)"`.
- If no configured planning files are present, `wtrm` says so. If a configured planning file cannot be archived, `wtrm` aborts and leaves the worktree in place.

The archive lives outside any repo, so it's never committed and never clutters your notes app — browse it in your editor any time. Tune what's carried with `WT_PLAN_FILES`, where it lives with `WT_PLAN_ARCHIVE`, or skip it for one command with `WT_NO_PLAN=1`.

### Running a sandboxed agent (Codex, etc.) in a worktree

A sandboxed agent scopes its filesystem/network to the *worktree folder* — but a linked worktree splits work across two places, so the sandbox needs two things, set in the agent's config (not this tool's):

- **Write access to the repo's git dir.** A worktree's metadata lives in `<main-repo>/.git/worktrees/<name>/`, *outside* the worktree folder, so `git add`/`commit` (which writes `index.lock` there) gets blocked. Add the repo's `.git` — or a parent dir covering all your repos — to the agent's writable roots. For Codex (`~/.codex/config.toml`):
  ```toml
  [sandbox_workspace_write]
  writable_roots = ["/path/to/your/code"]
  ```
- **Network access**, if you want the agent to `git push` / open PRs itself (and run `npm ci` / `pip install`). Separate switch, off by default:
  ```toml
  [sandbox_workspace_write]
  network_access = true
  ```

Restart the agent after editing its config — sandbox policy is read at session start. Heads-up: the Codex **CLI** honors these keys; the Codex **app** has historically ignored them ([openai/codex#13373](https://github.com/openai/codex/issues/13373)), so push from a normal terminal there.

## Configuration

Set these before sourcing the helper (or export them anytime):

| Variable | Default | What it does |
|---|---|---|
| `WORKTREE_ROOT` | `$HOME/Projects/worktrees` | Where worktrees are created: `$WORKTREE_ROOT/<repo>/<name>`. |
| `WT_BASE_BRANCH` | `main` | Branch `wt` branches from (set to `master` if that's your default). |
| `WT_BRANCH_PREFIX` | _(unset)_ | If set, `wt foo` creates branch `<prefix>/foo`. Handy for namespacing, e.g. `export WT_BRANCH_PREFIX="$(whoami)"` → `you/foo`. The folder name stays `foo`. |
| `WT_SETUP_HOOK` | _(unset)_ | Path to a global setup script, used if a repo has no `.worktree-setup`. |
| `WT_NO_SETUP` | `0` | `WT_NO_SETUP=1` skips the setup hook for one command. |
| `WT_NO_TITLE` | `0` | `WT_NO_TITLE=1` disables tab titling. |
| `WT_PLAN_ARCHIVE` | `$HOME/worktree-planning` | Where `wtrm` stashes planning files and `wt`/`wtco` restore them from. |
| `WT_PLAN_FILES` | `task_plan.md findings.md progress.md .planning` | Space-separated files/dirs carried across a worktree's lifecycle. |
| `WT_NO_PLAN` | `0` | `WT_NO_PLAN=1` skips planning archive/restore for one command. |

```sh
export WORKTREE_ROOT="$HOME/worktrees"
export WT_BASE_BRANCH="master"
export WT_BRANCH_PREFIX="$(whoami)"
source "$HOME/.agent-worktree-helpers/agent-worktree-helpers.sh"
```

## Things that will bite you

Generic to worktrees, not to this tool — worth knowing once:

- **Don't copy a `.venv` or `node_modules` between worktrees.** Reinstall per worktree (the setup hook does this). It's cheap thanks to the shared package cache.
- **Only one worktree can run a stateful local stack at a time** if they all point at the same local database / Redis / fixed dev-server port. For editing, compiling, and unit tests this never matters; it only matters when you actually boot the app. Give a second runner its own DB name and ports if you need two live at once.
- **Pre-commit hooks live in the shared `.git`,** so they're inherited by every worktree of a clone automatically — but a *separate clone* has its own hooks. Make worktrees from the clone whose hooks you want.
- **`wtrm` removes the folder, not the branch.** It prints the `git branch -D` command if you also want the branch gone. This is true for `wt` and `wtco` alike.

## Safety

- `wt` requires a name, rejects spaces, and validates the branch name.
- `wt` refuses to reuse an existing branch; `wtco` adopts one on purpose (and won't clobber local commits — if the branch already exists locally it checks it out as-is).
- If a target directory is already a worktree for the same repo, the command just enters it.
- `wtrm` refuses to remove the main checkout, and refuses to remove a dirty worktree (it prints `git status --short`). From the main checkout, `wtrm <name>` removes `$WORKTREE_ROOT/<repo>/<name>`.
- The setup hook only runs a file that's already in your checkout, and only if it's executable. Disable it with `WT_NO_SETUP=1`.

## Troubleshooting

**My default branch is `master`.** `export WT_BASE_BRANCH=master` before sourcing.

**`wtrm` says the worktree is dirty.** Commit, stash, or discard the changes it lists, then run it again. This is deliberate — it won't throw away work.

**`wt` says the branch already exists.** Pick another name, or delete the old branch (`git branch -D <name>`) once you're sure. To resume an existing branch instead, use `wtco <name>`.

**`wtco` can't fetch the branch.** It expects an existing branch on `origin`. Check the name with `git ls-remote --heads origin`.

**`wtpr` can't fetch a PR.** It uses `git fetch origin pull/<n>/head`, which is GitHub-style. For other hosts, fetch the branch and use `wtco`.

**Two dev servers won't both start.** Same fixed port. Set your framework's port per worktree (e.g. an env var in `.worktree-setup`).

## Security / trust

The installer is intentionally boring: it prints what it changes, copies one shell file into `~/.agent-worktree-helpers`, backs up your rc file, and adds one marked source block. The uninstaller removes only that block (and, with `--remove-files`, the installed file). You can skip it entirely and use the manual install above.

## Development

```sh
sh tests/smoke.sh                                                            # POSIX smoke tests
shellcheck install.sh uninstall.sh shell/agent-worktree-helpers.sh tests/smoke.sh
bats tests/smoke.bats                                                        # if bats is installed
```

CI runs all three on Ubuntu and macOS.
