"use client";

import dynamic from "next/dynamic";
import { useEffect, useSyncExternalStore } from "react";
import { onLiveHost, rememberUtm } from "@/lib/track";

const OpenPanelComponent = dynamic(
  () => import("@openpanel/nextjs").then((m) => m.OpenPanelComponent),
  { ssr: false }
);

/** The share of sessions that are recorded. The owner wants every session during launch; lower it after. */
const REPLAY_SAMPLE_RATE = 1;
/** How often the recorder sends what it has, in milliseconds. */
const REPLAY_FLUSH_INTERVAL_MS = 10_000;

const subscribe = () => () => {};

function onServer(): boolean {
  return false;
}

export function Analytics() {
  const clientId = process.env.NEXT_PUBLIC_OPENPANEL_CLIENT_ID;
  const live = useSyncExternalStore(subscribe, onLiveHost, onServer);
  useEffect(rememberUtm, []);
  if (!clientId || !live) return null;
  return (
    <OpenPanelComponent
      clientId={clientId}
      apiUrl="/api/op"
      scriptUrl="/api/op/op1.js"
      trackScreenViews={true}
      trackOutgoingLinks={false}
      trackAttributes={false}
      // The recorder is a second script, fetched only after the first one runs. Page text is the same for every reader, so it is not masked.
      sessionReplay={{
        enabled: true,
        sampleRate: REPLAY_SAMPLE_RATE,
        flushIntervalMs: REPLAY_FLUSH_INTERVAL_MS,
        maskAllInputs: true,
        maskAllText: false,
        scriptUrl: "/api/op/op1-replay.js",
      }}
    />
  );
}
