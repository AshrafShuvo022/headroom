package expo.modules.webviewrenderer

import android.os.Build
import android.webkit.WebView
import expo.modules.kotlin.functions.Queues
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition

/**
 * Ends Android WebView's renderer process once no WebView is open.
 *
 * Android WebView draws web content in a separate "renderer" process. Chrome
 * starts it with the first WebView and keeps it after the last one closes:
 * measured at 110-125 MB, alive for the rest of the session,
 * even after TRIM_MEMORY_COMPLETE. Once your own content renders natively, the only
 * WebViews left are embeds and third-party players, so most of the session has
 * none open while the renderer still sits there.
 *
 * The JS side (`src/services/webviewRenderer.ts`) counts open WebViews and
 * calls this once the count has been zero for a while. Android 10+ (API 29)
 * exposes the renderer only through a WebView, so a throwaway WebView asks
 * for it, ends it, and is destroyed. The next WebView starts a fresh renderer.
 * A WebView still holding the old renderer (one React has removed but Android
 * has not destroyed, a known Android behaviour) gets onRenderProcessGone, which
 * react-native-webview handles without crashing.
 *
 * Returns what happened, for a breadcrumb: "terminated", "refused" (Chrome
 * said no), "no-renderer" (none running, or WebView is single-process),
 * "unsupported" (below Android 10), "no-context".
 */
class WebViewRendererModule : Module() {
  override fun definition() = ModuleDefinition {
    Name("WebViewRenderer")

    AsyncFunction("terminateIdleRenderer") {
      if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return@AsyncFunction "unsupported"
      val context = appContext.currentActivity ?: appContext.reactContext
        ?: return@AsyncFunction "no-context"
      val probe = WebView(context)
      try {
        val process = probe.webViewRenderProcess ?: return@AsyncFunction "no-renderer"
        if (process.terminate()) "terminated" else "refused"
      } finally {
        probe.destroy()
      }
    }.runOnQueue(Queues.MAIN)
  }
}
