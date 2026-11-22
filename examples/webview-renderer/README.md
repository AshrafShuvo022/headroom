# Ending Android's idle WebView renderer

Android WebView (Chrome) runs page content in a separate renderer process. It starts with your
first WebView and **stays alive after the last one closes**, through `TRIM_MEMORY_COMPLETE`, for
the rest of the session: 110–125 MB beside your app, invisible in your app's own number.

This example ends it once no WebView has been open for 10 seconds. The next WebView starts a
fresh renderer in about half a second. Measured: memory held at rest, renderer counted,
396 → 282 MB; embeds and players unaffected.

- `WebViewRendererModule.kt`: a local Expo module (Android 10+). Put it in
  `modules/webview-renderer/android/src/main/java/expo/modules/webviewrenderer/` with the usual
  `expo-module.config.json`, `build.gradle` and `package.json` of a local module. Needs a native
  build; an OTA update cannot carry it.
- `webviewRenderer.ts`: the JS side. Counts open WebViews; render `<WebViewLease />` next to
  every `<WebView>` (and inside any component that wraps one, such as a YouTube player).

react-native-webview ≥ 13 handles `onRenderProcessGone`, so a WebView that is still around
(for example one that Android never destroyed inside a hidden tab) survives the renderer ending.
