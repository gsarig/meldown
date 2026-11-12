#!/usr/bin/env bash
# Builds a throwaway git repo stuck in a merge with conflicts, for trying the
# patched Meld, for instance after moving the patches to a new Meld release
# (see README.md). Usage: make-test-repo.sh [dir] (default ~/tmp/meld-test).
# Rerunning it rebuilds the repo from scratch. Then `git mergetool` in it
# tries the merge view one file at a time, and `meldown-merge.sh --repo` the
# Conflicts tab.
#
# "Theirs" is committed with plumbing on a separate index, so the checked-out
# branch never changes while the repo is built.

set -euo pipefail

R=${1:-$HOME/tmp/meld-test}
if [ -e "$R" ]; then
    # Only ever delete a repo this script made.
    [ -f "$R/.git/meld-test-repo" ] || { echo "refusing: $R exists and is not a meld test repo" >&2; exit 1; }
    rm -rf "${R:?}"
fi
mkdir -p "$R/src"
cd "$R"
git init -q -b feature/banner-cards
touch .git/meld-test-repo
git config user.name "Meld test"
git config user.email "meld-test@example.invalid"

# --- base ------------------------------------------------------------------
cat > src/BannerSplit.tsx <<'EOF'
import { Container } from '@/components/ui/container/Container';
import { Heading } from '@/components/ui/heading/Heading';
import { Paragraph } from '@/components/ui/paragraph/Paragraph';
import { cn } from '@/lib/utils';
import type { BannerProps } from './Banner';

// Split banner layout for the homepage.
export function BannerSplit({ banner, className = '' }: BannerProps) {
  const { heading, intro, image } = banner;

  return (
    <section className={cn('bg-green-900 relative', className)}>
      <Container className={cn('flex flex-col gap-6 py-10')}>
        <Heading level={1} styleAs="h1" className="text-pretty">
          {heading}
        </Heading>
        {intro && (
          <Paragraph styleAs="body--lg" className="mt-6">
            {intro}
          </Paragraph>
        )}
      </Container>
    </section>
  );
}
EOF
cat > src/Banner.tsx <<'EOF'
import { cn } from '@/lib/utils';

export type BannerTone = 'light' | 'dark';

export type BannerProps = {
  banner: {
    heading: string;
    intro?: string;
  };
  tone?: BannerTone;
  className?: string;
};

// Classes for the outer section, by tone.
export function bannerClasses(tone: BannerTone = 'dark', className = '') {
  return cn(
    'relative overflow-hidden',
    'transition-colors',
    tone === 'dark' ? 'bg-green-900 text-white' : 'bg-white text-green-900',
    className,
  );
}

// The heading level used when none is given.
export const DEFAULT_LEVEL = 1;

// Trims the intro and drops it when empty.
export function cleanIntro(intro?: string) {
  const text = intro?.trim();
  return text ? text : undefined;
}
EOF
git add -A
git commit -qm "Banner: base"
base=$(git rev-parse HEAD)

# --- theirs (split layout), built on a separate index ------------------------
T=$(mktemp -d)
cat > "$T/BannerSplit.tsx" <<'EOF'
import Image from 'next/image';
import { Container } from '@/components/ui/container/Container';
import { Heading } from '@/components/ui/heading/Heading';
import { Paragraph } from '@/components/ui/paragraph/Paragraph';
import { cn } from '@/lib/utils';
import type { BannerProps } from './Banner';

// Split banner layout for the redesigned homepage, text left, photo right.
export function BannerSplit({ banner, className = '' }: BannerProps) {
  const { heading, intro, image } = banner;

  return (
    <section className={cn('bg-green-900 relative', className)}>
      <Container className={cn('flex flex-col gap-6 py-10 lg:flex-row lg:items-center')}>
        <Heading level={1} styleAs="h1" className="text-pretty">
          {heading}
        </Heading>
        {intro && (
          <Paragraph styleAs="body--lg" className="mt-6">
            {intro}
          </Paragraph>
        )}
      </Container>
    </section>
  );
}
EOF
cat > "$T/Banner.tsx" <<'EOF'
import { cn } from '@/lib/utils';

export type BannerTone = 'light' | 'dark';

export type BannerProps = {
  banner: {
    heading: string;
    intro?: string;
    image?: { url: string; alt: string };
  };
  tone?: BannerTone;
  className?: string;
};

// Classes for the outer section, by tone.
export function bannerClasses(tone: BannerTone = 'dark', className = '') {
  return cn(
    'relative overflow-hidden',
    'transition-colors',
    tone === 'dark' ? 'bg-green-900 text-white' : 'bg-stone-50 text-green-900',
    className,
  );
}

// The heading level used when none is given.
export const DEFAULT_LEVEL = 1;

// Trims the intro and drops it when empty.
export function cleanIntro(intro?: string) {
  const text = intro?.trim();
  return text || undefined;
}
EOF
export GIT_INDEX_FILE=.git/theirs-index
git read-tree "$base"
for f in BannerSplit.tsx Banner.tsx; do
    git update-index --cacheinfo "100644,$(git hash-object -w "$T/$f"),src/$f"
done
theirs=$(git commit-tree "$(git write-tree)" -p "$base" -m "Banner: split layout with photo")
unset GIT_INDEX_FILE
rm -f .git/theirs-index
rm -rf "${T:?}"
git update-ref refs/heads/feature/banner-split-layout "$theirs"

# --- yours (feature cards), on the checked-out branch ------------------------
cat > src/BannerSplit.tsx <<'EOF'
import { Container } from '@/components/ui/container/Container';
import { Heading } from '@/components/ui/heading/Heading';
import { Paragraph } from '@/components/ui/paragraph/Paragraph';
import { cn } from '@/lib/utils';
import type { BannerProps } from './Banner';
import { BannerCard } from './BannerCard';

// Split banner layout for the homepage.
export function BannerSplit({ banner, className = '' }: BannerProps) {
  const { heading, intro, image, cards } = banner;
  const visibleCards = cards.filter((card) => card.heading);

  return (
    <section className={cn('bg-green-900 relative', className)}>
      <Container className={cn('py-10')}>
        <div className="min-w-0 wrap-break-word lg:flex-1">
          <Heading level={1} styleAs="h1" className="text-pretty">
            {heading}
          </Heading>
          {intro && (
            <Paragraph styleAs="body--lg" className="mt-6">
              {intro}
            </Paragraph>
          )}
        </div>
        {visibleCards.map((card) => <BannerCard key={card.heading} card={card} />)}
      </Container>
    </section>
  );
}
EOF
cat > src/Banner.tsx <<'EOF'
import { cn } from '@/lib/utils';

export type BannerTone = 'light' | 'dark';

export type BannerProps = {
  banner: {
    heading: string;
    intro?: string;
    cards?: { heading?: string }[];
  };
  tone?: BannerTone;
  className?: string;
};

// Classes for the outer section, by tone.
export function bannerClasses(tone: BannerTone = 'dark', className = '') {
  return cn(
    'relative isolate overflow-hidden',
    'transition-colors',
    tone === 'dark' ? 'bg-green-900 text-white' : 'bg-white text-green-900',
    className,
  );
}

// The heading level used when none is given.
export const DEFAULT_LEVEL = 2;

// Trims the intro and drops it when empty.
export function cleanIntro(intro?: string) {
  const text = intro?.trim();
  return text ? text : undefined;
}
EOF
git commit -qam "Banner: feature cards"

# --- the merge that conflicts --------------------------------------------------
git merge feature/banner-split-layout >/dev/null 2>&1 || true
echo "Test repo ready: $R"
git status --short
