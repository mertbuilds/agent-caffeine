import type { Meta, StoryObj } from '@storybook/react-vite';
import { expect, within } from 'storybook/test';
import { Badge } from './badge.tsx';
import { Button } from './button.tsx';
import {
  Card,
  CardAction,
  CardContent,
  CardDescription,
  CardFooter,
  CardHeader,
  CardTitle,
} from './card.tsx';

const meta = {
  component: Card,
  title: 'Card',
} satisfies Meta<typeof Card>;

export default meta;
type Story = StoryObj<typeof meta>;

export const Default: Story = {
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(canvas.getByText('Billing')).toBeInTheDocument();
    await expect(canvas.getByText('Active')).toBeInTheDocument();
    await expect(canvas.getByRole('button', { name: 'Manage' })).toBeInTheDocument();
  },
  render: () => (
    <Card style={{ width: 360 }}>
      <CardHeader>
        <CardTitle>Billing</CardTitle>
        <CardDescription>Your current subscription.</CardDescription>
        <CardAction>
          <Badge>Active</Badge>
        </CardAction>
      </CardHeader>
      <CardContent>Pro — $20 / month</CardContent>
      <CardFooter>
        <Button variant="outline">Manage</Button>
      </CardFooter>
    </Card>
  ),
};

export const Small: Story = {
  render: () => (
    <Card size="sm" style={{ width: 280 }}>
      <CardHeader>
        <CardTitle>Compact card</CardTitle>
      </CardHeader>
      <CardContent>Small spacing variant.</CardContent>
    </Card>
  ),
};
