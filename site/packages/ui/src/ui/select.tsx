'use client';

import { Select as SelectPrimitive } from '@base-ui/react/select';
import { create, props as stylexProps } from '@stylexjs/stylex';
import type { StyleXStyles } from '@stylexjs/stylex';
import { CheckIcon, ChevronDownIcon, ChevronUpIcon } from 'lucide-react';
import type { ComponentProps } from 'react';
import { colors, controlHeight, radius } from '../lib/tokens.stylex.ts';
import { customClassName } from '../lib/utils.stylex.ts';

const isHidden = (status: string | undefined) => status === 'starting' || status === 'ending';

const styles = create({
  content: {
    backgroundColor: colors.popover,
    borderRadius: radius.md,
    boxShadow: `0 4px 6px -1px rgba(0, 0, 0, 0.1), 0 2px 4px -2px rgba(0, 0, 0, 0.1), 0 0 0 1px color-mix(in oklab, ${colors.foreground} 10%, transparent)`,
    color: colors.popoverForeground,
    isolation: 'isolate',
    maxHeight: 'var(--available-height)',
    minWidth: '9rem',
    opacity: 1,
    outline: 'none',
    overflowX: 'hidden',
    overflowY: 'auto',
    position: 'relative',
    transform: 'scale(1)',
    transformOrigin: 'var(--transform-origin)',
    transitionDuration: '100ms',
    transitionProperty: 'opacity, transform',
    transitionTimingFunction: 'cubic-bezier(0, 0, 0.2, 1)',
    width: 'var(--anchor-width)',
    zIndex: 50,
  },
  contentHidden: {
    opacity: 0,
    transform: 'scale(0.95)',
  },
  group: {
    scrollMarginBlock: '0.25rem',
  },
  icon: {
    flexShrink: 0,
    height: '1rem',
    pointerEvents: 'none',
    width: '1rem',
  },
  item: {
    ':is(svg)': {
      flexShrink: 0,
      height: '1rem',
      pointerEvents: 'none',
      width: '1rem',
    },
    alignItems: 'center',
    backgroundColor: {
      ':focus': colors.accent,
      ':hover': colors.accent,
      default: 'transparent',
    },
    borderRadius: `calc(${radius.md} - 4px)`,
    color: {
      ':focus': colors.accentForeground,
      ':hover': colors.accentForeground,
      default: colors.foreground,
    },
    cursor: 'default',
    display: 'flex',
    fontSize: '0.875rem',
    gap: '0.375rem',
    lineHeight: '1.25rem',
    outline: 'none',
    paddingBottom: '0.25rem',
    paddingLeft: '0.375rem',
    paddingRight: '2rem',
    paddingTop: '0.25rem',
    position: 'relative',
    userSelect: 'none',
    width: '100%',
  },
  itemDisabled: {
    cursor: 'not-allowed',
    opacity: 0.5,
    pointerEvents: 'none',
  },
  itemHighlighted: {
    backgroundColor: colors.accent,
    color: colors.accentForeground,
  },
  itemIndicator: {
    alignItems: 'center',
    display: 'flex',
    height: '1rem',
    justifyContent: 'center',
    pointerEvents: 'none',
    position: 'absolute',
    right: '0.5rem',
    width: '1rem',
  },
  itemText: {
    display: 'flex',
    flex: 1,
    flexShrink: 0,
    gap: '0.5rem',
    whiteSpace: 'nowrap',
  },
  label: {
    color: colors.mutedForeground,
    fontSize: '0.75rem',
    fontWeight: 500,
    lineHeight: '1rem',
    paddingBottom: '0.375rem',
    paddingLeft: '0.5rem',
    paddingRight: '0.5rem',
    paddingTop: '0.375rem',
  },
  list: {
    padding: '0.25rem',
  },
  positioner: {
    isolation: 'isolate',
    outline: 'none',
    zIndex: 50,
  },
  scrollButton: {
    alignItems: 'center',
    backgroundColor: colors.popover,
    cursor: 'default',
    display: 'flex',
    justifyContent: 'center',
    paddingBlock: '0.25rem',
    position: 'relative',
    width: '100%',
    zIndex: 10,
  },
  scrollButtonDown: {
    bottom: 0,
  },
  scrollButtonUp: {
    top: 0,
  },
  separator: {
    backgroundColor: colors.border,
    height: '1px',
    marginBlock: '0.25rem',
    marginInline: '-0.25rem',
    pointerEvents: 'none',
  },
  trigger: {
    ':is(svg)': {
      flexShrink: 0,
      height: '1rem',
      pointerEvents: 'none',
      width: '1rem',
    },
    alignItems: 'center',
    backgroundColor: 'transparent',
    borderColor: {
      ':focus-visible': colors.ring,
      default: colors.input,
    },
    borderRadius: radius.full,
    borderStyle: 'solid',
    borderWidth: '1px',
    boxShadow: {
      ':focus-visible': `0 0 0 3px color-mix(in oklab, ${colors.ring} 50%, transparent)`,
      default: null,
    },
    color: colors.foreground,
    cursor: {
      ':disabled': 'not-allowed',
      default: 'pointer',
    },
    display: 'flex',
    fontFamily: 'inherit',
    fontSize: '0.875rem',
    gap: '0.375rem',
    justifyContent: 'space-between',
    lineHeight: '1.25rem',
    opacity: {
      ':disabled': 0.5,
      default: 1,
    },
    outline: 'none',
    paddingBottom: '0.5rem',
    paddingLeft: '0.625rem',
    paddingRight: '0.5rem',
    paddingTop: '0.5rem',
    pointerEvents: {
      ':disabled': 'none',
      default: null,
    },
    transitionDuration: '150ms',
    transitionProperty: 'color, background-color, border-color, box-shadow',
    userSelect: 'none',
    whiteSpace: 'nowrap',
    width: '100%',
  },
  triggerAriaInvalid: {
    borderColor: colors.destructive,
    boxShadow: {
      ':focus-visible': `0 0 0 3px color-mix(in oklab, ${colors.destructive} 40%, transparent)`,
      default: `0 0 0 3px color-mix(in oklab, ${colors.destructive} 20%, transparent)`,
    },
  },
  triggerDefault: {
    height: controlHeight.default,
  },
  triggerIcon: {
    color: colors.mutedForeground,
    flexShrink: 0,
    height: '1rem',
    pointerEvents: 'none',
    width: '1rem',
  },
  triggerSm: {
    borderRadius: radius.full,
    height: controlHeight.sm,
  },
  value: {
    display: 'flex',
    flex: 1,
    textAlign: 'left',
  },
});

