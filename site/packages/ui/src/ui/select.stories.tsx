import type { Meta, StoryObj } from '@storybook/react-vite';
import { expect, screen, userEvent, waitFor } from 'storybook/test';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from './select.tsx';

const plans = [
  { label: 'Free', value: 'free' },
  { label: 'Pro', value: 'pro' },
  { label: 'Team', value: 'team' },
];

const meta = {
  component: Select,
  title: 'Select',
} satisfies Meta<typeof Select>;

export default meta;
type Story = StoryObj<typeof meta>;

export const Basic: Story = {
  play: async ({ canvas, canvasElement }) => {
    const trigger = canvas.getByRole('combobox', { name: 'Plan' });
    await expect(trigger).toHaveTextContent('Free');
    // The trigger is a native <button>, which would take the browser's control font.
    await expect(getComputedStyle(trigger).fontFamily).toBe(
      getComputedStyle(canvasElement).fontFamily,
    );

    // Pointer: open, pick an option, the popup closes.
    await userEvent.click(trigger);
    // Base UI animates the popup in; assert presence, not mid-transition visibility.
    await expect(await screen.findByRole('listbox')).toBeInTheDocument();
    await userEvent.click(screen.getByRole('option', { name: 'Pro' }));
    await waitFor(() => expect(screen.queryByRole('listbox')).not.toBeInTheDocument());
    await expect(trigger).toHaveTextContent('Pro');

    // Keyboard: open from the focused trigger, move down one, select.
    trigger.focus();
    await userEvent.keyboard('{ArrowDown}');
    await expect(await screen.findByRole('listbox')).toBeInTheDocument();
    await waitFor(() => expect(screen.getByRole('option', { name: 'Pro' })).toHaveFocus());
    await userEvent.keyboard('{ArrowDown}');
    await waitFor(() => expect(screen.getByRole('option', { name: 'Team' })).toHaveFocus());
    await userEvent.keyboard('{Enter}');
    await waitFor(() => expect(screen.queryByRole('listbox')).not.toBeInTheDocument());
    await expect(trigger).toHaveTextContent('Team');
  },
  render: () => (
    <div style={{ width: 180 }}>
      <Select defaultValue="free" items={plans}>
        <SelectTrigger aria-label="Plan">
          <SelectValue />
        </SelectTrigger>
        <SelectContent>
          {plans.map((plan) => (
            <SelectItem key={plan.value} value={plan.value}>
              {plan.label}
            </SelectItem>
          ))}
        </SelectContent>
      </Select>
    </div>
  ),
};

const PlanSelect = ({
  invalid,
  label,
}: {
  invalid?: 'false' | 'grammar' | undefined;
  label: string;
}) => (
  <Select defaultValue="free" items={plans}>
    <SelectTrigger aria-invalid={invalid} aria-label={label}>
      <SelectValue />
    </SelectTrigger>
    <SelectContent>
      {plans.map((plan) => (
        <SelectItem key={plan.value} value={plan.value}>
          {plan.label}
        </SelectItem>
      ))}
    </SelectContent>
  </Select>
);

// Every aria-invalid value except "false" gets the invalid ring, not only
// true/"true". No aria-invalid, or "false", gets none.
export const Invalid: Story = {
  play: async ({ canvas }) => {
    const grammar = canvas.getByRole('combobox', { name: 'Grammar' });
    await expect(grammar).toHaveAttribute('aria-invalid', 'grammar');
    await expect(getComputedStyle(grammar).boxShadow).not.toBe('none');

    const unset = canvas.getByRole('combobox', { name: 'Unset' });
    await expect(unset).not.toHaveAttribute('aria-invalid');
    await expect(getComputedStyle(unset).boxShadow).toBe('none');

    const valid = canvas.getByRole('combobox', { name: 'False' });
    await expect(valid).toHaveAttribute('aria-invalid', 'false');
    await expect(getComputedStyle(valid).boxShadow).toBe('none');
  },
  render: () => (
    <div style={{ display: 'grid', gap: 8, width: 180 }}>
      <PlanSelect invalid="grammar" label="Grammar" />
      <PlanSelect label="Unset" />
      <PlanSelect invalid="false" label="False" />
    </div>
  ),
};

// The trigger is a native <button>: without a color of its own it keeps the
// browser's black button text on the dark background. Dark mode is emulated
// over the Chrome DevTools Protocol, as in the Button DarkMode story.
export const DarkMode: Story = {
  play: async ({ canvas, canvasElement }) => {
    const browser = await import('vitest/browser').catch(() => null);
    if (!browser) {
      return;
    }
    const trigger = canvas.getByRole('combobox', { name: 'Plan' });
    const session = browser.cdp();
    await session.send('Emulation.setEmulatedMedia', {
      features: [{ name: 'prefers-color-scheme', value: 'dark' }],
    });
    try {
      await expect(matchMedia('(prefers-color-scheme: dark)').matches).toBe(true);
      const foreground = getComputedStyle(canvasElement).color;
      await expect(foreground).not.toBe('rgb(0, 0, 0)');
      // The trigger transitions its color, so wait it out.
      await waitFor(() => expect(getComputedStyle(trigger).color).toBe(foreground));
    } finally {
      await session.send('Emulation.setEmulatedMedia', {
        features: [{ name: 'prefers-color-scheme', value: 'light' }],
      });
    }
  },
  render: () => (
    <div style={{ width: 180 }}>
      <PlanSelect label="Plan" />
    </div>
  ),
};
