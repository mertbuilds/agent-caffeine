"use client";

import dynamic from "next/dynamic";
import { useSyncExternalStore } from "react";

const OpenPanelComponent = dynamic(
  () => import("@openpanel/nextjs").then((m) => m.OpenPanelComponent),
  { ssr: false }
);

/** The hosts the live site is served on. A preview or a local run never sends an event. */
const LIVE_HOSTS = ["caffeinagent.com", "www.caffeinagent.com"];

const subscribe = () => () => {};

function onLiveHost(): boolean {
  return LIVE_HOSTS.includes(window.location.hostname);
}

function onServer(): boolean {
  return false;
}

export function Analytics() {
  const clientId = process.env.NEXT_PUBLIC_OPENPANEL_CLIENT_ID;
  const live = useSyncExternalStore(subscribe, onLiveHost, onServer);
  if (!clientId || !live) return null;
  return (
    <OpenPanelComponent
      clientId={clientId}
      apiUrl="/api/op"
      scriptUrl="/api/op/op1.js"
      trackScreenViews={true}
      trackOutgoingLinks={false}
      trackAttributes={false}
    />
  );
}
