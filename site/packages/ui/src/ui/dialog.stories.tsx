import type { Meta, StoryObj } from '@storybook/react-vite';
import { expect, screen, userEvent, waitFor } from 'storybook/test';
import { Button } from './button.tsx';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from './dialog.tsx';

const meta = {
  component: Dialog,
  title: 'Dialog',
} satisfies Meta<typeof Dialog>;

export default meta;
type Story = StoryObj<typeof meta>;

export const Basic: Story = {
  play: async ({ canvas }) => {
    await userEvent.click(canvas.getByRole('button', { name: 'Open dialog' }));
    // Base UI animates the popup in; assert presence, not mid-transition visibility.
    const dialog = await screen.findByRole('dialog');
    await expect(dialog).toBeInTheDocument();
    await expect(screen.getByText('Are you sure?')).toBeInTheDocument();
    await userEvent.keyboard('{Escape}');
    await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument());
  },
  render: () => (
    <Dialog>
      <DialogTrigger render={<Button variant="outline" />}>Open dialog</DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Are you sure?</DialogTitle>
          <DialogDescription>This action cannot be undone.</DialogDescription>
        </DialogHeader>
        <DialogFooter>
          <Button>Confirm</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  ),
};

const paragraphs = Array.from({ length: 40 }, (_, index) => `Paragraph ${index + 1}`);

export const LongContent: Story = {
  play: async ({ canvas }) => {
    await userEvent.click(canvas.getByRole('button', { name: 'Open dialog' }));
    const dialog = await screen.findByRole('dialog');
    // Capped at the viewport height, with the overflow scrolling inside.
    await expect(dialog.getBoundingClientRect().height).toBeLessThanOrEqual(globalThis.innerHeight);
    const last = screen.getByText('Paragraph 40');
    await expect(last.getBoundingClientRect().top).toBeGreaterThan(
      dialog.getBoundingClientRect().bottom,
    );

    // Scrolled to the end, the close button is still inside the dialog and on top.
    last.scrollIntoView();
    const dialogRect = dialog.getBoundingClientRect();
    await expect(last.getBoundingClientRect().bottom).toBeLessThanOrEqual(dialogRect.bottom);
    const close = screen.getByRole('button', { name: 'Close' });
    const closeRect = close.getBoundingClientRect();
    // A 28px square whose ::before keeps the 40px hit area. offsetHeight, as
    // the popup may still be scaling in.
    await expect(close.offsetHeight).toBe(28);
    await expect(getComputedStyle(close, '::before').top).toBe('-6px');
    await expect(closeRect.top).toBeGreaterThanOrEqual(dialogRect.top);
    await expect(closeRect.bottom).toBeLessThanOrEqual(dialogRect.bottom);
    const hit = document.elementFromPoint(
      closeRect.left + closeRect.width / 2,
      closeRect.top + closeRect.height / 2,
    );
    await expect(close.contains(hit)).toBe(true);

    await userEvent.click(close);
    await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument());
  },
  render: () => (
    <Dialog>
      <DialogTrigger render={<Button variant="outline" />}>Open dialog</DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Terms</DialogTitle>
          <DialogDescription>Scroll to read all of it.</DialogDescription>
        </DialogHeader>
        {paragraphs.map((text) => (
          <p key={text}>{text}</p>
        ))}
      </DialogContent>
    </Dialog>
  ),
};

export const CloseLabel: Story = {
  play: async ({ canvas }) => {
    await userEvent.click(canvas.getByRole('button', { name: 'Open dialog' }));
    await userEvent.click(await screen.findByRole('button', { name: 'Kapat' }));
    await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument());
  },
  render: () => (
    <Dialog>
      <DialogTrigger render={<Button variant="outline" />}>Open dialog</DialogTrigger>
      <DialogContent closeLabel="Kapat">
        <DialogHeader>
          <DialogTitle>Localized close</DialogTitle>
        </DialogHeader>
      </DialogContent>
    </Dialog>
  ),
};
