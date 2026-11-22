---
name: headroom
description: Build React Native / Expo apps that stay within memory. Use when adding or reviewing a screen, list, image, WebView, video or audio player, or navigation flow in a React Native app, when an app is being killed with no crash report, or before a release. Rules per situation, each with the reason and a measured number, plus a review checklist.
---

# React Native memory: the rules, by situation

Most React Native memory problems are not JavaScript leaks. They are native things (bitmaps,
WebViews, players, screens) kept **mounted** longer than needed. Hidden is not freed: a screen
under a pushed screen, a tab the user left, a row far down a ScrollView, a view at `opacity: 0`
all still hold their memory. Only leaving the tree frees it.

The pattern behind every rule: **keep the screen, unmount only the heavy child, put a same-size
placeholder in its place.**

Numbers are from one content app (feeds, articles, embeds, video) measured on RN 0.86 / Expo 57
/ iOS 27 / Android 16, taken from 574 → 365 MB (Android) and 279 → 158 MiB (iOS) with these
rules. The rules are general; re-measure the numbers on your own app (`reference.md`).

## Day one on a new project

Five things to set up before the first screen, so the rules below are the default:

1. **Cap the image memory cache** at startup: `Image.configureCache({ maxMemoryCost: 48 * 1024 * 1024 })`
   (expo-image), and prefetch with `'disk'` only.
2. **Report kills**: Sentry with watchdog-termination tracking on iOS; on Android read
   `ApplicationExitInfo` on launch and send low-memory exits.
3. **`freezeOnBlur: true` on the stack navigator's `screenOptions`** (not the tabs, not global).
4. **One `HeavyOnFocus` wrapper** (`useIsFocused` + a short delay + a same-size placeholder) and
   use it around every WebView and player from the start; plus the WebView lease from
   `examples/webview-renderer/` if you will ever show one on Android.
5. **A `FlatList` for every data-driven list**, with `onEndReached` paging and a Retry footer, as
   the project's list component; no `ScrollView` + `map`.

Then run the 10-minute session once on a release build to get your baseline (`reference.md`).

## Lists

- **If the item count depends on data, it's a `FlatList`.** A `ScrollView` builds every child
  at once and keeps them; a FlatList keeps only rows near the window. 150 items cost what 15 cost.
- **`initialNumToRender` rows are never released.** Keep it 1–3 when first rows can be heavy
  (embeds, players). 6 → 1 took a document's live WebViews from 6 to 3.
- **Mixed pages are still one FlatList**: header, sticky bar, player and the endless part as row
  kinds in `renderItem`. Never nest an endless list in a ScrollView.
