import { blur, duration, easing } from "@/lib/motion";
import { lessMotion } from "@/lib/use-less-motion";

/**
 * One layout gathering into another: the header's open strip into its pill
 * and back. `update` changes the layout at once; the items marked
 * `data-morph` inside `root` then move from where they stood to where they
 * now stand, and `surface`, the ground drawn behind them, grows or shrinks
 * from its old box to its new one.
 *
 * Gathering takes `verySlow`, the items setting off a `stagger` apart in the
 * order they stand. Opening back out is quicker, at `slow`, and all at once.
 * An item with no place on the other side fades and blurs out at `quick` as
 * the motion starts, or in as it ends.
 *
 * Where the browser has view transitions, the items are carried by one; each
 * `data-morph` is also its `view-transition-name`. Elsewhere they are moved
 * by hand, and an item that is gone leaves a copy where it stood to fade.
 * The surface stays live in both cases, so the page blurs through it the
 * whole way. With less motion, the layout only changes.
 *
 * An item that changes shape (`live`) is moved and resized by hand, its
 * corners going from the old radius to the new one, so it is one shape the
 * whole way rather than a square fading into a circle.
 *
 * A view transition also eases each of its own keyframes. Opening back out,
 * that transition gets a type and `globals.css` takes the second ease off,
 * so the items keep to the surface growing under them.
 */
type Timing = { delay?: number; duration: number; easing: string; fill?: FillMode };

const QUICK = duration.quick * 1000;
const STAGGER = duration.stagger * 1000;
const SMOOTH_OUT = `cubic-bezier(${easing.smoothOut.join(", ")})`;
const WORD_GONE = { filter: `blur(${blur.small}px)`, opacity: 0 };
const WORD_HERE = { filter: "blur(0)", opacity: 1 };
/** The type of a view transition that opens the items back out. */
const SPREADING = "morph-spreading";

type Box = { opacity: string; radius: string; rect: DOMRect };
type Shape = { radius: string; rect: DOMRect };
type Item = { copy: HTMLElement; parent: HTMLElement | null; rect: DOMRect };
type Pace = { ahead: boolean; length: number; stagger: number };

const GATHER: Pace = { ahead: true, length: duration.verySlow * 1000, stagger: STAGGER };
const SPREAD: Pace = { ahead: false, length: duration.slow * 1000, stagger: 0 };

function travel(pace: Pace, index: number): Timing {
  return { delay: index * pace.stagger, duration: pace.length, easing: SMOOTH_OUT, fill: "backwards" };
}

function leave(): Timing {
  return { duration: QUICK, easing: "ease-in-out", fill: "forwards" };
}

function arrive(pace: Pace): Timing {
  return { delay: pace.length - QUICK, duration: QUICK, easing: "ease-in-out", fill: "backwards" };
}

/** Where `element` is drawn now, motion included, and its running motion stopped. */
function settle(element: HTMLElement): DOMRect {
  const rect = element.getBoundingClientRect();
  for (const animation of element.getAnimations()) {
    animation.cancel();
  }
  return rect;
}

function surfaceBox(surface: HTMLElement): Box {
  const style = getComputedStyle(surface);
  const box = { opacity: style.opacity, radius: style.borderRadius, rect: surface.getBoundingClientRect() };
  settle(surface);
  return box;
}

function growSurface(surface: HTMLElement, from: Box, pace: Pace) {
  const to = surface.getBoundingClientRect();
  const style = getComputedStyle(surface);
  surface.animate(
    [
      {
        borderRadius: from.radius,
        bottom: `${to.bottom - from.rect.bottom}px`,
        left: `${from.rect.left - to.left}px`,
        opacity: from.opacity,
        right: `${to.right - from.rect.right}px`,
        top: `${from.rect.top - to.top}px`,
      },
      { borderRadius: style.borderRadius, bottom: "0px", left: "0px", opacity: style.opacity, right: "0px", top: "0px" },
    ],
    travel(pace, 0),
  );
}

function shapeOf(element: HTMLElement): Shape {
  const { borderRadius } = getComputedStyle(element);
  return { radius: borderRadius, rect: settle(element) };
}

/**
 * A live item from its old box and corners to the ones the layout gives it
 * now. `ahead` keeps the pace of view transition pictures that run under the
 * browser's own ease.
 */
function reshape(element: HTMLElement, from: Shape, pace: Pace, ahead: boolean) {
  const to = element.getBoundingClientRect();
  if (to.width === 0 || to.height === 0) {
    return;
  }
  element.animate(
    [
      {
        borderRadius: from.radius,
        easing: ahead ? "ease" : "linear",
        transform: `translate(${from.rect.left - to.left}px, ${from.rect.top - to.top}px) scale(${from.rect.width / to.width}, ${from.rect.height / to.height})`,
        transformOrigin: "0 0",
      },
      { borderRadius: getComputedStyle(element).borderRadius, transform: "none", transformOrigin: "0 0" },
    ],
    travel(pace, 0),
  );
}

/** The marked items in the order they stand, by name. */
function marked(root: HTMLElement): Map<string, HTMLElement> {
  const items = new Map<string, HTMLElement>();
  for (const element of root.querySelectorAll<HTMLElement>("[data-morph]")) {
    const name = element.dataset.morph;
    if (name !== undefined && element.getBoundingClientRect().width > 0) {
      items.set(name, element);
    }
  }
  return items;
}

