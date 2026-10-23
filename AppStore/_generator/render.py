import os, sys
from playwright.sync_api import sync_playwright
import ui
from ui import *

OUT = sys.argv[1] if len(sys.argv) > 1 else "out"

FRAME_CSS = """
.canvas{position:relative;overflow:hidden;background:#030A1C;width:100vw;height:100vh}
.aur{position:absolute;border-radius:50%;filter:blur(70px);opacity:.75}
.gridbg{position:absolute;inset:0;background-image:linear-gradient(rgba(255,255,255,.045) 1px,transparent 1px),linear-gradient(90deg,rgba(255,255,255,.045) 1px,transparent 1px);background-size:34px 34px;-webkit-mask-image:radial-gradient(circle at 50% 30%,#000,transparent 70%)}
.cap{position:absolute;left:0;right:0;text-align:center;padding:0 7%}
.eyebrow{color:#5FE0FF;font-weight:700;letter-spacing:.14em;text-transform:uppercase}
.head{color:#fff;font-weight:800;letter-spacing:-.02em;line-height:1.06;margin-top:.35em}
.head em{font-style:normal;background:linear-gradient(90deg,#4DA3FF,#5FE0FF);-webkit-background-clip:text;color:transparent}
.subl{color:rgba(255,255,255,.72);font-weight:500;margin-top:.55em;line-height:1.35}
.device{position:absolute;left:50%;background:#1b1d22;box-shadow:0 0 0 2px #4a4d55,0 40px 80px rgba(0,0,0,.6),0 0 90px rgba(47,139,255,.25)}
.device .glass{position:absolute;overflow:hidden;background:#111318}
.device .scaled{transform-origin:0 0;position:absolute;left:0;top:0}
.island{position:absolute;left:50%;transform:translateX(-50%);background:#000;border-radius:99px;z-index:20}
"""


def aurora(w, h):
    blobs = [("#0A4FE0", -0.25, -0.15, 1.0), ("#18B7F2", 0.55, 0.05, 0.75), ("#6A3DF0", -0.15, 0.55, 0.8), ("#0E7BFF", 0.6, 0.75, 0.7)]
    s = ""
    for c, x, y, size in blobs:
        d = w * size
        s += f'<div class="aur" style="background:{c};width:{d}px;height:{d}px;left:{x*w}px;top:{y*h}px"></div>'
    return s + '<div class="gridbg"></div>'


def page(inner, extra_css=""):
    return f'<!doctype html><html><head><meta charset="utf-8"><style>{ui.CSS}{FRAME_CSS}{extra_css}</style></head><body>{inner}</body></html>'


# ---------- iPhone ----------
def iphone_shot(W, H, eyebrow, head, subl, screen_html, sw=402, sh=874, dev_top=0.285):
    dev_w = W * 0.80
    bezel = dev_w * 0.035
    glass_w = dev_w - 2 * bezel
    scale = glass_w / sw
    glass_h = sh * scale
    dev_h = glass_h + 2 * bezel
    radius = dev_w * 0.16
    top = H * dev_top
    island_w = glass_w * 0.31
    cap = f'''<div class="cap" style="top:{H*0.055}px"><div class="eyebrow" style="font-size:{W*0.03}px">{eyebrow}</div>
<div class="head" style="font-size:{W*0.083}px">{head}</div><div class="subl" style="font-size:{W*0.036}px">{subl}</div></div>'''
    device = f'''<div class="device" style="width:{dev_w}px;height:{dev_h}px;top:{top}px;margin-left:{-dev_w/2}px;border-radius:{radius}px">
<div class="glass" style="left:{bezel}px;top:{bezel}px;width:{glass_w}px;height:{glass_h}px;border-radius:{radius-bezel}px">
<div class="island" style="top:{11*scale}px;width:{island_w}px;height:{36*scale}px"></div>
<div class="scaled" style="width:{sw}px;height:{sh}px;transform:scale({scale})">{screen_html}</div></div></div>'''
    return page(f'<div class="canvas">{aurora(W,H)}{cap}{device}</div>')


