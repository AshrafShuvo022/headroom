/**
 * Ends Android WebView's renderer process once no WebView has been open for a
 * while.
 *
 * Measured: after the first WebView of a session (a social embed, the
 * YouTube player), Android WebView keeps its renderer process alive for the
 * rest of the session, 110-125 MB, with no WebView open and even after
 * TRIM_MEMORY_COMPLETE. Once your own content renders natively, most of a session has no
 * WebView open, so that renderer is pure dead weight.
 *
 * Every component that mounts a WebView calls useWebViewLease() next to it.
 * When the count of open WebViews drops to zero and stays there for
 * RENDERER_IDLE_MS, the native module (modules/webview-renderer) ends the
 * renderer; the next WebView starts a fresh one. The wait keeps a reader
 * scrolling from one embed to the next from restarting it each time.
 *
 * Android only. iOS already gives each WebView its own WebContent process,
 * which ends when the WebView does.
 */
import { useEffect } from 'react';
import { Platform } from 'react-native';
import { requireOptionalNativeModule } from 'expo-modules-core';

type WebViewRendererModule = { terminateIdleRenderer(): Promise<string> };

const native =
  Platform.OS === 'android' ? requireOptionalNativeModule<WebViewRendererModule>('WebViewRenderer') : null;

/** How long no WebView must be open before the renderer is ended. */
export const RENDERER_IDLE_MS = 10_000;

let open = 0;
let timer: ReturnType<typeof setTimeout> | null = null;

function opened() {
  open += 1;
  if (timer) {
    clearTimeout(timer);
    timer = null;
  }
}

function closed() {
  open = Math.max(0, open - 1);
  if (open > 0 || !native) return;
  if (timer) clearTimeout(timer);
  timer = setTimeout(() => {
    timer = null;
    if (open > 0) return;
    native
      .terminateIdleRenderer()
      .then((result) => {
        // Optional: record `result` as a breadcrumb in your error reporter.
        void result;
      })
      .catch(() => {});
  }, RENDERER_IDLE_MS);
}

/** Call in a component for as long as it has a WebView mounted. */
export function useWebViewLease() {
  useEffect(() => {
    opened();
    return closed;
  }, []);
}

/** For a branch that mounts a WebView: render <WebViewLease /> next to it. */
export function WebViewLease() {
  useWebViewLease();
  return null;
}
