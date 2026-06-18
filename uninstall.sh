#!/bin/sh
set -eu

usage() {
  cat <<'EOF'
Usage: sh uninstall.sh [--shell zsh|bash] [--rc-file PATH] [--remove-files] [--dry-run]

Removes the marked agent-worktree-helpers source block from your shell rc file.
Use --remove-files to also remove $HOME/.agent-worktree-helpers.
EOF
}

dry_run=0
remove_files=0
shell_name=
rc_file=

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run)
      dry_run=1
      shift
      ;;
    --remove-files)
      remove_files=1
      shift
      ;;
    --shell)
      [ "$#" -ge 2 ] || {
        printf '%s\n' "uninstall.sh: --shell requires zsh or bash" >&2
        exit 2
      }
      shell_name=$2
      shift 2
      ;;
    --rc-file)
      [ "$#" -ge 2 ] || {
        printf '%s\n' "uninstall.sh: --rc-file requires a path" >&2
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
      printf '%s\n' "uninstall.sh: unknown argument: $1" >&2
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
    printf '%s\n' "uninstall.sh: unsupported shell: $shell_name" >&2
    printf '%s\n' "uninstall.sh: use --shell zsh, --shell bash, or --rc-file PATH" >&2
    exit 2
    ;;
esac

if [ -z "$rc_file" ]; then
  case "$shell_name" in
    zsh) rc_file="$HOME/.zshrc" ;;
    bash) rc_file="$HOME/.bashrc" ;;
  esac
fi

install_dir="$HOME/.agent-worktree-helpers"
begin_marker="# >>> agent-worktree-helpers >>>"
end_marker="# <<< agent-worktree-helpers <<<"

if [ "$dry_run" -eq 1 ]; then
  printf 'uninstall.sh: dry run\n'
  if [ -f "$rc_file" ] && grep -Fq "$begin_marker" "$rc_file"; then
    printf 'uninstall.sh: would back up rc file before editing: %s\n' "$rc_file"
    printf 'uninstall.sh: would remove marked source block from: %s\n' "$rc_file"
  else
    printf 'uninstall.sh: marked block not found in: %s\n' "$rc_file"
  fi
  if [ "$remove_files" -eq 1 ]; then
    printf 'uninstall.sh: would remove installed files directory: %s\n' "$install_dir"
  fi
  exit 0
fi

if [ -f "$rc_file" ] && grep -Fq "$begin_marker" "$rc_file"; then
  backup_file="$rc_file.agent-worktree-helpers.bak.$(date +%Y%m%d%H%M%S)"
  tmp_file="$rc_file.agent-worktree-helpers.tmp.$$"
  cp "$rc_file" "$backup_file"
  sed "/^$begin_marker\$/,/^$end_marker\$/d" "$rc_file" >"$tmp_file"
  mv "$tmp_file" "$rc_file"
  printf 'uninstall.sh: backed up rc file to: %s\n' "$backup_file"
  printf 'uninstall.sh: removed marked source block from: %s\n' "$rc_file"
else
  printf 'uninstall.sh: marked block not found in: %s\n' "$rc_file"
fi

if [ "$remove_files" -eq 1 ]; then
  if [ -n "$install_dir" ] && [ -d "$install_dir" ]; then
    rm -rf "$install_dir"
    printf 'uninstall.sh: removed installed files directory: %s\n' "$install_dir"
  else
    printf 'uninstall.sh: installed files directory not found: %s\n' "$install_dir"
  fi
fi
