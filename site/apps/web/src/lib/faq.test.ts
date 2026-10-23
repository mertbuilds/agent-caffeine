import { describe, expect, it } from 'vitest';
import { answerText, faqItems, faqPage } from './faq.tsx';

describe('faq', () => {
  it('gives every question its own id for the count, and an answer in plain text', () => {
    const items = faqItems();
    expect(new Set(items.map((item) => item.id)).size).toBe(items.length);
    for (const item of items) {
      expect(item.id).toMatch(/^[a-z]+$/);
      expect(answerText(item.answer).trim().length).toBeGreaterThan(0);
    }
  });

  it('reads the words of a link into the plain text of its answer', () => {
    const detection = faqPage().mainEntity.find((entry) =>
      entry.acceptedAnswer.text.startsWith('Claude Code'),
    );
    expect(detection?.acceptedAnswer.text).toMatch(/It knows more than \d+ agents\.$/);
  });
});
