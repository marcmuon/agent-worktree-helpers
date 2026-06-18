# agent-worktree-helpers

Terminal tabs are windows. Git worktrees are isolated folders.

`agent-worktree-helpers` is a tiny sourced shell helper for developers who run coding agents in terminal tabs. The loop is simple: use your normal checkout for one task, and make a temporary Git worktree when another tab or agent needs its own clean workspace.

cmux is a good example of a terminal where this workflow is useful, but this is not a cmux plugin and does not depend on cmux. It also works in Ghostty, iTerm, Terminal, tmux, and plain bash or zsh.

## Commands

```sh
wt <name>        # create a worktree and cd into it
wtrm             # remove the current temporary worktree safely
wtls             # list Git worktrees
wtpr <number>    # optional: fetch a GitHub PR into a review worktree
```

Defaults:

```sh
WORKTREE_ROOT="${WORKTREE_ROOT:-$HOME/Projects/worktrees}"
WT_BASE_BRANCH="${WT_BASE_BRANCH:-main}"
```

Set those before sourcing the helper if you want different defaults:

```sh
export WORKTREE_ROOT="$HOME/worktrees"
export WT_BASE_BRANCH="master"
source "$HOME/.agent-worktree-helpers/agent-worktree-helpers.sh"
```

## Mental Model

- One task at a time: use the normal repo.
- Parallel task: run `wt <name>`.
- Done with a temporary workspace: run `wtrm` from inside that worktree.
- Normal PR review by diff: no worktree needed.
- Need to run a PR locally: use optional `wtpr <number>`.

## Manual Install

Clone or copy this repo, then source the helper from your shell rc file:

```sh
mkdir -p "$HOME/.agent-worktree-helpers"
cp shell/agent-worktree-helpers.sh "$HOME/.agent-worktree-helpers/agent-worktree-helpers.sh"
printf '%s\n' 'source "$HOME/.agent-worktree-helpers/agent-worktree-helpers.sh"' >> "$HOME/.zshrc"
```

Use `~/.bashrc` instead of `~/.zshrc` if you use bash.

For the current shell session:

```sh
source "$HOME/.agent-worktree-helpers/agent-worktree-helpers.sh"
```

## Installer

Preview first:

```sh
sh install.sh --dry-run
```

Install for your detected shell:

```sh
sh install.sh
```

Choose a shell or rc file explicitly:

```sh
sh install.sh --shell zsh
sh install.sh --rc-file "$HOME/.zshrc"
```

The installer copies the helper to `~/.agent-worktree-helpers/agent-worktree-helpers.sh`, backs up the rc file before editing, and adds exactly one marked block:

```sh
# >>> agent-worktree-helpers >>>
source "$HOME/.agent-worktree-helpers/agent-worktree-helpers.sh"
# <<< agent-worktree-helpers <<<
```

Running the installer twice does not duplicate the block.

## Uninstall

Preview:

```sh
sh uninstall.sh --dry-run
```

Remove the rc block:

```sh
sh uninstall.sh
```

Remove the rc block and installed helper files:

```sh
sh uninstall.sh --remove-files
```

## Examples

From a normal repo:

```sh
cd ~/src/example-app
wt fix-login-race
```

That creates and enters:

```text
$WORKTREE_ROOT/example-app/fix-login-race
```

When finished:

```sh
wtrm
```

If the worktree has uncommitted changes, `wtrm` refuses and prints `git status --short`.

## Safety

- `wt` requires a name and rejects names containing spaces.
- `wt` refuses to overwrite an existing non-worktree directory.
- If the target directory is already a worktree for the same repo, `wt` just enters it.
- `wtrm` refuses to remove the main checkout.
- `wtrm` refuses to remove a dirty worktree.
- `wtrm` does not delete branches automatically. It prints the manual branch deletion command.
- `wtpr` expects a GitHub-style `origin` remote that supports `pull/<number>/head`.

## Troubleshooting

### My default branch is master, not main

Set `WT_BASE_BRANCH` before sourcing:

```sh
export WT_BASE_BRANCH=master
```

### `wtrm` refuses because the worktree is dirty

Check the printed status. Commit, stash, reset, or delete files yourself, then run `wtrm` again.

### The branch already exists

`wt <name>` creates a new branch with the same name. Pick a new name, or delete the old branch manually after you are sure it is safe:

```sh
git branch -D <name>
```

### I ran `wtrm` from the main checkout

That is refused on purpose. `wtrm` is only for temporary worktrees.

### `wtpr` cannot fetch a PR

`wtpr` uses:

```sh
git fetch origin "pull/<number>/head"
```

That works for GitHub-style remotes. For other hosts, fetch the branch manually or use `wt <name>`.

## Security / Trust

The installer is intentionally boring. It prints what it changes, copies one shell file into `~/.agent-worktree-helpers`, backs up your selected rc file, and adds one marked source block. The uninstaller removes only that marked block.

You can skip the installer and use the manual install commands above.

## Development

Run the smoke tests:

```sh
sh tests/smoke.sh
```

Run ShellCheck if installed:

```sh
shellcheck install.sh uninstall.sh shell/agent-worktree-helpers.sh tests/smoke.sh
```

Run the optional Bats tests if Bats is installed:

```sh
bats tests/smoke.bats
```