# ---------- iPad ----------
SIDEBAR_CSS = f"""
.ipad{{display:flex;height:100%;background:{BG}}}
.side{{width:300px;background:#17191E;border-right:1px solid {SEP};padding:28px 14px;flex:none}}
.side .it{{display:flex;align-items:center;gap:11px;padding:9px 12px;border-radius:10px;font-size:16px;font-weight:500;color:#E8E9EE}}
.side .it.on{{background:{ACCENT};color:#fff}}
.side .sec{{font-size:12px;color:{SEC};font-weight:700;letter-spacing:.06em;margin:20px 12px 6px;text-transform:uppercase}}
.ipad .main{{flex:1;position:relative;overflow:hidden}}
.ipad .content{{padding:0 26px 40px}}
.cols{{display:grid;grid-template-columns:1fr 1fr;gap:14px;align-items:start}}
.cols>div{{display:flex;flex-direction:column;gap:14px}}
"""


def ipad_screen(active, title, body):
    nav = [("Home", "⌂"), ("Apps", "≣"), ("TestFlight", "✈︎"), ("Insights", "↗"), ("Account", "◉")]
    items = "".join(f'<div class="it{" on" if n == active else ""}"><span style="width:20px;text-align:center">{g}</span>{n}</div>' for n, g in nav)
    apps = "".join(f'<div class="it">{icon(a, 26)}{a[1]}</div>' for a in APPS)
    side = f'''<div class="side"><div class="row" style="padding:0 10px 18px"><img src="logo.png" style="width:34px;height:34px"><div><div style="font-size:20px;font-weight:800">DevTools</div><div class="sub">PixelForges</div></div></div>{items}<div class="sec">My apps</div>{apps}</div>'''
    return f'<div class="screen"><div class="ipad">{side}<div class="main">{status_bar()}<div class="big" style="padding:4px 26px 14px">{title}</div><div class="content">{body}</div></div></div></div>'


def ipad_shot(W, H, eyebrow, head, subl, screen_html, sw=1032, sh=1376):
    dev_w = W * 0.86
    bezel = dev_w * 0.022
    glass_w = dev_w - 2 * bezel
    scale = glass_w / sw
    glass_h = sh * scale
    dev_h = glass_h + 2 * bezel
    radius = dev_w * 0.045
    top = H * 0.27
    cap = f'''<div class="cap" style="top:{H*0.05}px"><div class="eyebrow" style="font-size:{W*0.02}px">{eyebrow}</div>
<div class="head" style="font-size:{W*0.058}px">{head}</div><div class="subl" style="font-size:{W*0.024}px">{subl}</div></div>'''
    device = f'''<div class="device" style="width:{dev_w}px;height:{dev_h}px;top:{top}px;margin-left:{-dev_w/2}px;border-radius:{radius}px">
<div class="glass" style="left:{bezel}px;top:{bezel}px;width:{glass_w}px;height:{glass_h}px;border-radius:{radius-bezel}px">
<div class="scaled" style="width:{sw}px;height:{sh}px;transform:scale({scale})">{screen_html}</div></div></div>'''
    return page(f'<div class="canvas">{aurora(W,H)}{cap}{device}</div>', SIDEBAR_CSS)


