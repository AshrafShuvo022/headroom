#!/usr/bin/env python3
"""Pull one process's memory series out of an Instruments sysmon-process export.

Used for T19 of the SDK upgrade test matrix (memory after 10 minutes of
browsing). Works against a TestFlight or App Store build - no signing, no
rebuild, no debuggable binary required - so it measures the artifact that
actually ships.

  # 1. find the device (phone unlocked, USB cable that carries data)
  xcrun xctrace list devices

  # 2. record while someone browses the app for ten minutes
  xcrun xctrace record --template 'Activity Monitor' \\
      --device <UDID> --all-processes --time-limit 10m \\
      --output run.trace

  # 3. export the per-process table
  xcrun xctrace export --input run.trace \\
      --xpath '/trace-toc/run[@number="1"]/data/table[@schema="sysmon-process"]' \\
      --output run.xml

  # 4. read the series
  python3 scripts/trace-mem.py run.xml <app>

Confirm the recording is actually capturing samples before asking anyone to
start browsing - a failed session looks identical to a quiet one until the
export comes back empty, and ten minutes of someone's time is gone.

The XML interns repeated values: the first occurrence carries id="N" and later
occurrences are <tag ref="N"/>. Both forms have to be resolved or most rows
come back empty.
"""
import re, sys, xml.etree.ElementTree as ET

path, want = sys.argv[1], sys.argv[2].lower()

COLS = ["Timestamp", "Process Name", "Process Recently Died", "Kind",
        "Sudden Termination", "Sandbox", "Restricted", "App Nap",
        "Context Switch", "% CPU", "System Time", "User Time",
        "Disk Reads (B)", "Disk Writes (B)", "Faults", "Interrupt Wake Ups",
        "Mach Ports", "Memory", "Anonymous Mem", "Compressed Mem",
        "Purgeable Mem", "Real Private Mem", "Real Shared Mem",
        "Resident Size", "Virtual Size"]
IDX = {c: i for i, c in enumerate(COLS)}

store = {}


def val(el):
    """Resolve an element to its text, following ref= back to the interned value."""
    r = el.get("ref")
    if r is not None:
        return store.get(r, "")
    i = el.get("id")
    t = (el.get("fmt") or el.text or "").strip()
    if i is not None:
        store[i] = t
    return t


rows = []
for _, node in ET.iterparse(path, events=("end",)):
    if node.tag != "row":
        continue
    cells = [val(c) for c in list(node)]
    if len(cells) > IDX["Resident Size"]:
        name = cells[IDX["Process Name"]]
        if want in name.lower():
            rows.append(cells)
    node.clear()

if not rows:
    print(f"no samples for '{sys.argv[2]}'")
    sys.exit(1)


def mb(s):
    """Instruments formats these as '123.45 MB' / '1.2 GB' / raw bytes."""
    s = s.strip()
    m = re.match(r"([\d.,]+)\s*(KiB|MiB|GiB|KB|MB|GB|bytes)?", s, re.I)
    if not m:
        return None
    n = float(m.group(1).replace(",", ""))
    u = (m.group(2) or "bytes").lower()
    return n * {"bytes": 1/1048576, "kb": 1/1024, "kib": 1/1024,
                "mb": 1, "mib": 1, "gb": 1024, "gib": 1024}[u]


# One series per process. "Process Name" carries the PID ("<App> (1200)",
# "com.apple.WebKit.WebContent (921)"), so several processes can match the same
# search word - every WebContent process on the phone matches "WebContent".
# Mixing their rows into one series produced a curve that jumped between two
# processes' values. Each process is reported on its own, then a total.
by_proc = {}
for r in rows:
    by_proc.setdefault(r[IDX["Process Name"]], []).append(r)


def report(name, proc_rows):
    series = [(r[IDX["Timestamp"]], mb(r[IDX["Memory"]]), mb(r[IDX["Resident Size"]]))
              for r in proc_rows]
    series = [s for s in series if s[1] is not None]
    if not series:
        return None
    print(f"process     : {name}")
    print(f"samples     : {len(series)}")
    foot = [s[1] for s in series]
    res = [s[2] for s in series if s[2] is not None]
    print(f"footprint   : first {foot[0]:.1f} MB   last {foot[-1]:.1f} MB   "
          f"min {min(foot):.1f}   max {max(foot):.1f}   growth {foot[-1]-foot[0]:+.1f} MB")
    if res:
        print(f"resident    : first {res[0]:.1f} MB   last {res[-1]:.1f} MB   max {max(res):.1f} MB")
    # A coarse shape of the curve, so a steady climb is distinguishable from a spike.
    if len(foot) >= 8:
        step = len(foot) // 8
        pts = [foot[i] for i in range(0, len(foot), step)][:8]
        print("curve       : " + " -> ".join(f"{p:.0f}" for p in pts))
    return foot[-1]


lasts = []
for i, (name, proc_rows) in enumerate(by_proc.items()):
    if i:
        print()
    last = report(name, proc_rows)
    if last is not None:
        lasts.append(last)

if len(lasts) > 1:
    print()
    print(f"processes   : {len(lasts)} matching '{sys.argv[2]}'")
    print(f"total last  : {sum(lasts):.1f} MB footprint across them")
