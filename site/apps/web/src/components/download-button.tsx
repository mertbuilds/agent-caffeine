import { create, props, type StyleXStyles } from '@stylexjs/stylex';
import { rootRouteId, useLoaderData } from '@tanstack/react-router';
import { useSyncExternalStore, type ReactNode } from 'react';
import { downloadLink } from '../lib/download.ts';
import type { Release } from '../lib/release.ts';
import { isMacDevice, openSendToMac } from '../lib/send-to-mac.ts';
import { rememberedUtm, track, type Placement } from '../lib/track.ts';
import { m } from '../paraglide/messages.js';
import { pill } from './pill.ts';

const subscribe = () => () => {};

function onServer(): null {
  return null;
}

/** The newest release, which the root route loads for every page, or null while there is none. */
export function useRelease(): Release | null {
  return useLoaderData({ from: rootRouteId }) ?? null;
}

const styles = create({
  // The body of the mark, without its leaf, sits at the middle of the capitals.
  mark: {
    flexShrink: 0,
    height: '0.84em',
    transform: 'translateY(-0.15em)',
    width: 'auto',
  },
  // The small text size puts the middle of the capitals a little higher in its line.
  markSmall: {
    transform: 'translateY(-0.19em)',
  },
  withMark: {
    alignItems: 'center',
    display: 'flex',
    gap: '7px',
    justifyContent: 'center',
  },
});

/** Words with the Apple mark before them. */
export function WithAppleMark({
  children,
  small = false,
}: {
  children: ReactNode;
  small?: boolean;
}) {
  return (
    <span {...props(styles.withMark)}>
      <svg
        aria-hidden="true"
        fill="currentColor"
        viewBox="0 0 814 1000"
        {...props(styles.mark, small && styles.markSmall)}
      >
        <path d="M788.1 340.9c-5.8 4.5-108.2 62.2-108.2 190.5 0 148.4 130.3 200.9 134.2 202.2-.6 3.2-20.7 71.9-68.7 141.9-42.8 61.6-87.5 123.1-155.5 123.1s-85.5-39.5-164-39.5c-76.5 0-103.7 40.8-165.9 40.8s-105.6-57-155.5-127C46.7 790.7 0 663 0 541.8c0-194.4 126.4-297.5 250.8-297.5 66.1 0 121.2 43.4 162.7 43.4 39.5 0 101.1-46 176.3-46 28.5 0 130.9 2.6 198.3 99.2zm-234-181.5c31.1-36.9 53.1-88.1 53.1-139.3 0-7.1-.6-14.3-1.9-20.1-50.6 1.9-110.8 33.7-147.1 75.8-28.5 32.4-55.1 83.6-55.1 135.5 0 7.8 1.3 15.6 1.9 18.1 3.2.6 8.4 1.3 13.6 1.3 45.4 0 102.5-30.4 135.5-71.3z" />
      </svg>
      {children}
    </span>
  );
}

/** The words of a button that starts the free trial. */
export function TryFree({ small = false }: { small?: boolean }) {
  return <WithAppleMark small={small}>{m.download_try_free()}</WithAppleMark>;
}

/**
 * A link to the dmg, by way of `/download`, where the server counts it. The
 * release's `href` tells a sample release, which has no file, from a real one.
 * The click is also counted in the browser with where it sits.
 *
 * The link is the same for everyone, so it works with no script. Off a Mac,
 * where the app cannot run, a click starts no download: it opens the popup
 * that sends the link on to a Mac (components/send-to-mac-popup.tsx), and is
 * counted apart.
 */
export function DownloadLink({
  children,
  placement,
  release,
  style,
}: {
  children: ReactNode;
  placement: Placement;
  release: Release;
  style?: StyleXStyles;
}) {
  const utm = useSyncExternalStore(subscribe, rememberedUtm, onServer);
  return (
    <a
      download={release.href.startsWith('#') ? undefined : release.filename}
      href={downloadLink(placement, utm)}
      onClick={(event) => {
        if (isMacDevice(navigator.userAgent, navigator.maxTouchPoints)) {
          track('download_click', { placement });
          return;
        }
        event.preventDefault();
        track('download_blocked_not_mac', { placement });
        openSendToMac(event.currentTarget);
      }}
      {...props(style)}
    >
      {children}
    </a>
  );
}

const SIZES = { compact: pill.compact, large: pill.large, small: pill.small };

const LOOKS = {
  brand: [pill.onBrand, pill.brand],
  brandOutline: [pill.onBrand, pill.brandOutline],
  solid: [pill.base, pill.ink],
};

/** A download link drawn as a pill, the page's ink by default or one of the pricing card's. */
export function DownloadButton({
  children,
  placement,
  release,
  size = 'large',
  variant = 'solid',
}: {
  children: ReactNode;
  placement: Placement;
  release: Release;
  size?: keyof typeof SIZES;
  variant?: keyof typeof LOOKS;
}) {
  return (
    <DownloadLink placement={placement} release={release} style={[LOOKS[variant], SIZES[size]]}>
      {children}
    </DownloadLink>
  );
}
