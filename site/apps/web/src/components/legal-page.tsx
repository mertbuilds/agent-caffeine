import { props } from '@stylexjs/stylex';
import type { ReactNode } from 'react';
import { formatDate } from '../lib/blog.ts';
import { m } from '../paraglide/messages.js';
import { Footer } from './footer.tsx';
import { page } from './page.ts';

/** Privacy and terms: the title, the day they last changed, the text and the footer. */
export function LegalPage({
  children,
  title,
  updated,
}: {
  children: ReactNode;
  title: string;
  updated: string;
}) {
  return (
    <main id="main" {...props(page.main)}>
      <article {...props(page.column, page.grow)}>
        <header {...props(page.header)}>
          <h1 {...props(page.title)}>{title}</h1>
          <p {...props(page.meta)}>
            {m.legal_updated()} <time dateTime={updated}>{formatDate(updated)}</time>
          </p>
        </header>
        <div className="article">
          <div>{children}</div>
        </div>
      </article>
      <Footer />
    </main>
  );
}
