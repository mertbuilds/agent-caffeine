import type { Meta, StoryObj } from '@storybook/react-vite';
import { expect, screen, userEvent, waitFor, within } from 'storybook/test';
import { InfoTip } from './info-tip.tsx';

const content = 'Seats are the people on your plan.';

const meta = {
  args: {
    children: content,
    closeLabel: 'Close',
    label: 'About seats',
  },
  component: InfoTip,
  title: 'InfoTip',
} satisfies Meta<typeof InfoTip>;

export default meta;
type Story = StoryObj<typeof meta>;

export const Default: Story = {
  play: async ({ canvas }) => {
    const button = canvas.getByRole('button', { name: 'About seats' });
    await userEvent.tab();
    await expect(button).toHaveFocus();
    await userEvent.keyboard('{Enter}');
    const popup = await screen.findByRole('dialog', { name: 'About seats' });
    await expect(within(popup).getByText(content)).toBeInTheDocument();
    await userEvent.keyboard('{Escape}');
    await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument());
    await expect(button).toHaveFocus();
  },
  render: (args) => (
    <p style={{ fontSize: 14, margin: 0 }}>
      Seats <InfoTip {...args} />
    </p>
  ),
};

// The icon follows the size; the press stays 24px either way.
export const Sizes: Story = {
  play: async ({ canvas }) => {
    for (const [name, icon] of [
      ['About plans', 20],
      ['About seats', 14],
    ] as const) {
      const button = canvas.getByRole('button', { name });
      const { height, width } = button.getBoundingClientRect();
      await expect({ height, width }).toEqual({ height: 24, width: 24 });
      const svg = button.querySelector('svg');
      await expect(svg?.getBoundingClientRect().width).toBe(icon);
    }
  },
  render: (args) => (
    <div style={{ display: 'grid', gap: 16 }}>
      <h2 style={{ fontSize: 24, fontWeight: 500, margin: 0 }}>
        Plans{' '}
        <InfoTip {...args} label="About plans" size="large">
          Every plan includes unlimited projects.
        </InfoTip>
      </h2>
      <p style={{ fontSize: 14, margin: 0 }}>
        Seats <InfoTip {...args} size="small" />
      </p>
    </div>
  ),
};
