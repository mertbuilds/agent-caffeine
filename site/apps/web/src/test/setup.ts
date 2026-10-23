import { cleanup } from '@testing-library/react';
import { afterEach } from 'vitest';
import '@testing-library/jest-dom/vitest';

// Vitest does not enable globals, so RTL's automatic cleanup never registers
// itself — without this, components from one test leak into the next.
afterEach(() => {
  cleanup();
});
