import { useSyncExternalStore } from "react";

function subscribe(onChange: () => void): () => void {
  document.addEventListener("visibilitychange", onChange);
  return () => document.removeEventListener("visibilitychange", onChange);
}

function tabHidden(): boolean {
  return document.visibilityState === "hidden";
}

function hiddenOnServer(): boolean {
  return false;
}

/** Whether the tab is put away, so a drawing that loops can hold while nobody sees it. */
export function useTabHidden(): boolean {
  return useSyncExternalStore(subscribe, tabHidden, hiddenOnServer);
}
