# headroom

Building a React Native or Expo app? It won't crash from memory. It'll be **killed**: no report,
no trace, just the splash screen again.

headroom is the guideline that prevents it, in one place: rules for lists, images, WebViews,
players and navigation, each with its reason and a measured number; a checklist for every new
screen; and the scripts to measure on iOS and Android. Use it as a Claude Code skill, or keep
`SKILL.md` open in code review.

Measured on a production app: **−36 % memory on Android, −43 % on iOS** at the end of a
10-minute session, flat instead of climbing.

## Install

```sh
# Claude Code: clone it into your project's skills
git clone https://github.com/AshrafShuvo022/headroom .claude/skills/headroom
```

Or just read `SKILL.md`. It's about 130 lines and it is the whole skill; the rest is optional.

## What's in it

- **`SKILL.md`**: the rules, by what you're building (lists, images, WebViews, players,
  navigation), and a 9-point review checklist for a new screen.
- **`reference.md`**: why each rule holds, and how to measure on iOS and Android: the right
  number, the 10-minute session, the commands, how to set a gate.
- **`scripts/`**: `trace-mem.py` (reads an Instruments export), `meminfo-sample.sh` (one
  Android sample as a CSV row, renderer process included), `run-session.sh` (the full 10-minute
  Android run).
- **`examples/webview-renderer/`**: a 50-line Expo module that ends Android's idle WebView
  renderer, and the JS lease that drives it.

## Three things we couldn't find written down anywhere

1. **Chrome's WebView renderer outlives the last WebView.** Open one embed and Android keeps a
   110–125 MB renderer process beside your app for the rest of the session, through
   `TRIM_MEMORY_COMPLETE`. It never shows in your app's own number. Ending it when no WebView has
   been open for 10 s took held memory from 396 to 282 MB. (`examples/webview-renderer/`)
2. **A WebView unmounted inside a hidden tab is never destroyed natively** (react-native-screens
   4 + bottom tabs, Android). The same WebView removed by Back from a pushed screen is. Put
   WebView-heavy content on pushed screens.
3. **expo-image's iOS memory cache ships unlimited.** The same prefetch is bounded on Android and
   grows forever on iOS. Two lines fix it; without measuring, the growth looks like a leak
   somewhere else.

## The one idea

Native memory is tied to what is **mounted**, not what is visible. Keep the screen, unmount only
the heavy child, put a placeholder in its place. Every rule in `SKILL.md` is that idea applied
to one situation.

## Measured on

React Native 0.86 (new architecture), Expo SDK 57, React Navigation 7, react-native-screens
4.26, react-native-webview 13.16, expo-image 3, expo-video 3; an iPhone 15 Pro on iOS 27 and a
6 GB Android phone on Android 16. One run per build on a live feed, so treat differences under
~20 MB as noise. The rules are general; the numbers are one app's. Re-measure on yours with
`reference.md` before quoting them.

## License

MIT.
