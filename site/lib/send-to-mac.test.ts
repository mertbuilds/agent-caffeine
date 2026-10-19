import assert from "node:assert/strict";
import { test } from "node:test";
import { SEND_LINK, closeSendToMac, isMacDevice, openSendToMac, sendToMacOpener, subscribeSendToMac } from "./send-to-mac";

const MAC = [
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36",
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:143.0) Gecko/20100101 Firefox/143.0",
];
/** Safari on an iPad asks for the desktop site, with the user agent of a Mac. */
const IPAD_DESKTOP = MAC[0];
const NOT_A_MAC = [
  "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
  "Mozilla/5.0 (iPad; CPU OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
  "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Mobile Safari/537.36",
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36",
  "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36",
  "",
];

test("a Mac is a Mac, with no touch screen or with one touch", () => {
  for (const userAgent of MAC) {
    assert.equal(isMacDevice(userAgent, 0), true, userAgent);
    assert.equal(isMacDevice(userAgent, 1), true, userAgent);
  }
});

test("an iPad with the user agent of a Mac is not a Mac", () => {
  assert.equal(isMacDevice(IPAD_DESKTOP, 5), false);
  assert.equal(isMacDevice(IPAD_DESKTOP, 2), false);
});

test("a phone, a tablet, Windows, Linux and no user agent are not a Mac", () => {
  for (const userAgent of NOT_A_MAC) {
    assert.equal(isMacDevice(userAgent, 0), false, userAgent);
    assert.equal(isMacDevice(userAgent, 5), false, userAgent);
  }
});

test("the link to send on is the home page, tagged as shared from the popup", () => {
  assert.equal(SEND_LINK, "https://caffeinagent.com/?utm_source=share&utm_medium=phone_popup&utm_campaign=download");
});

test("the popup opens with its button, closes, and tells who listens each time", () => {
  let told = 0;
  const stop = subscribeSendToMac(() => told++);
  const button = { isConnected: true, focus() {} };
  assert.equal(sendToMacOpener(), null);
  openSendToMac(button);
  assert.equal(sendToMacOpener(), button);
  closeSendToMac();
  assert.equal(sendToMacOpener(), null);
  assert.equal(told, 2);
  stop();
  openSendToMac(button);
  closeSendToMac();
  assert.equal(told, 2);
});