/** The copy of `item` where it stood, fading out of focus, then gone. */
function fadeOut(item: Item) {
  const ghost = item.copy;
  ghost.removeAttribute("data-morph");
  ghost.setAttribute("aria-hidden", "true");
  ghost.inert = true;
  Object.assign(ghost.style, {
    boxSizing: "border-box",
    height: `${item.rect.height}px`,
    left: `${item.rect.left}px`,
    margin: "0",
    pointerEvents: "none",
    position: "fixed",
    top: `${item.rect.top}px`,
    width: `${item.rect.width}px`,
  });
  (item.parent?.isConnected ? item.parent : document.body).append(ghost);
  const fade = ghost.animate([WORD_HERE, WORD_GONE], leave());
  void fade.finished.finally(() => ghost.remove()).catch(() => {});
}

/** The marked items from their old boxes to their new ones, by hand. */
function slide(root: HTMLElement, before: Map<string, Item>, order: Array<string>, pace: Pace) {
  for (const [name, element] of marked(root)) {
    const old = before.get(name);
    before.delete(name);
    if (old === undefined) {
      element.animate([WORD_GONE, WORD_HERE], arrive(pace));
      continue;
    }
    const rect = element.getBoundingClientRect();
    element.animate(
      [
        {
          transform: `translate(${old.rect.left - rect.left}px, ${old.rect.top - rect.top}px) scale(${old.rect.width / rect.width}, ${old.rect.height / rect.height})`,
          transformOrigin: "0 0",
        },
        { transform: "none", transformOrigin: "0 0" },
      ],
      travel(pace, order.indexOf(name)),
    );
  }
  for (const old of before.values()) {
    fadeOut(old);
  }
}

/** A view transition that takes types, which TypeScript's DOM types do not know yet. */
function isTyped(transition: object): transition is { types: { add: (type: string) => void } } {
  return (
    "types" in transition &&
    typeof transition.types === "object" &&
    transition.types !== null &&
    "add" in transition.types &&
    typeof transition.types.add === "function"
  );
}

function isKeyframeEffect(effect: AnimationEffect | null): effect is KeyframeEffect {
  return effect !== null && "pseudoElement" in effect;
}

/** The view transition's own motion, set to the page's pace. */
function retime(order: Array<string>, pace: Pace) {
  const pictures = document.getAnimations().flatMap(({ effect }) => {
    if (!isKeyframeEffect(effect)) {
      return [];
    }
    const match = /^::view-transition-(group|old|new)\((.+)\)$/.exec(effect.pseudoElement ?? "");
    return match?.[1] === undefined || match[2] === undefined ? [] : [{ effect, name: match[2], side: match[1] }];
  });
  const sides = new Set(pictures.map(({ name, side }) => `${side} ${name}`));
  for (const { effect, name, side } of pictures) {
    if (side === "old" && !sides.has(`new ${name}`)) {
      effect.setKeyframes([WORD_HERE, WORD_GONE]);
      effect.updateTiming(leave());
    } else if (side === "new" && !sides.has(`old ${name}`)) {
      effect.setKeyframes([WORD_GONE, WORD_HERE]);
      effect.updateTiming(arrive(pace));
    } else {
      const timing = travel(pace, order.indexOf(name));
      effect.updateTiming(pace.ahead ? timing : { ...timing, fill: "both" });
    }
  }
}

/**
 * Changes the layout with `update` and moves the items from the old one to
 * the new one: gathering when `gather` is true, spreading back out when not.
 */
export function morph({
  gather,
  live = [],
  root,
  surface,
  update,
}: {
  gather: boolean;
  live?: ReadonlyArray<HTMLElement>;
  root: HTMLElement;
  surface: HTMLElement;
  update: () => void;
}) {
  if (lessMotion()) {
    update();
    return;
  }
  const pace = gather ? GATHER : SPREAD;
  const from = surfaceBox(surface);
  const shapes = live.map((element) => ({ element, from: shapeOf(element) }));
  const reshapeLive = (ahead: boolean) => {
    for (const shape of shapes) {
      reshape(shape.element, shape.from, pace, ahead);
    }
  };
  const standing = marked(root);
  const orderAfter = () => [...new Set([...standing.keys(), ...marked(root).keys()])];

  if (typeof document.startViewTransition === "function") {
    const transition = document.startViewTransition(update);
    if (!pace.ahead && isTyped(transition)) {
      transition.types.add(SPREADING);
    }
    // `ready` rejects when a newer transition cuts this one short.
    transition.ready.then(() => retime(orderAfter(), pace)).catch(() => {});
    transition.updateCallbackDone
      .then(() => {
        growSurface(surface, from, pace);
        reshapeLive(pace.ahead);
      })
      .catch(() => {});
    return;
  }

  const before = new Map<string, Item>();
  for (const [name, element] of standing) {
    before.set(name, { copy: document.importNode(element, true), parent: element.parentElement, rect: settle(element) });
  }
  update();
  const order = orderAfter();
  slide(root, before, order, pace);
  growSurface(surface, from, pace);
  reshapeLive(false);
}
