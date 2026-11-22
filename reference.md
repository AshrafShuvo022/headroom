# Reference: why the rules hold, and how to measure

Read `SKILL.md` first; this is the background for when a rule is questioned, and the method for
checking your own numbers.

## Why

### JS holds handles, native holds the weight
A React Native process has two worlds. JavaScript (Hermes) holds components, state and JSON;
native holds the real views, bitmaps, WebViews, players and GPU buffers. JS keeps only a small
handle to each native object: an `<Image>` element is bytes in JS and a 0.5–11 MB bitmap in
native; a `<WebView>` element is a string in JS and a browser plus a content process in native.
So a JS heap snapshot can say 30 MB while the OS sees 400, and the garbage collector, which sees
only the tiny handle, feels no pressure to free the 30 MB player behind it. Release explicitly:
unmount, or call the library's release.

### Mounted, not visible
Native memory is allocated when a component mounts and freed when it unmounts. Re-renders reuse
the native object; hiding does not free it. A screen under a push, a left tab, `opacity: 0`,
`display: 'none'`, and anything far down a ScrollView are all mounted and holding. Only a
FlatList row outside the window and `{show && <Heavy />}` with `show` false give memory back.

### Navigation
A stack is an array of mounted screens: `push` adds one and keeps the rest; Back, `replace` and
`popToTop` unmount. A covered screen is *blurred*, so `useEffect` cleanup never runs; use
`useIsFocused` / `useFocusEffect`. Tabs mount on first visit and stay. Going to the background is
not a blur to navigation; only `AppState` knows. `freezeOnBlur` stops re-renders of hidden
screens (CPU), keeps their native views (memory), and must run after any release-on-blur. On
react-native-screens 4 / React Navigation 7, the native stack never freezes the screen just below
the top, so a short delayed release there works; the tab navigator freezes a hidden tab one tick
after the switch, before a delayed release could run. Also on Android, a WebView unmounted inside
a hidden tab is never destroyed natively (the tab's views are detached first); removed by Back
from a pushed screen, it is.

### Images
RAM is width × height × 4 bytes. Native image views downsample while decoding (RAM only; the
full file is still downloaded, decoded and cached), WebViews do not. expo-image's iOS memory
cache is an NSCache with cost limit 0 = unlimited, emptied only on a memory warning; Android's is
a bounded LRU. A prefetch to `'memory-disk'` on iOS stores full-size decoded originals there.

### WebViews
Three costs: the engine in your process (Android: ~75 MB from the first WebView, for the life of
the process); the drawn surface (a full-height WebView draws the whole document: ~91 MiB of GPU
surfaces per open document, measured); and the content process (iOS: one WebContent per
WebView, 8–214 MiB per document; Android: one Chrome renderer for all, 110–125 MB, kept after the
last WebView closes, through the trim). Rendering your own HTML natively from blocks removes the
second and third for that content; ending the idle renderer removes the third on Android.

### Players
Paused keeps buffers, the hardware decoder and the GPU surface; only unmount frees them.
Third-party web players are WebViews. On Android, buffered video sits in the Java heap as byte
arrays, so stacked players are the one way a React Native app gets a real `OutOfMemoryError`
instead of a silent kill.

### How the OS kills
iOS (jetsam): a per-app footprint limit, unpublished, roughly half of RAM or less in the
foreground; crossing it is an instant `SIGKILL`, no report; a warning may precede it. Android
(`lmkd`): processes ranked foreground → visible → services → cached, killed from the bottom,
largest first; the foreground app dies last, which on 2–3 GB phones with a big app is not rare.
Kills are seen only on the next launch: Sentry's watchdog-termination detection on iOS,
`ApplicationExitInfo` (`REASON_LOW_MEMORY`) on Android 11+.

## How to measure

### Six rules
1. **The number the OS kills on.** iOS: physical footprint (not resident). Android: PSS (not
   RSS). One run: footprint 99 → 279 MiB, resident 176 → 434; only the first is real. Never
   compare platforms with each other.
2. **A curve over a fixed session**, not a snapshot. A cache flattens; a leak keeps sloping.
3. **Every process.** Web content is in another process and absent from the app's number.
4. **What ships.** Release build, real phone. Debug builds, simulators and emulators lie.
5. **Same conditions every run**: phone, build type, cold start, script, network, toggles.
6. **How much first, then what.** The cheap curve on the shipping build; Instruments / heap
   dumps only once you know which minute to look at.

### The 10-minute session (template)
One activity per minute, read to the tester on a clock. Fill with your screens; keep the shape:
0 cold start, scroll the main list · 1 detail → push two more → Back ×3 · 2 flip a setting that
re-requests images (language, theme) and start media · 3 the media screen, play ~30 s · 4 an
outside link in the browser, back · 5 a second entry point, push two, back out · 6 the toggle
twice, a light screen · 7 the longest content screen, read to the end · 8 media detail → related
→ Back · 9 idle, hands off. Then on Android: Home button, 8 s, sample; `TRIM_MEMORY_COMPLETE`,
15 s, sample (what is left is what the app holds). Noise between two runs on live data: ~20 MB.

### iOS
```sh
xcrun xctrace record --template 'Activity Monitor' --device <UDID> --attach <app> \
  --time-limit 660s --output run.trace            # app only
xcrun xctrace record --template 'Activity Monitor' --device <UDID> --all-processes \
  --time-limit 700s --output run.trace            # with WebContent; the save takes minutes
xcrun xctrace export --input run.trace \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="sysmon-process"]' --output run.xml
python3 scripts/trace-mem.py run.xml <app>        # per-second footprint, per process
python3 scripts/trace-mem.py run.xml WebContent   # every WebKit process
```
WebContent processes are not labelled by app: yours are the ones that start after your launch.
To see *what* is inside (needs a development-signed build): Instruments Allocations + VM
Tracker, read in the Instruments window; watch IOSurface / CoreAnimation (drawn surfaces),
ImageIO / CG raster (bitmaps), WebKit.

### Android
```sh
scripts/run-session.sh <package> [serial]         # cold launch, 10 samples, Home, trim; CSV
scripts/meminfo-sample.sh <package> [serial]      # one sample now, renderer included
```
From `dumpsys meminfo` App Summary: Java Heap, Native Heap (Hermes, bitmaps), Graphics (GPU;
a full-height WebView shows in `Gfx dev` / `EGL mtrack`), and `WebViews:` (objects not yet
collected; a hint, one GC behind). The renderer process is under "Total PSS by process" as
`sandboxed_process…webview`; exclude the PIDs that existed before your launch. Use KB ÷ 1024
consistently. For what's inside: Android Studio's Memory Profiler heap dump, mostly for players.

### Record every run
One CSV per run, header stating device, OS, build and commit, method, and anything unusual (a
late cue, a touch during idle). It's what makes a run comparable a month later.

### The gate
Not ratios ("≤ 1.5× cold start" punishes a lean start). At rest under a budget sized to your
users' phones (a content app for 2–4 GB phones: iOS ≤ 200 MiB on home at the end, Android
≤ 300 MB after the trim, renderer counted); a peak ceiling; flat over the last 3 minutes; a leak
check (the same screen opened and left 10 times, at rest within 10 % of before); within 10 % of
the last accepted baseline. In the field: ≥ 99.9 % of sessions free of a foreground memory kill
per release, over 7 days and 5,000+ sessions. Lab says a fix works; field says it worked.

### Reading the curve
Rising to the end: things kept mounted. Sawtooth with a flat tail: release works, what remains
is caches and engines. A spike that drops back: media or a long document; a peak, not a leak. A
process that never ends beside the app: count it, don't just read the app's number.
