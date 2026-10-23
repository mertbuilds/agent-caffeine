import { props, type StyleXStyles } from '@stylexjs/stylex';

/**
 * props() for an element that also takes class names of styles/scenes.css, which StyleX does not
 * know. A falsy name is left out.
 */
export function sceneProps(
  names: ReadonlyArray<string | false | null | undefined>,
  ...styles: ReadonlyArray<StyleXStyles>
): ReturnType<typeof props> {
  const own = props(...styles);
  const className = [...names, own.className].filter(Boolean).join(' ');
  return { ...own, className };
}