- **Nothing after an endless list** (it's never reached). **Pages load on scroll**
  (`onEndReached`, ~0.5), one at a time; after a failed page show Retry instead of auto-loading.
- Android: if row images come back blank after scrolling, set `removeClippedSubviews={false}`.

## Images

- **RAM = width × height × 4**, whatever the file size. A 127 KB, 1600×1732 px image is 11 MB.
- **Request the size you draw**: sized copies from your CDN (e.g. 480/960/1500 px), chosen by
  slot width × device scale **capped at 2×** (3× looks the same, costs 2.25× the pixels).
- **Cap the memory cache once at startup**: `Image.configureCache({ maxMemoryCost })`, 32–64 MB.
  expo-image on iOS ships with the cap at 0 = unlimited, emptied only on a memory warning;
  Android's cache is bounded. The same prefetch grew iOS by ~2.6 MB per card per toggle, forever.
- **Prefetch to `'disk'`, never `'memory-disk'`.** RAM is for what's on screen now.
- **Never your own images through a WebView**: it decodes at full size and shrinks for display.

## WebViews

- **Your own HTML (articles, descriptions, help pages) does not go in a WebView.** Convert it to
  blocks and render them as FlatList rows. A document in a full-height WebView cost ~91 MiB of
  drawn surfaces in the app plus a content process of 8–214 MiB; native, 0 processes and flat
  memory. Converting in the app is milliseconds and ~1 MB per document.
- **A WebView is for other people's content** (embeds, their players, OAuth). Create it **on
  tap** behind a poster, **release it on blur** with a placeholder of its measured height
  (`useIsFocused`; `useEffect` cleanup never runs on a covered screen).
- **Every WebView takes a lease**; on Android, when none has been open for ~10 s, **end the
  renderer process** (`examples/webview-renderer/`). Chrome keeps it alive at 110–125 MB after
  the last WebView closes, through `TRIM_MEMORY_COMPLETE`. Ending it: held memory 396 → 282 MB.
- **WebView-heavy content on pushed screens, not in tabs.** A WebView unmounted inside a hidden
  tab is never destroyed natively on Android; removed by Back from a pushed screen, it is.
- **Never a full-height WebView inside a native scroll view**; let it scroll itself.
- Injected CSS: add `:not(script):not(style)` to `+ *` rules and `:not(iframe)` to attribute
  selectors, or script source shows as text and widget frames get double margins.

## Video and audio

- Third-party players (YouTube, Facebook, TikTok) **are WebViews**; all WebView rules apply.
  Your own media in a native player is far lighter.
- **Pause is not release.** Paused keeps buffers, the hardware decoder and the GPU surface.
  Decoders are few; stacked players turn the next one black.
- **Poster first, player on tap, `key` by media id, unmount on blur, one audio at a time.**
  Nothing plays while hidden, so auto-advance stops by itself.
- Playback is the session's peak (249 MiB iOS / 357 MB Android here) and drops back on leaving.

## Navigation

- **`push` keeps the screen below mounted; only Back unmounts.** Release heavy children on blur;
  cap chain depth (`replace` beyond ~5).
- **Tabs mount on first visit and stay mounted.** A left tab's player plays on.
- **Background is not blur.** Save state on `AppState`, not on blur.
- **`freezeOnBlur` saves CPU, not memory**, and must come *after* release-on-blur. Stack
  navigator only; never `enableFreeze()` globally (the tab navigator freezes a hidden tab before
  a delayed release can run).
- **Restore the top screen after a kill** (short window, not after a crash). No rule guarantees
  survival on a 2 GB phone; coming back where the user was makes a kill invisible.

## Kills and warnings

- iOS kills with `SIGKILL` at the footprint limit, no report; a memory warning *may* come first
  (clear the image cache in it, don't rely on it). Android's `lmkd` kills from cached processes
  up, largest first; the foreground app dies last, which on 2–3 GB phones is not rare.
- **Report kills**: Sentry watchdog terminations (iOS); `ApplicationExitInfo` with
  `REASON_LOW_MEMORY` read on next launch (Android 11+). Tag sessions with the feature in use.

## Not memory fixes

Memoisation, inline-function hygiene, smaller JSON, shorter query caches: a few MB at most
(halving query cache time: Android no change, iOS ~20 MiB). Fix what's mounted first.

## Review checklist for a new screen

1. Covered by a push: what stays mounted? Heavy children released on blur with a placeholder?
2. In a tab the user leaves: same question.
3. Every data-driven list a FlatList, `initialNumToRender` small if rows can be heavy?
4. Every image a sized copy; nothing decoded larger than its slot?
5. Every WebView on tap, leased, released on blur, not in a tab?
6. Every player poster-first, keyed by media id, unmounted on blur?
7. Anything after an endless list? A "Load more" button that should load on scroll?
8. Any `useEffect` cleanup doing work that must happen on blur?
9. Measured on a release build, on a real phone, before and after? (`reference.md`)

## More

`reference.md`: why each rule holds, and how to measure (commands, the 10-minute session, the
gate). `scripts/`: the samplers. `examples/webview-renderer/`: the Android module that ends an
idle renderer, and the JS lease.
