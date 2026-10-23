import { richParts } from '../lib/rich.ts';

/** Renders a message with its `code` and [text](href) marks: `<Rich text={m.privacy_contact(...)} />`. */
export function Rich({ text }: { text: string }) {
  return (
    <>
      {richParts(text).map((part, index) => {
        if (part.kind === 'code') {
          // oxlint-disable-next-line react/no-array-index-key -- the parts of one message never move
          return <code key={index}>{part.text}</code>;
        }
        if (part.kind === 'link') {
          return (
            <a
              href={part.href}
              // oxlint-disable-next-line react/no-array-index-key -- the parts of one message never move
              key={index}
              {...(part.href.startsWith('https://') ? { rel: 'noreferrer' } : {})}
            >
              {part.text}
            </a>
          );
        }
        return part.text;
      })}
    </>
  );
}