const Select = SelectPrimitive.Root;

type SelectProps<
  Value = unknown,
  Multiple extends boolean | undefined = boolean | undefined,
> = SelectPrimitive.Root.Props<Value, Multiple>;

type SelectGroupProps = Omit<SelectPrimitive.Group.Props, 'style'> & {
  className?: string;
  style?: StyleXStyles;
};

const SelectGroup = ({ className, style, ...props }: SelectGroupProps) => (
  <SelectPrimitive.Group
    data-slot="select-group"
    {...stylexProps(styles.group, customClassName(className), style)}
    {...props}
  />
);

type SelectValueProps = Omit<SelectPrimitive.Value.Props, 'style'> & {
  className?: string;
  style?: StyleXStyles;
};

const SelectValue = ({ className, style, ...props }: SelectValueProps) => (
  <SelectPrimitive.Value
    data-slot="select-value"
    {...stylexProps(styles.value, customClassName(className), style)}
    {...props}
  />
);

type SelectTriggerProps = Omit<SelectPrimitive.Trigger.Props, 'style'> & {
  className?: string;
  size?: 'sm' | 'default';
  style?: StyleXStyles;
};

const SelectTrigger = ({
  children,
  className,
  size = 'default',
  style,
  ...props
}: SelectTriggerProps) => {
  // Same check as Input: every aria-invalid value except false ("grammar",
  // "spelling") marks the trigger invalid.
  const isInvalid = Boolean(props['aria-invalid']) && props['aria-invalid'] !== 'false';

  return (
    <SelectPrimitive.Trigger
      data-size={size}
      data-slot="select-trigger"
      {...stylexProps(
        styles.trigger,
        size === 'sm' ? styles.triggerSm : styles.triggerDefault,
        isInvalid && styles.triggerAriaInvalid,
        customClassName(className),
        style,
      )}
      {...props}
    >
      {children}
      <SelectPrimitive.Icon render={<ChevronDownIcon {...stylexProps(styles.triggerIcon)} />} />
    </SelectPrimitive.Trigger>
  );
};

type SelectScrollUpButtonProps = Omit<
  ComponentProps<typeof SelectPrimitive.ScrollUpArrow>,
  'style'
> & {
  className?: string;
  style?: StyleXStyles;
};

const SelectScrollUpButton = ({ className, style, ...props }: SelectScrollUpButtonProps) => (
  <SelectPrimitive.ScrollUpArrow
    data-slot="select-scroll-up-button"
    {...stylexProps(styles.scrollButton, styles.scrollButtonUp, customClassName(className), style)}
    {...props}
  >
    <ChevronUpIcon {...stylexProps(styles.icon)} />
  </SelectPrimitive.ScrollUpArrow>
);