# ---------- Widgets home screen ----------
def widgets_screen():
    vals = series(30, 330, 70, 7, 1.2)
    medium = f'''<div class="wd" style="grid-column:span 2;height:170px;display:flex;gap:12px">
<div style="width:132px"><div class="row" style="gap:6px"><img src="logo.png" style="width:17px"><b style="font-size:13px">All apps</b></div>
<div style="font-size:28px;font-weight:800;margin-top:4px">12,480</div><div class="sub" style="font-size:11px">downloads · 30d</div>
<div style="font-size:11.5px;font-weight:700;color:{LIVE};margin-top:4px">↗ +1,036 <span style="color:{SEC};font-weight:400">7d</span></div>
<div style="font-size:11.5px;font-weight:700;margin-top:18px"><span style="color:{LIVE}">€</span> €3,214</div></div>
<div style="flex:1"><div class="row" style="gap:12px;font-size:11px;font-weight:700"><span><span style="color:#FFD60A">★</span> 4.7</span><span><span style="color:{PENDING}">⟳</span> 8.9K</span><span><span style="color:{REVIEW}">⌛</span> 1</span></div>{area_chart(vals, 200, 112, ACCENT, axis=False)}</div></div>'''
    small = f'''<div class="wd" style="height:170px"><div class="row" style="gap:6px"><img src="logo.png" style="width:14px"><span class="sub" style="font-size:11px;font-weight:700">Status</span></div>
{"".join(f'<div class="row" style="gap:8px;margin-top:9px"><span style="width:24px;height:24px;border-radius:24px;background:{c}26;color:{c};display:flex;align-items:center;justify-content:center;font-size:12px">{g}</span><div><b style="font-size:16px">{v}</b><div class="sub" style="font-size:10px">{l}</div></div></div>' for g, c, v, l in [("✓", LIVE, 4, "Live"), ("⌛", REVIEW, 1, "In review"), ("!", PENDING, 2, "Attention")])}</div>'''
    small2 = f'''<div class="wd" style="height:170px"><div class="row" style="gap:6px">{icon(APPS[0], 18)}<b style="font-size:12.5px">Trailhead</b></div><div style="font-size:25px;font-weight:800;margin-top:3px">5,840</div>
<div style="font-size:11px;font-weight:700;color:{LIVE}">↗ +412 <span style="color:{SEC};font-weight:400">7d</span></div>{area_chart(series(30,170,40,3,.4), 140, 70, LIVE, axis=False)}</div>'''
    rows = ""
    for a in APPS[:4]:
        sp, _ = smooth_path(series(20, a[5] / 30, a[5] / 80, a[6] / 400, APPS.index(a)), 56, 22, pad=2)
        col = LIVE if a[7] == "READY_FOR_SALE" else STATE[a[7]][1]
        lab = f"v{a[8]}" if a[7] == "READY_FOR_SALE" else STATE[a[7]][0]
        d = f'+{a[6]}' if a[6] >= 0 else f'−{-a[6]}'
        rows += f'''<div class="row" style="margin-top:9px;gap:9px">{icon(a, 30)}<div style="flex:1"><b style="font-size:12.5px">{a[1]}</b><div style="font-size:9.5px;font-weight:600;color:{col}">{lab} <span style="color:#FFD60A">★ {a[9] or "–"}</span></div></div>
<svg width="56" height="22"><path d="{sp}" fill="none" stroke="{ACCENT}" stroke-width="1.6"/></svg><div style="text-align:right;width:48px"><b style="font-size:12.5px">{a[5]/1000:.1f}K</b><div style="font-size:9.5px;font-weight:700;color:{LIVE if a[6]>=0 else RED}">{d}</div></div></div>'''
    large = f'''<div class="wd" style="grid-column:span 2;height:250px"><div class="row" style="gap:6px"><img src="logo.png" style="width:14px"><span class="sub" style="font-size:11px;font-weight:700">Top apps</span><div class="sp"></div><span class="sub" style="font-size:11px">12.5K · 30d</span></div>{rows}</div>'''
    css = f""".hs{{position:absolute;inset:0;background:radial-gradient(circle at 20% 10%,#2b5bd7,transparent 55%),radial-gradient(circle at 90% 70%,#7a3df0,transparent 50%),linear-gradient(160deg,#0b1d4f,#120a2e)}}
.wgrid{{position:absolute;top:70px;left:22px;right:22px;display:grid;grid-template-columns:1fr 1fr;gap:20px}}
.wd{{background:rgba(25,27,34,.92);border-radius:22px;padding:14px;box-shadow:0 10px 30px rgba(0,0,0,.35)}}
.dock{{position:absolute;bottom:18px;left:14px;right:14px;height:92px;border-radius:30px;background:rgba(255,255,255,.18);display:flex;justify-content:space-around;align-items:center}}"""
    dock = "".join(icon(a, 62) for a in APPS[:3]) + '<img src="logo.png" style="width:64px;height:64px">'
    return f'<style>{css}</style><div class="screen"><div class="hs"></div>{status_bar()}<div class="wgrid">{medium}{small}{small2}{large}</div><div class="dock">{dock}</div></div>'


