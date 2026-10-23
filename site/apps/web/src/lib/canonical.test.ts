import { describe, expect, it } from 'vitest';
import { canonicalRedirect } from './canonical.ts';

const target = (address: string): string | null =>
  canonicalRedirect(new URL(address))?.headers.get('location') ?? null;

describe('canonicalRedirect', () => {
  it('leaves the apex over https alone', () => {
    expect(canonicalRedirect(new URL('https://caffeinagent.com/privacy'))).toBeNull();
  });

  it('moves www to the apex with a 301, path and query kept', () => {
    const moved = canonicalRedirect(new URL('https://www.caffeinagent.com/privacy?x=1'));
    expect(moved?.status).toBe(301);
    expect(moved?.headers.get('location')).toBe('https://caffeinagent.com/privacy?x=1');
    expect(target('http://www.caffeinagent.com/')).toBe('https://caffeinagent.com/');
  });

  it('moves the apex over plain http to https', () => {
    expect(target('http://caffeinagent.com/mac/appcast.xml')).toBe(
      'https://caffeinagent.com/mac/appcast.xml',
    );
  });

  it('leaves local servers, previews and workers.dev alone', () => {
    for (const address of [
      'http://localhost:4173/',
      'https://c7.caffeinagent.localhost/',
      'http://caffeinagent.localhost/',
      'https://abc123-caffeinagent-web.example.workers.dev/',
      'https://caffeinagent-web.example.workers.dev/',
      'https://caffeinagent.com.evil.example/',
    ]) {
      expect(canonicalRedirect(new URL(address)), address).toBeNull();
    }
  });
});
