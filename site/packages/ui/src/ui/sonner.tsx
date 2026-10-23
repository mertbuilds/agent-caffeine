'use client';

import type { CSSProperties } from 'react';
import { Toaster as Sonner } from 'sonner';
import type { ToasterProps } from 'sonner';

// Adapted from shadcn-cssinjs: next-themes dropped — this design system themes
// via prefers-color-scheme only, which sonner's "system" theme already follows.
const Toaster = (props: ToasterProps) => {
  return (
    <Sonner
      className="toaster group"
      data-slot="sonner"
      style={
        {
          '--normal-bg': 'var(--popover)',
          '--normal-border': 'var(--border)',
          '--normal-text': 'var(--popover-foreground)',
        } as CSSProperties
      }
      theme="system"
      {...props}
    />
  );
};

export { Toaster };
