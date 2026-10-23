import { isValidElement, type ReactNode } from 'react';
import { m } from '../paraglide/messages.js';
import { dollars, FULL_PRICE, LAUNCH_PRICE_ACTIVE, MACS, PORTAL_URL, PRICE } from './pricing.ts';

/** `SafetyMonitor.defaultBatteryFloorPercent`: on battery the app stops at this level. */
const BATTERY_FLOOR = 20;

/** The largest round ten below the number of agents the app knows, for copy that says "more than". */
const AGENTS_MORE_THAN = 40;

/** `id` names the question where it is counted, and stays when the list is put in another order. `open` is for an answer the page shows from the start. */
type FaqItem = { answer: ReactNode; id: string; open?: boolean; question: string };

/** Short answers, the direct one first. The first three are what a reader asks before a download, and they are open from the start. */
export function faqItems(): ReadonlyArray<FaqItem> {
  return [
    {
      answer: m.faq_caffeinate_answer(),
      id: 'caffeinate',
      open: true,
      question: m.faq_caffeinate_question(),
    },
    {
      answer: m.faq_battery_answer({ floor: BATTERY_FLOOR }),
      id: 'battery',
      open: true,
      question: m.faq_battery_question(),
    },
    { answer: m.faq_admin_answer(), id: 'admin', open: true, question: m.faq_admin_question() },
    {
      answer: (
        <>
          {m.faq_detection_answer()}
          <a href="#agents">{m.faq_detection_link({ count: AGENTS_MORE_THAN })}</a>
          {m.faq_detection_after()}
        </>
      ),
      id: 'detection',
      question: m.faq_detection_question(),
    },
    { answer: m.faq_waiting_answer(), id: 'waiting', question: m.faq_waiting_question() },
    { answer: m.faq_phone_answer(), id: 'phone', question: m.faq_phone_question() },
    { answer: m.faq_script_answer(), id: 'script', question: m.faq_script_question() },
    { answer: m.faq_mcp_answer(), id: 'mcp', question: m.faq_mcp_question() },
    {
      answer: (
        <>
          {m.faq_privacy_answer()}
          <a href="/privacy">{m.faq_privacy_link()}</a>
          {m.faq_privacy_after()}
        </>
      ),
      id: 'privacy',
      question: m.faq_privacy_question(),
    },
    {
      answer: (
        <>
          {LAUNCH_PRICE_ACTIVE
            ? m.faq_price_launch({ full: dollars(FULL_PRICE), price: PRICE })
            : m.faq_price_once({ price: PRICE })}
          {m.faq_price_answer({ macs: MACS })}
        </>
      ),
      id: 'price',
      question: m.faq_price_question(),
    },
    { answer: m.faq_updates_answer(), id: 'updates', question: m.faq_updates_question() },
    {
      answer: (
        <>
          {m.faq_key_answer()}
          <a href={PORTAL_URL}>{m.faq_key_link()}</a>
          {m.faq_key_after()}
        </>
      ),
      id: 'key',
      question: m.faq_key_question(),
    },
    { answer: m.faq_refund_answer(), id: 'refund', question: m.faq_refund_question() },
  ];
}

/** The plain text of an answer, so the structured data says exactly what the page shows. */
export function answerText(node: ReactNode): string {
  if (typeof node === 'string' || typeof node === 'number') {
    return String(node);
  }
  if (Array.isArray(node)) {
    return node.map(answerText).join('');
  }
  if (isValidElement<{ children?: ReactNode }>(node)) {
    return answerText(node.props.children);
  }
  return '';
}

/** The questions as schema.org FAQPage, for the home page's structured data. */
export function faqPage() {
  return {
    '@type': 'FAQPage',
    mainEntity: faqItems().map((item) => ({
      '@type': 'Question',
      acceptedAnswer: { '@type': 'Answer', text: answerText(item.answer) },
      name: item.question,
    })),
  };
}
