#!/usr/bin/env bash
# meldown-merge.sh - git mergetool wrapper that opens the patched Linux Meld,
# run from its source checkout (~/.local/src/meld, at a release tag), with
# branch names as the pane headers.
#
# Git hands a mergetool only file paths, so Meld would title the panes
# a_LOCAL_123.txt and a_REMOTE_123.txt. The names are worked out here from
# the state files of the merge, rebase or cherry-pick in progress.
#
# With --repo it takes no files: it opens Meld's Conflicts tab for the
# current repository, a list of every conflicted file, passing the same
# branch names as column titles through MELD_CONFLICTS_* variables.
#
# Called from git config (README.md):
#   mergetool.meldown.cmd = /path/to/meldown/meldown-merge.sh "$LOCAL" "$BASE" "$REMOTE" "$MERGED"

set -u

repo=false
[ "${1:-}" = --repo ] && { repo=true; shift; }
# No GDK_SCALE: Meld runs as a Wayland client, where GTK ignores it. Under
# WSL, WSLg scales windows per screen itself, but only while the Windows
# display layout is one row or one column (README.md).
MELD="${MELD_SRC:-$HOME/.local/src/meld}/bin/meld"
$repo || { local_file=$1 base_file=$2 remote_file=$3 merged_file=$4; }
git_dir=$(git rev-parse --git-dir) || exit 1

# Branch names go into Pango markup in the Conflicts tab's header.
esc() { sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g' <<<"$1"; }

# Readable name for a commit (a branch, possibly with ~N), or nothing.
name_of() {
    git name-rev --name-only --no-undefined "$1" 2>/dev/null | sed 's#^remotes/##'
}

current=$(git symbolic-ref --short -q HEAD)
left="${current:-local} (yours)"
right="remote (incoming)"
header="Conflicts in <b>$(esc "$(basename "$(git rev-parse --show-toplevel)")")</b>"

rebase_dir=""
for d in "$git_dir/rebase-merge" "$git_dir/rebase-apply"; do
    [ -f "$d/head-name" ] && rebase_dir=$d && break
done

if [ -n "$rebase_dir" ]; then
    # In a rebase git's LOCAL is the branch being rebased onto and REMOTE is
    # your own commit being replayed, the reverse of a merge.
    onto=$(name_of "$(cat "$rebase_dir/onto" 2>/dev/null)")
    yours=$(sed 's#^refs/heads/##' "$rebase_dir/head-name")
    left="${onto:-upstream} (rebasing onto)"
    right="$yours (your commit)"
    header="Rebasing <b>$(esc "$yours")</b> onto <b>$(esc "${onto:-upstream}")</b>"
elif [ -f "$git_dir/MERGE_HEAD" ]; then
    incoming=$(name_of MERGE_HEAD)
    if [ -z "$incoming" ]; then
        # A merge of a fetched ref has no local branch name; MERGE_MSG still
        # says "Merge branch 'x' of <url>".
        incoming=$(sed -n "1s/^Merge \(remote-tracking \)\?branch '\([^']*\)'.*/\2/p" "$git_dir/MERGE_MSG" 2>/dev/null)
    fi
    right="${incoming:-remote} (incoming)"
    header="Merging branch <b>$(esc "${incoming:-remote}")</b> into branch <b>$(esc "${current:-HEAD}")</b>"
elif [ -f "$git_dir/CHERRY_PICK_HEAD" ]; then
    picked=$(git log -1 --format='%h %s' CHERRY_PICK_HEAD)
    right="$picked (cherry-pick)"
    header="Cherry-picking <b>$(esc "$picked")</b> onto <b>$(esc "${current:-HEAD}")</b>"
fi

if $repo; then
    root=$(git rev-parse --show-toplevel) || exit 1
    if [ -z "$(git ls-files -u)" ]; then
        echo "No merge conflicts in $root"
        exit 0
    fi
    export MELD_CONFLICTS_YOURS="$left" MELD_CONFLICTS_THEIRS="$right" MELD_CONFLICTS_HEADER="$header"
    exec "$MELD" --conflicts "$root"
fi

# git mergetool opens one Meld window per file, so Meld cannot know how many
# files are left; the files still unmerged (this one included) go in the
# result pane's title. The count comes first because Meld shortens a long
# title in the middle, which would hide it at the end.
left_files=$(git diff --name-only --diff-filter=U 2>/dev/null | wc -l)
case "$left_files" in
    0|1) result_title="Result (last file): $merged_file" ;;
    *) result_title="Result ($left_files files left): $merged_file" ;;
esac

# --anchored-merge is the patched checkout's apply-or-dismiss merge view: the
# result starts as the base and each change is applied or dismissed.
exec "$MELD" --anchored-merge \
    -L "$left" -L "$result_title" -L "$right" \
    "$local_file" "$base_file" "$remote_file" \
    --output "$merged_file"