# ---------- Apple Watch ----------
WATCH_CSS = f"""
html,body{{background:#000}}.w{{background:#000;color:#fff;width:100vw;height:100vh;padding:8px 10px;font-size:11px;position:relative;overflow:hidden}}
.wt{{display:flex;justify-content:space-between;align-items:center;font-size:12px;font-weight:600;margin:2px 2px 6px}}
.wt b{{color:{ACCENT};font-size:13px}}
.ws{{background:rgba(255,255,255,.1);border-radius:10px;padding:6px 7px}}
.ws .l{{font-size:9.5px;font-weight:600}}.ws .v{{font-size:17px;font-weight:700;margin-top:1px}}
.wrow{{background:#1C1C1E;border-radius:12px;padding:7px 8px;display:flex;gap:7px;align-items:center;margin-bottom:5px}}
"""


def watch_page(inner):
    return page(f'<div class="w">{inner}</div>', WATCH_CSS)


def watch_overview():
    vals = series(30, 330, 70, 7, 1.2)
    return watch_page(f'''<div class="wt"><b>DevTools</b><span>9:41</span></div>
<div style="font-size:10px;color:{SEC}">Downloads · 30d</div><div style="font-size:30px;font-weight:800;line-height:1.05">12,480</div>
<div style="font-size:11px;color:{LIVE};font-weight:600">+1K · 7d</div>{area_chart(vals, 190, 40, ACCENT, axis=False)}
<div style="display:grid;grid-template-columns:1fr 1fr;gap:5px;margin-top:4px">
<div class="ws"><div class="l" style="color:{LIVE}">✓ Live</div><div class="v">4</div></div><div class="ws"><div class="l" style="color:{REVIEW}">⌛ In review</div><div class="v">1</div></div>
<div class="ws"><div class="l" style="color:{LIVE}">€ Proceeds</div><div class="v">€3.2K</div></div><div class="ws"><div class="l" style="color:#FFD60A">★ Rating</div><div class="v">4.7</div></div></div>''')


def watch_apps():
    rows = ""
    for a in APPS[:4]:
        col = LIVE if a[7] == "READY_FOR_SALE" else STATE[a[7]][1]
        d = f'+{a[6]}' if a[6] >= 0 else f'−{-a[6]}'
        rows += f'<div class="wrow">{icon(a, 28)}<div style="flex:1"><div style="font-size:12px;font-weight:700">{a[1]}</div><div style="font-size:10px;color:{SEC}">{a[5]/1000:.1f}K <span style="color:{LIVE if a[6]>=0 else RED}">{d}</span></div></div><i style="width:8px;height:8px;border-radius:8px;background:{col}"></i></div>'
    return watch_page(f'<div class="wt"><b>My Apps</b><span>9:41</span></div>{rows}')


def watch_detail():
    a = APPS[0]
    vals = series(30, 170, 40, 3, .4)
    rows = "".join(f'<div style="display:flex;justify-content:space-between;font-size:11px;margin:3px 0"><span style="color:{SEC}">{k}</span><span style="color:{c};font-weight:600">{v}</span></div>' for k, v, c in
                   [("Status", "Live", LIVE), ("Next", "v2.5.0 · Waiting for Review", REVIEW), ("Build", "318", CYAN), ("Rating", "4.8 ★", "#FFD60A")])
    return watch_page(f'''<div class="wt"><b>‹ Trailhead</b><span>9:41</span></div><div class="row" style="gap:8px">{icon(a, 36)}<div><div style="font-size:24px;font-weight:800;line-height:1">5,840</div><div style="font-size:10px;color:{SEC}">downloads</div></div></div>
<div style="font-size:11px;color:{LIVE};font-weight:600;margin-top:3px">+412 · 7d</div>{area_chart(vals, 190, 42, ACCENT, axis=False)}{rows}''')


