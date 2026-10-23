import type { Meta, StoryObj } from '@storybook/react-vite';
import { expect, fn, userEvent, waitFor } from 'storybook/test';
import { Button } from './button.tsx';

const meta = {
  args: { children: 'Button', onClick: fn() },
  component: Button,
  title: 'Button',
} satisfies Meta<typeof Button>;

export default meta;
type Story = StoryObj<typeof meta>;

export const Default: Story = {
  play: async ({ args, canvas, canvasElement }) => {
    const button = canvas.getByRole('button', { name: 'Button' });
    await expect(button).toHaveAttribute('type', 'button');
    // 36px pill, and its ::before widens the hit area to 40px.
    await expect(button.getBoundingClientRect().height).toBe(36);
    await expect(getComputedStyle(button, '::before').top).toBe('-2px');
    // A native <button> takes the browser's control font unless it inherits
    // the one around it.
    await expect(getComputedStyle(button).fontFamily).toBe(
      getComputedStyle(canvasElement).fontFamily,
    );
    await userEvent.click(button);
    await expect(args.onClick).toHaveBeenCalledOnce();
  },
};

// Only an explicit type="submit" submits the surrounding form.
export const InForm: Story = {
  play: async ({ canvas }) => {
    const onSubmit = fn((event: Event) => event.preventDefault());
    canvas.getByRole('form', { name: 'Settings' }).addEventListener('submit', onSubmit);
    await userEvent.click(canvas.getByRole('button', { name: 'Cancel' }));
    await expect(onSubmit).not.toHaveBeenCalled();
    const save = canvas.getByRole('button', { name: 'Save' });
    await expect(save).toHaveAttribute('type', 'submit');
    await userEvent.click(save);
    await expect(onSubmit).toHaveBeenCalledOnce();
  },
  render: () => (
    <form aria-label="Settings">
      <Button variant="outline">Cancel</Button>
      <Button type="submit">Save</Button>
    </form>
  ),
};

export const Secondary: Story = {
  args: { variant: 'secondary' },
};

export const Outline: Story = {
  args: { variant: 'outline' },
};

// Link-rendered buttons must look like buttons: global anchor styles in
// theme.css must not override the StyleX color or add an underline.
const expectButtonStyledLink = async (link: HTMLElement) => {
  const style = getComputedStyle(link);
  await expect(style.textDecorationLine).toBe('none');
  await expect(style.color).not.toBe(style.backgroundColor);
};

export const AsLink: Story = {
  args: { render: <a href="#as-link" /> },
  play: async ({ canvas }) => {
    await expectButtonStyledLink(canvas.getByRole('link', { name: 'Button' }));
  },
};

export const OutlineAsLink: Story = {
  args: { render: <a href="#as-link" />, variant: 'outline' },
  play: async ({ canvas }) => {
    await expectButtonStyledLink(canvas.getByRole('link', { name: 'Button' }));
  },
};

// The color a CSS value computes to right now, to compare variant rules
// against the theme tokens of the active color scheme.
const computedColor = (value: string) => {
  const probe = document.createElement('div');
  probe.style.color = value;
  document.body.append(probe);
  const { color } = getComputedStyle(probe);
  probe.remove();
  return color;
};

// Dark mode follows prefers-color-scheme, so the play function emulates it over
// the Chrome DevTools Protocol. vitest/browser only loads in the Vitest run; in
// the Storybook UI the story only renders.
export const DarkMode: Story = {
  play: async ({ canvas }) => {
    const browser = await import('vitest/browser').catch(() => null);
    if (!browser) {
      return;
    }
    const outline = canvas.getByRole('button', { name: 'Outline' });
    const destructive = canvas.getByRole('button', { name: 'Destructive' });
    await expect(getComputedStyle(outline).backgroundColor).toBe(
      computedColor('var(--background)'),
    );
    const session = browser.cdp();
    await session.send('Emulation.setEmulatedMedia', {
      features: [{ name: 'prefers-color-scheme', value: 'dark' }],
    });
    try {
      await expect(matchMedia('(prefers-color-scheme: dark)').matches).toBe(true);
      // Buttons transition background and border colors, so wait them out.
      await waitFor(async () => {
        await expect(getComputedStyle(outline).backgroundColor).toBe(
          computedColor('color-mix(in oklab, var(--input) 30%, transparent)'),
        );
        await expect(getComputedStyle(outline).borderTopColor).toBe(computedColor('var(--input)'));
        await expect(getComputedStyle(destructive).backgroundColor).toBe(
          computedColor('color-mix(in oklab, var(--destructive) 20%, transparent)'),
        );
      });
    } finally {
      await session.send('Emulation.setEmulatedMedia', {
        features: [{ name: 'prefers-color-scheme', value: 'light' }],
      });
    }
  },
  render: () => (
    <>
      <Button variant="outline">Outline</Button>
      <Button variant="destructive">Destructive</Button>
    </>
  ),
};

export const Disabled: Story = {
  args: { disabled: true },
  play: async ({ args, canvas }) => {
    const button = canvas.getByRole('button', { name: 'Button' });
    await expect(button).toBeDisabled();
    await userEvent.click(button).catch(() => undefined);
    await expect(args.onClick).not.toHaveBeenCalled();
  },
};

export const DisabledAsLink: Story = {
  args: { disabled: true, render: <a href="#disabled-link" /> },
  play: async ({ args, canvas }) => {
    const link = canvas.getByRole('link', { name: 'Button' });
    await expect(link).toHaveAttribute('aria-disabled', 'true');
    await expect(link).toHaveAttribute('tabindex', '-1');
    await expect(link).not.toHaveAttribute('disabled');
    await expect(link).not.toHaveAttribute('type');
    // Keyboard: Tab skips it, and Enter on it (focused programmatically) does nothing.
    await userEvent.tab();
    await expect(link).not.toHaveFocus();
    link.focus();
    await userEvent.keyboard('{Enter}');
    link.click();
    await expect(args.onClick).not.toHaveBeenCalled();
    await expect(globalThis.location.hash).not.toBe('#disabled-link');
  },
};