type SelectScrollDownButtonProps = Omit<
  ComponentProps<typeof SelectPrimitive.ScrollDownArrow>,
  'style'
> & {
  className?: string;
  style?: StyleXStyles;
};

const SelectScrollDownButton = ({ className, style, ...props }: SelectScrollDownButtonProps) => (
  <SelectPrimitive.ScrollDownArrow
    data-slot="select-scroll-down-button"
    {...stylexProps(
      styles.scrollButton,
      styles.scrollButtonDown,
      customClassName(className),
      style,
    )}
    {...props}
  >
    <ChevronDownIcon {...stylexProps(styles.icon)} />
  </SelectPrimitive.ScrollDownArrow>
);

type SelectContentProps = Omit<SelectPrimitive.Popup.Props, 'style'> &
  Pick<
    SelectPrimitive.Positioner.Props,
    'align' | 'alignOffset' | 'side' | 'sideOffset' | 'alignItemWithTrigger'
  > & {
    className?: string;
    style?: StyleXStyles;
  };

const SelectContent = ({
  align = 'center',
  alignItemWithTrigger = true,
  alignOffset = 0,
  children,
  className,
  side = 'bottom',
  sideOffset = 4,
  style,
  ...props
}: SelectContentProps) => (
  <SelectPrimitive.Portal>
    <SelectPrimitive.Positioner
      align={align}
      alignItemWithTrigger={alignItemWithTrigger}
      alignOffset={alignOffset}
      side={side}
      sideOffset={sideOffset}
      {...stylexProps(styles.positioner)}
    >
      <SelectPrimitive.Popup
        className={(state) =>
          stylexProps(
            styles.content,
            !alignItemWithTrigger && isHidden(state.transitionStatus) && styles.contentHidden,
            customClassName(className),
            style,
          ).className
        }
        data-align-trigger={alignItemWithTrigger}
        data-slot="select-content"
        {...props}
      >
        <SelectScrollUpButton />
        <SelectPrimitive.List {...stylexProps(styles.list)}>{children}</SelectPrimitive.List>
        <SelectScrollDownButton />
      </SelectPrimitive.Popup>
    </SelectPrimitive.Positioner>
  </SelectPrimitive.Portal>
);

type SelectLabelProps = Omit<SelectPrimitive.GroupLabel.Props, 'style'> & {
  className?: string;
  style?: StyleXStyles;
};

const SelectLabel = ({ className, style, ...props }: SelectLabelProps) => (
  <SelectPrimitive.GroupLabel
    data-slot="select-label"
    {...stylexProps(styles.label, customClassName(className), style)}
    {...props}
  />
);

type SelectItemProps = Omit<SelectPrimitive.Item.Props, 'style'> & {
  className?: string;
  style?: StyleXStyles;
};

const SelectItem = ({ children, className, style, ...props }: SelectItemProps) => (
  <SelectPrimitive.Item
    className={(state) =>
      stylexProps(
        styles.item,
        state.highlighted && styles.itemHighlighted,
        state.disabled && styles.itemDisabled,
        customClassName(className),
        style,
      ).className
    }
    data-slot="select-item"
    {...props}
  >
    <SelectPrimitive.ItemText {...stylexProps(styles.itemText)}>
      {children}
    </SelectPrimitive.ItemText>
    <SelectPrimitive.ItemIndicator
      render={
        <span {...stylexProps(styles.itemIndicator)}>
          <CheckIcon {...stylexProps(styles.icon)} />
        </span>
      }
    />
  </SelectPrimitive.Item>
);

type SelectSeparatorProps = Omit<SelectPrimitive.Separator.Props, 'style'> & {
  className?: string;
  style?: StyleXStyles;
};

const SelectSeparator = ({ className, style, ...props }: SelectSeparatorProps) => (
  <SelectPrimitive.Separator
    data-slot="select-separator"
    {...stylexProps(styles.separator, customClassName(className), style)}
    {...props}
  />
);

export {
  Select,
  SelectContent,
  SelectGroup,
  SelectItem,
  SelectLabel,
  SelectScrollDownButton,
  SelectScrollUpButton,
  SelectSeparator,
  SelectTrigger,
  SelectValue,
  styles as selectStyles,
};

export type {
  SelectContentProps,
  SelectGroupProps,
  SelectItemProps,
  SelectLabelProps,
  SelectProps,
  SelectScrollDownButtonProps,
  SelectScrollUpButtonProps,
  SelectSeparatorProps,
  SelectTriggerProps,
  SelectValueProps,
};