def watch_attention():
    return watch_page(f'''<div class="wt"><b>Attention</b><span>9:41</span></div><div style="font-size:10px;color:{SEC};font-weight:700;margin:2px 4px 4px">IN REVIEW</div>
<div class="wrow">{icon(APPS[1], 24)}<div><div style="font-size:12px;font-weight:700">Lumen Notes</div><div style="font-size:10px;color:{REVIEW}">v1.9.0 · Waiting for Review</div></div></div>
<div style="font-size:10px;color:{SEC};font-weight:700;margin:7px 4px 4px">NEEDS ATTENTION</div>
<div class="wrow">{icon(APPS[3], 24)}<div><div style="font-size:12px;font-weight:700">Tempo Timer</div><div style="font-size:10px;color:{CYAN}">Ready for Distribution</div></div></div>
<div class="wrow">{icon(APPS[5], 24)}<div><div style="font-size:12px;font-weight:700">Harbor Budget</div><div style="font-size:10px;color:{REVIEW}">Export compliance</div></div></div>''')


# ---------- Promo ----------
def promo(W, H):
    shot = phone_screen("Home", dashboard(), "Home")
    sw, sh = 402, 874
    ph_w = W * 0.22
    scale = (ph_w * 0.93) / sw
    def ph(x, y, rot, html, z):
        dev_h = sh * scale + ph_w * 0.07
        return f'''<div class="device" style="width:{ph_w}px;height:{dev_h}px;left:{x}px;top:{y}px;border-radius:{ph_w*0.16}px;transform:rotate({rot}deg);z-index:{z};margin-left:0">
<div class="glass" style="left:{ph_w*0.035}px;top:{ph_w*0.035}px;width:{ph_w*0.93}px;height:{sh*scale}px;border-radius:{ph_w*0.125}px"><div class="scaled" style="width:{sw}px;height:{sh}px;transform:scale({scale})">{html}</div></div></div>'''
    p1 = ph(W * 0.52, H * 0.16, -6, phone_screen("", app_detail(), "Apps", back="Apps", large=False, nav_title="Trailhead"), 1)
    p2 = ph(W * 0.71, H * 0.09, 5, shot, 2)
    text = f'''<div style="position:absolute;left:{W*0.07}px;top:{H*0.26}px;width:{W*0.44}px">
<div class="row" style="gap:{W*0.012}px"><img src="logo.png" style="width:{W*0.06}px"><div style="font-size:{W*0.04}px;font-weight:800">DevTools</div></div>
<div class="head" style="font-size:{W*0.045}px;margin-top:{H*0.04}px">Your App Store Connect.<br><em>In your pocket.</em></div>
<div class="subl" style="font-size:{W*0.016}px;margin-top:{H*0.03}px">Downloads, versions, TestFlight, reviews, widgets and Apple Watch — for indie developers.</div></div>'''
    return page(f'<div class="canvas">{aurora(W,H)}{text}{p1}{p2}</div>')


# ---------- Shots ----------
IPHONE = [
    ("01-dashboard", "Developer dashboard", "Your apps.<br><em>At a glance.</em>", "Downloads, proceeds and status of every app — the moment you open it.",
     lambda: phone_screen("Home", dashboard(), "Home")),
    ("02-app-detail", "Insights", "Every app.<br><em>Every number.</em>", "Install trends, top countries, ratings and the latest build per app.",
     lambda: phone_screen("", app_detail(), "Apps", back="Apps", large=False, nav_title="Trailhead")),
    ("03-new-version", "Release", "Ship updates<br><em>from anywhere.</em>", "Create a version, write What’s New in every language and submit for review.",
     lambda: phone_screen("", version_editor(), "Apps", back="Trailhead", large=False, nav_title="2.5.0")),
    ("04-testflight", "TestFlight", "Builds &amp; testers<br><em>under control.</em>", "What to Test, test groups, auto-notify and beta review in a few taps.",
     lambda: phone_screen("", testflight(), "TestFlight", back="Builds", large=False, nav_title="Build 318")),
    ("05-insights", "Analytics", "Charts that<br><em>tell the story.</em>", "Installs, updates, in-app purchases and proceeds across your portfolio.",
     lambda: phone_screen("Insights", insights(), "Insights")),
    ("06-reviews", "Customer reviews", "Reply to reviews<br><em>in seconds.</em>", "See every rating, filter by stars and respond right from your iPhone.",
     lambda: phone_screen("", reviews(), "Apps", back="Trailhead", large=False, nav_title="Ratings & Reviews")),
    ("07-widgets", "Widgets", "Your numbers<br><em>on your Home Screen.</em>", "Pick an app or show them all. Live, in review and downloads always in view.",
     widgets_screen),
]

