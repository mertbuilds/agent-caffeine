export const THEME_CHOICES = ['system', 'light', 'dark'] as const;

export type ThemeChoice = (typeof THEME_CHOICES)[number];

/** Where a chosen light or dark is kept. The system's is kept as no entry. */
const THEME_KEY = 'theme';

/** Runs in the head before the first paint, so a kept theme is never preceded by the other. */
export const THEME_SCRIPT = `try{var t=localStorage.getItem('${THEME_KEY}');if(t==='light'||t==='dark')document.documentElement.setAttribute('data-theme',t)}catch(e){}`;

const listeners = new Set<() => void>();

export function subscribeTheme(listener: () => void): () => void {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}

/** The theme on `<html>`, where the head's script put the kept one. */
export function readTheme(): ThemeChoice {
  const theme = document.documentElement.dataset['theme'];
  return theme === 'light' || theme === 'dark' ? theme : 'system';
}

export function serverTheme(): ThemeChoice {
  return 'system';
}

export function applyTheme(choice: ThemeChoice): void {
  const root = document.documentElement;
  try {
    if (choice === 'system') {
      localStorage.removeItem(THEME_KEY);
    } else {
      localStorage.setItem(THEME_KEY, choice);
    }
  } catch {
    // Storage is off: the choice lasts until the page is left.
  }
  if (choice === 'system') {
    delete root.dataset['theme'];
  } else {
    root.dataset['theme'] = choice;
  }
  for (const listener of listeners) {
    listener();
  }
}
