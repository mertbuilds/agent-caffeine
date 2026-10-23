import { useEffect, useState, type RefObject } from 'react';

/**
 * Whether the element in `ref` is in view, for motion that plays as it comes
 * on screen. It turns on once `amount` of the element is in the window, and
 * off only once the element has left the window altogether, so nothing stops
 * or starts over while it is still in sight.
 */
export function useSeen(ref: RefObject<Element | null>, amount = 0.5): boolean {
  const [seen, setSeen] = useState(false);

  useEffect(() => {
    const element = ref.current;
    if (element === null) {
      return;
    }
    const entering = new IntersectionObserver(
      (entries) => {
        if (entries.some((entry) => entry.isIntersecting && entry.intersectionRatio >= amount)) {
          setSeen(true);
        }
      },
      { threshold: amount },
    );
    const leaving = new IntersectionObserver((entries) => {
      if (entries.at(-1)?.isIntersecting === false) {
        setSeen(false);
      }
    });
    entering.observe(element);
    leaving.observe(element);
    return () => {
      entering.disconnect();
      leaving.disconnect();
    };
  }, [amount, ref]);

  return seen;
}
