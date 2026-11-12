# meldown

Patches that give [Meld](https://meld.app/) a PhpStorm-style way of resolving merge conflicts, plus a `git mergetool` wrapper and a dark theme to match.

Stock Meld opens a three-way merge with the result already half-merged, and every change shows as a copy between panes. meldown keeps Meld but changes how a merge works:

- **Merge view (`--anchored-merge`).** The result starts as the common base. Every change from either side gets an arrow to apply it and an X to dismiss it; on a conflict, a second arrow adds the other side after the first. A toolbar applies all non-conflicting changes from the left, the right or both, runs the magic wand on simple conflicts, and counts changes, unresolved changes and conflicts. The side panes are read-only, applied lines are tinted, dismissed ones struck through. Undo, typing and reopening a half-done file all keep each change's state, because the state is worked out from the text itself.
- **Conflicts tab (`--conflicts DIR`).** Every conflicted file of a git repository in one list, grouped Unresolved, Auto-resolved and Resolved, with an Accept button per side, Resolve simple conflicts (which says how many files it would merge, and is greyed out when there are none), and Accept and finish. Double-click a file to open it in the merge view.
- **Calmer highlighting.** Changes are marked word by word, not character by character, and whitespace is ignored, so a re-indented block no longer lights up.
- **Conflict count** in the merge pane's status bar.
- **Branch names as pane titles**, from the wrapper, for merges, rebases and cherry-picks.
- **An honest exit status.** Meld exits 0 only when the result was saved with nothing left unresolved, so with `trustExitCode` git never marks a half-done file as resolved.

Tested on Ubuntu 24.04 under WSL 2 (WSLg). Other Linux distributions should work the same way.

## What is here

| Path | What it is |
|---|---|
| `patches/` | The patch series, in `git format-patch` form |
| `MELD_VERSION` | The Meld release tag the patches apply to |
| `meldown-merge.sh` | The `git mergetool` wrapper, and the Conflicts tab launcher with `--repo` |
| `theme/` | A colour scheme matching PhpStorm's Islands Dark, and light gutter icons |
| `make-test-repo.sh` | Builds a throwaway repo stuck in a merge, for trying everything out |

## Setup

Meld runs straight from its source folder, without a build. The distribution's `meld` package is installed only for the libraries it pulls in, and `libglib2.0-dev-bin` for `glib-compile-resources`, which the first run uses to compile Meld's UI files. The commands below are for Ubuntu and Debian; on other distributions, install their `meld` package and `glib-compile-resources` instead.

```bash
# where you cloned this repo
MELDOWN=~/src/meldown
# libraries (the distribution's own Meld stays unused)
sudo apt install meld libglib2.0-dev-bin
# Meld's source at the release the patches were written for
git clone --depth 1 --branch "$(cat "${MELDOWN:?}/MELD_VERSION")" https://gitlab.gnome.org/GNOME/meld.git ~/.local/src/meld
# the patches, committed on a branch of their own
git -C ~/.local/src/meld switch -c meldown
git -C ~/.local/src/meld am -3 "${MELDOWN:?}"/patches/*.patch
```

Then make it git's merge tool. `trustExitCode` matters: without it, git marks every file you close in Meld as resolved, finished or not.

```bash
git config --global mergetool.meldown.cmd "${MELDOWN:?}/meldown-merge.sh \"\$LOCAL\" \"\$BASE\" \"\$REMOTE\" \"\$MERGED\""
git config --global mergetool.meldown.trustExitCode true
git config --global merge.tool meldown
git config --global mergetool.keepBackup false
# should print true
git config --global --get mergetool.meldown.trustExitCode
```

The wrapper looks for Meld in `~/.local/src/meld`; set `MELD_SRC` if you cloned it elsewhere.

### Theme (optional)

The colour scheme matches PhpStorm's Islands Dark, with IntelliJ's diff colours, and the font is [JetBrains Mono](https://github.com/JetBrains/JetBrainsMono) (SIL Open Font License). The gutter icons replace Meld's own black ones, which ignore a dark theme; they go under the Adwaita theme because Meld's bundled copies win over a user hicolor folder. A source checkout counts as a development build, so GTK gives it a striped title bar, which the stylesheet line removes.

```bash
# colour scheme and gutter icons (copy again after changing them)
mkdir -p ~/.local/share/gtksourceview-4/styles && cp "${MELDOWN:?}"/theme/intellij-islands-dark.xml ~/.local/share/gtksourceview-4/styles/
mkdir -p ~/.local/share/icons/Adwaita/16x16/actions && cp "${MELDOWN:?}"/theme/icons/*.png ~/.local/share/icons/Adwaita/16x16/actions/
# JetBrains Mono
T=$(mktemp -d) && curl -fsSL -o "$T/jbm.zip" https://github.com/JetBrains/JetBrainsMono/releases/download/v2.304/JetBrainsMono-2.304.zip
mkdir -p ~/.local/share/fonts && unzip -q -o -j "$T/jbm.zip" 'fonts/ttf/JetBrainsMono-Regular.ttf' 'fonts/ttf/JetBrainsMono-Bold.ttf' 'fonts/ttf/JetBrainsMono-Italic.ttf' 'fonts/ttf/JetBrainsMono-BoldItalic.ttf' -d ~/.local/share/fonts/ && fc-cache -f ~/.local/share/fonts
# no development-build title bar
mkdir -p ~/.config/gtk-3.0 && printf '%s\n' '.devel headerbar { background-image: none; }' >> ~/.config/gtk-3.0/gtk.css
# Meld settings, through the checkout's own schema
export GSETTINGS_SCHEMA_DIR=$HOME/.local/src/meld/data
gsettings set org.gnome.meld style-scheme intellij-islands-dark
gsettings set org.gnome.meld custom-font 'JetBrains Mono 10'
gsettings set org.gnome.meld use-system-font false
gsettings set org.gnome.meld wrap-mode none
gsettings set org.gnome.meld indent-width 4
for k in prefer-dark-theme show-line-numbers highlight-syntax highlight-current-line; do gsettings set org.gnome.meld $k true; done
```

The quiet colour for changes you have already handled is `meld:resolved` in the colour scheme. Without the theme, Meld's own schemes supply it.

## Use

- `git mergetool` opens each conflicted file in the merge view, one after another. Save and close moves on to the next file.
- `meldown-merge.sh --repo`, run inside a repository with conflicts, opens the Conflicts tab. An alias makes it handy: `alias mergeall='~/src/meldown/meldown-merge.sh --repo'`.

To try both on a throwaway repo:

```bash
# builds ~/tmp/meld-test, stuck in a merge with two conflicted files
bash "${MELDOWN:?}"/make-test-repo.sh
cd ~/tmp/meld-test
git mergetool
```

## Changing the patches

Commit in the checkout on the `meldown` branch, then export the whole series again, so `patches/` always matches the branch. The patches' own tests run from the checkout.

```bash
# tests
cd ~/.local/src/meld && python3 -m unittest test.test_anchored test.test_words test.test_conflicts test.test_matchers
# re-export
rm "${MELDOWN:?}"/patches/*.patch
git -C ~/.local/src/meld format-patch "$(cat "${MELDOWN:?}/MELD_VERSION")..meldown" -o "${MELDOWN:?}"/patches/
```

## Moving to a newer Meld

Stable Meld releases have an even minor version (3.24.x); odd ones (3.23.x) are development releases. Find the latest stable tag, replay the patches onto it, and clear out the old version's compiled UI and settings files, which Meld only rebuilds when they are missing:

```bash
NEW=$(git ls-remote --tags https://gitlab.gnome.org/GNOME/meld.git | grep -oE 'refs/tags/[0-9]+\.[0-9]*[02468]\.[0-9]+$' | sed 's#refs/tags/##' | sort -V | tail -1)
echo "${NEW:?tag lookup failed}"
git -C ~/.local/src/meld fetch --depth 1 origin tag "${NEW:?}"
git -C ~/.local/src/meld rebase --onto "${NEW:?}" "$(cat "${MELDOWN:?}/MELD_VERSION")" meldown
git -C ~/.local/src/meld clean -fdx
```

If a patch no longer fits, the rebase stops on an ordinary merge conflict: resolve it and run `git -C ~/.local/src/meld rebase --continue`. Then run the tests, try both flows on the test repo, write the new tag into `MELD_VERSION`, and export the series again as above.

## WSL

Under WSL, Meld shows as a Linux window through WSLg, so it needs a WSL 2 distribution; WSL 1 cannot show it. Only git run inside WSL uses it.

Meld's size follows each screen's Windows scaling, rounded down to a whole number (200% gives 2x, 125% gives 1x), and changes as the window moves between screens. That only works while Windows arranges the screens in one row or one column. With a more complex layout, WSLg logs "Scaling is used, but can't be supported in complex monitor placement" in `/mnt/wslg/weston.log` and draws every screen at 1x, so Meld looks tiny on a high-density screen. `GDK_SCALE` cannot help, since Meld runs as a Wayland client, where GTK ignores it.

## License

The patches, `meldown-merge.sh` and `make-test-repo.sh` are licensed under the GNU General Public License, version 2 or later, like Meld itself (see `LICENSE`). The files in `theme/` are derived from JetBrains' open-source intellij-community and are under the Apache License 2.0; `NOTICE` says where each comes from. meldown is not affiliated with JetBrains or the GNOME project.
