import type { Meta, StoryObj } from '@storybook/react-vite';
import { expect } from 'storybook/test';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from './table.tsx';

const meta = {
  component: Table,
  title: 'Table',
} satisfies Meta<typeof Table>;

export default meta;
type Story = StoryObj<typeof meta>;

export const Basic: Story = {
  play: async ({ canvas }) => {
    const table = canvas.getByRole('table');
    await expect(table).toBeVisible();
    await expect(canvas.getAllByRole('row')).toHaveLength(3);
    // Borders on <tr> are dropped in the default separate border model.
    await expect(getComputedStyle(table).borderCollapse).toBe('collapse');
  },
  render: () => (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>Name</TableHead>
          <TableHead>Plan</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        <TableRow>
          <TableCell>Mert</TableCell>
          <TableCell>Pro</TableCell>
        </TableRow>
        <TableRow>
          <TableCell>Ada</TableCell>
          <TableCell>Free</TableCell>
        </TableRow>
      </TableBody>
    </Table>
  ),
};
