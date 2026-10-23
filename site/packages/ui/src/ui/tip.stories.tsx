import type { Meta, StoryObj } from '@storybook/react-vite';
import type { CDPSession } from '@vitest/browser-playwright';
import { expect, fn, screen, userEvent, waitFor, within } from 'storybook/test';
import { Button } from './button.tsx';
import { Tip } from './tip.tsx';

const content = 'Billing renews on the first day of each month.';

const meta = {
  args: {
    children: content,
    closeLabel: 'Close',
    onOpenChange: fn(),
    title: 'Renewal',
    trigger: <Button variant="outline">Billing</Button>,
  },
  component: Tip,
  title: 'Tip',
} satisfies Meta<typeof Tip>;

export default meta;
type Story = StoryObj<typeof meta>;

// The popover waits 600ms of rest on the trigger before it opens on hover.
const hoverTimeout = { timeout: 2000 };

export const Hover: Story = {
  play: async ({ args, canvas }) => {
    const trigger = canvas.getByRole('button', { name: 'Billing' });
    await userEvent.hover(trigger);
    // Base UI animates the popup in; assert presence, not mid-transition visibility.
    const popup = await screen.findByRole('dialog', { name: 'Renewal' }, hoverTimeout);
    await expect(popup).toHaveAttribute('data-slot', 'tip');
    await expect(within(popup).getByText(content)).toBeInTheDocument();
    await expect(args.onOpenChange).toHaveBeenLastCalledWith(
      true,
      expect.objectContaining({ reason: 'trigger-hover' }),
    );
    // Opened by hover, it leaves focus where it was.
    await expect(popup).not.toHaveFocus();
    await userEvent.unhover(trigger);
    await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument());
    await expect(args.onOpenChange).toHaveBeenLastCalledWith(
      false,
      expect.objectContaining({ reason: 'trigger-hover' }),
    );
  },
};

export const Keyboard: Story = {
  play: async ({ args, canvas }) => {
    const trigger = canvas.getByRole('button', { name: 'Billing' });
    await userEvent.tab();
    await expect(trigger).toHaveFocus();
    await userEvent.keyboard('{Enter}');
    const popup = await screen.findByRole('dialog', { name: 'Renewal' });
    await expect(args.onOpenChange).toHaveBeenLastCalledWith(
      true,
      expect.objectContaining({ reason: 'trigger-press' }),
    );
    // Focus moves in, so a screen reader announces the title and content.
    await waitFor(() => expect(popup).toHaveFocus());
    await userEvent.keyboard('{Escape}');
    await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument());
    await expect(args.onOpenChange).toHaveBeenLastCalledWith(
      false,
      expect.objectContaining({ reason: 'escape-key' }),
    );
    await expect(trigger).toHaveFocus();
  },
};

// A pointer that can hover can also click or tap, as on a touchscreen laptop.
export const Click: Story = {
  play: async ({ args, canvas }) => {
    await expect(matchMedia('(hover: hover)').matches).toBe(true);
    await userEvent.click(canvas.getByRole('button', { name: 'Billing' }));
    await expect(await screen.findByRole('dialog', { name: 'Renewal' })).toBeInTheDocument();
    await expect(args.onOpenChange).toHaveBeenLastCalledWith(
      true,
      expect.objectContaining({ reason: 'trigger-press' }),
    );
    await userEvent.click(document.body);
    await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument());
    await expect(args.onOpenChange).toHaveBeenLastCalledWith(
      false,
      expect.objectContaining({ reason: 'outside-press' }),
    );
  },
};

export const Accessible: Story = {
  play: async ({ canvas }) => {
    const trigger = canvas.getByRole('button', { name: 'Billing' });
    await expect(trigger).toHaveAttribute('aria-haspopup', 'dialog');
    await expect(trigger).toHaveAttribute('aria-expanded', 'false');
    await userEvent.click(trigger);
    const popup = await screen.findByRole('dialog');
    await expect(trigger).toHaveAttribute('aria-expanded', 'true');
    await expect(trigger).toHaveAttribute('aria-controls', popup.id);
    // Named by its title, a heading, and described by its content.
    const title = within(popup).getByRole('heading', { name: 'Renewal' });
    await expect(popup).toHaveAttribute('aria-labelledby', title.id);
    await expect(popup).toHaveAccessibleName('Renewal');
    await expect(popup).toHaveAccessibleDescription(content);
    // The heading keeps the popup's type, not a browser h2's.
    const { fontSize, fontWeight, marginBlockStart } = getComputedStyle(title);
    await expect({ fontSize, fontWeight, marginBlockStart }).toEqual({
      fontSize: '14px',
      fontWeight: '500',
      marginBlockStart: '0px',
    });
    await userEvent.keyboard('{Escape}');
    await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument());
  },
};

