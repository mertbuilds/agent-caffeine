"use client";

import dynamic from "next/dynamic";

const OpenPanelComponent = dynamic(
  () => import("@openpanel/nextjs").then((m) => m.OpenPanelComponent),
  { ssr: false }
);

export function Analytics() {
  const clientId = process.env.NEXT_PUBLIC_OPENPANEL_CLIENT_ID;
  if (!clientId) return null;
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
