import type { Meta, StoryObj } from '@storybook/react-vite';
import { expect, userEvent } from 'storybook/test';
import { Button } from './button.tsx';
import { Field, FieldError, FieldLabel } from './field.tsx';
import { Input } from './input.tsx';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from './select.tsx';

const meta = {
  component: Input,
  title: 'Input',
} satisfies Meta<typeof Input>;

export default meta;
type Story = StoryObj<typeof meta>;

export const WithLabel: Story = {
  play: async ({ canvas }) => {
    const input = canvas.getByLabelText('Email');
    await expect(getComputedStyle(input).appearance).toBe('none');
    await userEvent.type(input, 'mert@example.com');
    await expect(input).toHaveValue('mert@example.com');
  },
  render: () => (
    <Field>
      <FieldLabel htmlFor="email">Email</FieldLabel>
      <Input id="email" name="email" type="email" />
    </Field>
  ),
};

export const WithError: Story = {
  play: async ({ canvas }) => {
    await expect(canvas.getByRole('alert')).toHaveTextContent('Enter a valid email address.');
    await expect(canvas.getByLabelText('Email')).toHaveAttribute('aria-invalid', 'true');
  },
  render: () => (
    <Field data-invalid>
      <FieldLabel htmlFor="email-error">Email</FieldLabel>
      <Input aria-invalid defaultValue="not-an-email" id="email-error" name="email" type="email" />
      <FieldError role="alert">Enter a valid email address.</FieldError>
    </Field>
  ),
};

export const Disabled: Story = {
  args: { disabled: true, placeholder: 'Disabled' },
};

const height = (element: HTMLElement) => element.getBoundingClientRect().height;

// An email field next to its submit button, as in a waitlist form: every form
// control shares the default control height, so the row lines up.
export const NextToButton: Story = {
  play: async ({ canvas }) => {
    const input = canvas.getByLabelText('Email');
    await expect(height(input)).toBe(36);
    await expect(height(canvas.getByRole('button', { name: 'Join' }))).toBe(height(input));
    // The button's text is the same size as the field's.
    await expect(getComputedStyle(canvas.getByRole('button', { name: 'Join' })).fontSize).toBe(
      getComputedStyle(input).fontSize,
    );
    await expect(height(canvas.getByRole('combobox', { name: 'Plan' }))).toBe(height(input));
  },
  render: () => (
    <div style={{ alignItems: 'center', display: 'flex', gap: 8, width: 480 }}>
      <Input aria-label="Email" placeholder="you@example.com" type="email" />
      <div style={{ flexShrink: 0, width: 120 }}>
        <Select defaultValue="free" items={[{ label: 'Free', value: 'free' }]}>
          <SelectTrigger aria-label="Plan">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="free">Free</SelectItem>
          </SelectContent>
        </Select>
      </div>
      <Button type="submit">Join</Button>
    </div>
  ),
};