// Real touches over the Chrome DevTools Protocol. CDP takes page coordinates,
// and the story renders in an iframe that Vitest scales to fit the page, so
// the element's center is scaled and offset by the frame.
const pageCenter = (element: Element) => {
  const frame = globalThis.frameElement?.getBoundingClientRect();
  const scale = frame ? frame.width / globalThis.innerWidth : 1;
  const rect = element.getBoundingClientRect();
  return {
    scale,
    x: (frame?.left ?? 0) + (rect.left + rect.width / 2) * scale,
    y: (frame?.top ?? 0) + (rect.top + rect.height / 2) * scale,
  };
};

const tap = async (session: CDPSession, element: Element) => {
  const { x, y } = pageCenter(element);
  await session.send('Input.dispatchTouchEvent', { touchPoints: [{ x, y }], type: 'touchStart' });
  await session.send('Input.dispatchTouchEvent', { touchPoints: [], type: 'touchEnd' });
};

// A finger drag from the element's center, `distance` story pixels down.
const swipeDown = async (session: CDPSession, element: Element, distance: number) => {
  const { scale, x, y } = pageCenter(element);
  await session.send('Input.dispatchTouchEvent', { touchPoints: [{ x, y }], type: 'touchStart' });
  for (let step = 1; step <= 10; step++) {
    await session.send('Input.dispatchTouchEvent', {
      touchPoints: [{ x, y: y + (distance * scale * step) / 10 }],
      type: 'touchMove',
    });
  }
  await session.send('Input.dispatchTouchEvent', { touchPoints: [], type: 'touchEnd' });
};

// A phone: touch emulation makes the primary input coarse and unable to hover,
// so the Tip renders a sheet. vitest/browser only loads in the Vitest run; in
// the Storybook UI the story only renders.
export const Phone: Story = {
  play: async ({ args, canvas }) => {
    const browser = await import('vitest/browser').catch(() => null);
    if (!browser) {
      return;
    }
    // Playwright's session type, as in .storybook/preview.ts.
    const session = browser.cdp() as CDPSession;
    const popoverTrigger = canvas.getByRole('button', { name: 'Billing' });
    await session.send('Emulation.setTouchEmulationEnabled', { enabled: true, maxTouchPoints: 1 });
    try {
      await expect(matchMedia('(hover: none)').matches).toBe(true);
      // The trigger is now the sheet's: React mounts a new button for it.
      await waitFor(() =>
        expect(canvas.getByRole('button', { name: 'Billing' })).not.toBe(popoverTrigger),
      );
      await tap(session, canvas.getByRole('button', { name: 'Billing' }));
      const sheet = await screen.findByRole('dialog', { name: 'Renewal' });
      await expect(within(sheet).getByText(content)).toBeInTheDocument();
      await expect(args.onOpenChange).toHaveBeenLastCalledWith(
        true,
        expect.objectContaining({ reason: 'trigger-press' }),
      );

      // The sheet slides up; tap its close button once it has come to rest.
      await waitFor(() => expect(sheet.getAnimations()).toHaveLength(0));
      const close = within(sheet).getByRole('button', { name: 'Close' });
      // A 28px square whose ::before keeps the 40px hit area.
      await expect(close.offsetHeight).toBe(28);
      await expect(getComputedStyle(close, '::before').top).toBe('-6px');
      await tap(session, close);
      await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument());
      await expect(args.onOpenChange).toHaveBeenLastCalledWith(
        false,
        expect.objectContaining({ reason: 'close-press' }),
      );

      // A swipe down dismisses it too.
      await tap(session, canvas.getByRole('button', { name: 'Billing' }));
      const swiped = await screen.findByRole('dialog', { name: 'Renewal' });
      await waitFor(() => expect(swiped.getAnimations()).toHaveLength(0));
      await swipeDown(session, within(swiped).getByText('Renewal'), 200);
      await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument());
      await expect(args.onOpenChange).toHaveBeenLastCalledWith(
        false,
        expect.objectContaining({ reason: 'swipe' }),
      );
    } finally {
      await session.send('Emulation.setTouchEmulationEnabled', { enabled: false });
    }
  },
};