IPAD = [
    ("01-dashboard", "Developer dashboard", "Your portfolio.<br><em>One screen.</em>", "Downloads, proceeds, status and attention items — with your apps in the sidebar.",
     lambda: ipad_screen("Home", "Home", f'<div class="cols"><div>{dashboard()}</div><div><div class="card list" style="padding:4px 14px">{"".join(app_row(a) for a in APPS)}</div>{insights()}</div></div>')),
    ("02-app-detail", "Insights", "Every app.<br><em>Every number.</em>", "Install trends, countries, ratings, versions and builds side by side.",
     lambda: ipad_screen("Apps", "Trailhead", f'<div class="cols"><div>{app_detail()}</div><div>{testflight()}</div></div>')),
    ("03-new-version", "Release", "Ship updates<br><em>from anywhere.</em>", "What’s New, promotional text, keywords and build — then submit for review.",
     lambda: ipad_screen("Apps", "Version 2.5.0", f'<div class="cols"><div>{version_editor()}</div><div>{reviews()}</div></div>')),
    ("04-insights", "Analytics", "Charts that<br><em>tell the story.</em>", "Installs per app, devices, countries and proceeds — 7 days to a full year.",
     lambda: ipad_screen("Insights", "Insights", f'<div class="cols"><div>{insights()}</div><div>{trend_card(series(30,330,70,7,1.2), sel=22, label="688", sub="Sat, Oct 17")}<div class="card list" style="padding:4px 14px">{"".join(app_row(a) for a in APPS[:4])}</div></div></div>')),
]

WATCH = [("01-overview", watch_overview), ("02-apps", watch_apps), ("03-detail", watch_detail), ("04-attention", watch_attention)]


def main():
    os.makedirs(OUT, exist_ok=True)
    base = os.path.dirname(os.path.abspath(__file__))
    with sync_playwright() as p:
        b = p.chromium.launch()

        def shoot(html, w, h, scale, path):
            f = os.path.join(base, "_tmp.html")
            open(f, "w").write(html)
            pg = b.new_page(viewport={"width": w, "height": h}, device_scale_factor=scale)
            pg.goto("file://" + f)
            pg.wait_for_timeout(250)
            pg.screenshot(path=path, omit_background=False)
            pg.close()

        sets = [("iPhone-6.9in-1320x2868", 440, 956, 3), ("iPhone-6.3in-1206x2622", 402, 874, 3)]
        for folder, w, h, s in sets:
            d = os.path.join(OUT, folder); os.makedirs(d, exist_ok=True)
            for name, eb, head, sub, fn in IPHONE:
                shoot(iphone_shot(w, h, eb, head, sub, fn()), w, h, s, os.path.join(d, f"{name}.png"))
        d = os.path.join(OUT, "iPad-13in-2064x2752"); os.makedirs(d, exist_ok=True)
        for name, eb, head, sub, fn in IPAD:
            shoot(ipad_shot(1032, 1376, eb, head, sub, fn()), 1032, 1376, 2, os.path.join(d, f"{name}.png"))
        for folder, w, h in [("AppleWatch-Ultra-422x514", 211, 257), ("AppleWatch-Series-416x496", 208, 248)]:
            d = os.path.join(OUT, folder); os.makedirs(d, exist_ok=True)
            for name, fn in WATCH:
                shoot(fn(), w, h, 2, os.path.join(d, f"{name}.png"))
        d = os.path.join(OUT, "Promo"); os.makedirs(d, exist_ok=True)
        shoot(promo(1920, 1080), 1920, 1080, 1, os.path.join(d, "promo-1920x1080.png"))
        shoot(promo(1200, 630), 1200, 630, 1, os.path.join(d, "social-1200x630.png"))
        b.close()


if __name__ == "__main__":
    main()
