import { describe, expect, it } from 'vitest';
import {
  closeSendToMac,
  isMacDevice,
  openSendToMac,
  SEND_LINK,
  sendToMacOpener,
  subscribeSendToMac,
} from './send-to-mac.ts';

const MAC = [
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15',
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36',
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:143.0) Gecko/20100101 Firefox/143.0',
];
/** Safari on an iPad asks for the desktop site, with the user agent of a Mac. */
const IPAD_DESKTOP = MAC[0] ?? '';
const NOT_A_MAC = [
  'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1',
  'Mozilla/5.0 (iPad; CPU OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1',
  'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Mobile Safari/537.36',
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36',
  'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36',
  '',
];

describe('send to Mac', () => {
  it('takes a Mac for a Mac, with no touch screen or with one touch', () => {
    for (const userAgent of MAC) {
      expect(isMacDevice(userAgent, 0), userAgent).toBe(true);
      expect(isMacDevice(userAgent, 1), userAgent).toBe(true);
    }
  });

  it('does not take an iPad with the user agent of a Mac for a Mac', () => {
    expect(isMacDevice(IPAD_DESKTOP, 5)).toBe(false);
    expect(isMacDevice(IPAD_DESKTOP, 2)).toBe(false);
  });

  it('does not take a phone, a tablet, Windows, Linux or no user agent for a Mac', () => {
    for (const userAgent of NOT_A_MAC) {
      expect(isMacDevice(userAgent, 0), userAgent).toBe(false);
      expect(isMacDevice(userAgent, 5), userAgent).toBe(false);
    }
  });

  it('sends on the home page, tagged as shared from the popup', () => {
    expect(SEND_LINK).toBe(
      'https://caffeinagent.com/?utm_source=share&utm_medium=phone_popup&utm_campaign=download',
    );
  });

  it('opens with its button, closes, and tells who listens each time', () => {
    let told = 0;
    const stop = subscribeSendToMac(() => told++);
    const button = { focus() {}, isConnected: true };
    expect(sendToMacOpener()).toBeNull();
    openSendToMac(button);
    expect(sendToMacOpener()).toBe(button);
    closeSendToMac();
    expect(sendToMacOpener()).toBeNull();
    expect(told).toBe(2);
    stop();
    openSendToMac(button);
    closeSendToMac();
    expect(told).toBe(2);
  });
});
