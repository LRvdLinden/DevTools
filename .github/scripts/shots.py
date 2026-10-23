#!/usr/bin/env python3
"""Takes App Store screenshots in the simulators using DevTools' demo mode."""
import json, subprocess, time, os, sys

OUT = "shots"
os.makedirs(OUT, exist_ok=True)
DD = "dd/Build/Products"
APP = f"{DD}/Debug-iphonesimulator/DevTools.app"
WATCH_APP = f"{DD}/Debug-watchsimulator/DevToolsWatch.app"
BUNDLE = "nl.lrvdlinden.devtools"
WATCH_BUNDLE = "nl.lrvdlinden.devtools.watchkitapp"
LOG = open(f"{OUT}/log.txt", "w")

def sh(cmd, check=True):
    LOG.write("$ " + " ".join(cmd) + "\n"); LOG.flush()
    r = subprocess.run(cmd, capture_output=True, text=True)
    LOG.write(r.stdout[-2000:] + r.stderr[-2000:] + "\n"); LOG.flush()
    if check and r.returncode != 0:
        raise RuntimeError(f"failed: {cmd}")
    return r.stdout

types = json.loads(sh(["xcrun", "simctl", "list", "devicetypes", "-j"]))["devicetypes"]
runtimes = [r for r in json.loads(sh(["xcrun", "simctl", "list", "runtimes", "-j"]))["runtimes"] if r.get("isAvailable")]
LOG.write("TYPES: " + ", ".join(t["name"] for t in types) + "\n")
LOG.write("RUNTIMES: " + ", ".join(r["name"] for r in runtimes) + "\n")

def pick_type(prefs):
    names = {t["name"]: t["identifier"] for t in types}
    for p in prefs:
        for n, ident in names.items():
            if n.startswith(p):
                return n, ident
    return None, None

def runtime(platform):
    rs = [r for r in runtimes if r["platform"] == platform] if any("platform" in r for r in runtimes) else [r for r in runtimes if r["name"].startswith(platform)]
    if not rs:
        rs = [r for r in runtimes if platform.lower() in r["identifier"].lower()]
    return sorted(rs, key=lambda r: r["version"])[-1]["identifier"]

def boot(name, type_id, rt):
    udid = sh(["xcrun", "simctl", "create", name, type_id, rt]).strip()
    sh(["xcrun", "simctl", "boot", udid])
    sh(["xcrun", "simctl", "bootstatus", udid, "-b"], check=False)
    sh(["xcrun", "simctl", "ui", udid, "appearance", "dark"], check=False)
    return udid

def status_bar(udid):
    sh(["xcrun", "simctl", "status_bar", udid, "override", "--time", "9:41", "--dataNetwork", "wifi", "--wifiMode", "active",
        "--wifiBars", "3", "--cellularMode", "active", "--cellularBars", "4", "--batteryState", "charged", "--batteryLevel", "100"], check=False)

def shoot(udid, bundle, args, path, wait=7):
    sh(["xcrun", "simctl", "terminate", udid, bundle], check=False)
    sh(["xcrun", "simctl", "launch", udid, bundle, "-demo", "-noSplash", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + args)
    time.sleep(wait)
    sh(["xcrun", "simctl", "io", udid, "screenshot", "--type=png", path])

ios_rt = runtime("iOS")
screens = ["home", "insights", "app", "version", "build", "reviews", "apps", "guide"]

name, tid = pick_type(["iPhone 17 Pro Max", "iPhone 16 Pro Max", "iPhone 16 Plus", "iPhone 15 Pro Max"])
if tid:
    u = boot("shot-iphone", tid, ios_rt); status_bar(u)
    sh(["xcrun", "simctl", "install", u, APP])
    time.sleep(90)  # let first-boot system notifications pass
    for i, s in enumerate(screens):
        try: shoot(u, BUNDLE, ["-screen", s], f"{OUT}/iphone-{i+1:02d}-{s}.png")
        except Exception as e: LOG.write(f"ERR {s}: {e}\n")
    # splash (with animation running)
    try:
        sh(["xcrun", "simctl", "terminate", u, BUNDLE], check=False)
        sh(["xcrun", "simctl", "launch", u, BUNDLE, "-demo", "-holdSplash", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"])
        time.sleep(3.0); sh(["xcrun", "simctl", "io", u, "screenshot", "--type=png", f"{OUT}/iphone-00-splash.png"])
    except Exception as e: LOG.write(f"ERR splash: {e}\n")
    sh(["xcrun", "simctl", "shutdown", u], check=False)
    LOG.write(f"iPhone: {name}\n")

name, tid = pick_type(["iPad Pro 13-inch (M5)", "iPad Pro 13-inch (M4)", "iPad Pro (12.9-inch) (6th generation)", "iPad Air 13-inch"])
if tid:
    u = boot("shot-ipad", tid, ios_rt); status_bar(u)
    sh(["xcrun", "simctl", "install", u, APP])
    time.sleep(90)
    for i, s in enumerate(["home", "insights", "app", "build", "reviews"]):
        try: shoot(u, BUNDLE, ["-screen", s], f"{OUT}/ipad-{i+1:02d}-{s}.png", wait=11)
        except Exception as e: LOG.write(f"ERR ipad {s}: {e}\n")
    sh(["xcrun", "simctl", "shutdown", u], check=False)
    LOG.write(f"iPad: {name}\n")

try:
    w_rt = runtime("watchOS")
    name, tid = pick_type(["Apple Watch Ultra 3 (49mm)", "Apple Watch Ultra 2 (49mm)", "Apple Watch Series 11 (46mm)", "Apple Watch Series 10 (46mm)"])
    if tid:
        u = boot("shot-watch", tid, w_rt)
        sh(["xcrun", "simctl", "install", u, WATCH_APP])
        time.sleep(30)
        for i in range(3):
            try: shoot(u, WATCH_BUNDLE, ["-page", str(i)], f"{OUT}/watch-{i+1:02d}.png", wait=8)
            except Exception as e: LOG.write(f"ERR watch {i}: {e}\n")
        LOG.write(f"Watch: {name}\n")
except Exception as e:
    LOG.write(f"ERR watch: {e}\n")
LOG.close()
