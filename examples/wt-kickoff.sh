# shellcheck shell=bash
# wt-kickoff — EXAMPLE: provision a worktree, seed a plan, launch an agent.
#
# This is a worked example of composing agent-worktree-helpers with a coding
# agent. It is NOT part of the core tool and depends on nothing beyond `wt`
# and whatever agent you point it at — copy it, gut it, make it yours.
#
# Source it AFTER the helpers in your rc file:
#   source ~/.agent-worktree-helpers/agent-worktree-helpers.sh
#   source /path/to/wt-kickoff.sh
#
# Usage:   wt-kickoff <slug> [one-line goal ...]
# Config:  WT_KICKOFF_AGENT   command to launch in the worktree (default: claude)
#
# What it does:
#   1. `wt <slug>`  — fresh worktree off origin/<base>, with .env + deps (via the
#      setup hook) and any archived planning files restored.
#   2. seeds `.planning/<slug>/task_plan.md` with your goal and an empty
#      checklist. Because it lives under `.planning/`, the helpers archive it on
#      `wtrm` and restore it if you recreate the worktree — your plan outlives
#      the folder.
#   3. launches your agent with the plan path as its first instruction, so the
#      session starts already pointed at the work.

wt-kickoff() {
  [ "$#" -ge 1 ] || { echo "usage: wt-kickoff <slug> [goal ...]" >&2; return 2; }
  _wtk_slug=$1; shift
  _wtk_goal=${*:-"(describe the task)"}

  wt "$_wtk_slug" || return 1        # creates the worktree and cd's into it

  _wtk_dir=".planning/$_wtk_slug"
  mkdir -p "$_wtk_dir"
  cat > "$_wtk_dir/task_plan.md" <<EOF
# Task: $_wtk_slug

## Goal
$_wtk_goal

## Plan
- [ ] ...

## Status
pending
EOF

  _wtk_agent=${WT_KICKOFF_AGENT:-claude}
  echo "wt-kickoff: seeded $_wtk_dir/task_plan.md; launching '$_wtk_agent'"

  # Adapt this launch line to your agent's CLI. Examples:
  #   claude "Read $_wtk_dir/task_plan.md and implement it."
  #   codex  "Read $_wtk_dir/task_plan.md and implement it."
  #
  # To open it in a NEW terminal window/tab instead of the current pane, wrap it
  # with your terminal's CLI, e.g.:
  #   Yaw:   yaw -d "$PWD" -e "$_wtk_agent 'Read $_wtk_dir/task_plan.md ...'"
  #   tmux:  tmux new-window -c "$PWD" "$_wtk_agent 'Read ...'"
  "$_wtk_agent" "Read $_wtk_dir/task_plan.md and implement it. Tick the checklist as you go."
}
