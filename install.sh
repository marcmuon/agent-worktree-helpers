#!/bin/sh
set -eu

usage() {
  cat <<'EOF'
Usage: sh install.sh [--shell zsh|bash] [--rc-file PATH] [--dry-run]

Installs agent-worktree-helpers by copying the sourced helper file to:
  $HOME/.agent-worktree-helpers/agent-worktree-helpers.sh

Then adds one marked source block to your shell rc file.
EOF
}

dry_run=0
shell_name=
rc_file=

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run)
      dry_run=1
      shift
      ;;
    --shell)
      [ "$#" -ge 2 ] || {
        printf '%s\n' "install.sh: --shell requires zsh or bash" >&2
        exit 2
      }
      shell_name=$2
      shift 2
      ;;
    --rc-file)
      [ "$#" -ge 2 ] || {
        printf '%s\n' "install.sh: --rc-file requires a path" >&2
        exit 2
      }
      rc_file=$2
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      printf '%s\n' "install.sh: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [ -z "$shell_name" ]; then
  shell_name=$(basename "${SHELL:-zsh}")
fi

case "$shell_name" in
  zsh | bash) ;;
  *)
    printf '%s\n' "install.sh: unsupported shell: $shell_name" >&2
    printf '%s\n' "install.sh: use --shell zsh, --shell bash, or --rc-file PATH" >&2
    exit 2
    ;;
esac

if [ -z "$rc_file" ]; then
  case "$shell_name" in
    zsh) rc_file="$HOME/.zshrc" ;;
    bash) rc_file="$HOME/.bashrc" ;;
  esac
fi

script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd -P)
source_file="$script_dir/shell/agent-worktree-helpers.sh"
install_dir="$HOME/.agent-worktree-helpers"
installed_file="$install_dir/agent-worktree-helpers.sh"
begin_marker="# >>> agent-worktree-helpers >>>"
end_marker="# <<< agent-worktree-helpers <<<"

block=$(cat <<'EOF'
# >>> agent-worktree-helpers >>>
source "$HOME/.agent-worktree-helpers/agent-worktree-helpers.sh"
# <<< agent-worktree-helpers <<<
EOF
)

[ -f "$source_file" ] || {
  printf '%s\n' "install.sh: missing helper file: $source_file" >&2
  exit 1
}

if [ "$dry_run" -eq 1 ]; then
  printf 'install.sh: dry run\n'
  printf 'install.sh: would create directory: %s\n' "$install_dir"
  printf 'install.sh: would copy: %s -> %s\n' "$source_file" "$installed_file"
  if [ -f "$rc_file" ] && grep -Fq "$begin_marker" "$rc_file"; then
    printf 'install.sh: rc file already contains marked block: %s\n' "$rc_file"
  else
    printf 'install.sh: would back up rc file before editing: %s\n' "$rc_file"
    printf 'install.sh: would append marked source block to: %s\n' "$rc_file"
  fi
  exit 0
fi

mkdir -p "$install_dir"
cp "$source_file" "$installed_file"
printf 'install.sh: copied helper to: %s\n' "$installed_file"

mkdir -p "$(dirname "$rc_file")"

if [ -f "$rc_file" ] && grep -Fq "$begin_marker" "$rc_file"; then
  printf 'install.sh: rc file already contains marked block: %s\n' "$rc_file"
  exit 0
fi

backup_file="$rc_file.agent-worktree-helpers.bak.$(date +%Y%m%d%H%M%S)"
if [ -f "$rc_file" ]; then
  cp "$rc_file" "$backup_file"
else
  : >"$backup_file"
  : >"$rc_file"
fi
printf 'install.sh: backed up rc file to: %s\n' "$backup_file"

if [ -s "$rc_file" ]; then
  printf '\n%s\n' "$block" >>"$rc_file"
else
  printf '%s\n' "$block" >>"$rc_file"
fi

printf 'install.sh: appended marked source block to: %s\n' "$rc_file"
printf 'install.sh: installed block markers: %s / %s\n' "$begin_marker" "$end_marker"
