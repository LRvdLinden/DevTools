"""Mac App Store screenshots (Mac Catalyst): 2880 × 1800 and 1280 × 800 (16:10).

Run from AppStore/_generator:  python3 mac_shots.py ../Mac-2880x1800 ../Mac-1280x800
"""
import io
import os
import sys

from PIL import Image
from playwright.sync_api import sync_playwright

from render import aurora, page, SIDEBAR_CSS
from ui import *  # noqa: F401,F403

OUT_BIG = sys.argv[1] if len(sys.argv) > 1 else "../Mac-2880x1800"
OUT_SMALL = sys.argv[2] if len(sys.argv) > 2 else "../Mac-1280x800"

MAC_CSS = SIDEBAR_CSS + """
.win{position:absolute;left:50%;border-radius:14px;overflow:hidden;background:#111318;
  box-shadow:0 0 0 1px rgba(255,255,255,.14),0 40px 90px rgba(0,0,0,.6),0 0 120px rgba(47,139,255,.22)}
.titlebar{height:38px;display:flex;align-items:center;gap:8px;padding:0 14px;background:#1B1D23;border-bottom:1px solid #2A2D35}
.tl{width:12px;height:12px;border-radius:6px}
.wtitle{flex:1;text-align:center;color:#C9CBD3;font-size:13px;font-weight:600;margin-right:60px}
.menubar{position:absolute;left:0;right:0;top:0;height:28px;background:rgba(10,14,30,.55);backdrop-filter:blur(20px);
  display:flex;align-items:center;gap:18px;padding:0 18px;color:#fff;font-size:13px;font-weight:500;z-index:5}
.menubar b{font-weight:700}
.mac .ipad{height:100%}
.mac .side{width:250px}
"""


def mac_screen(active, title, body):
    nav = [("Home", "⌂"), ("Apps", "≣"), ("TestFlight", "✈︎"), ("Insights", "↗"), ("Account", "◉")]
    items = "".join(f'<div class="it{" on" if n == active else ""}"><span style="width:20px;text-align:center">{g}</span>{n}</div>' for n, g in nav)
    apps = "".join(f'<div class="it">{icon(a, 24)}{a[1]}</div>' for a in APPS)
    side = (f'<div class="side"><div class="row" style="padding:0 10px 18px"><img src="logo.png" style="width:30px;height:30px">'
            f'<div><div style="font-size:18px;font-weight:800">DevTools</div><div class="sub">PixelForges</div></div></div>{items}'
            f'<div class="sec">My apps</div>{apps}</div>')
    return (f'<div class="screen mac"><div class="ipad">{side}<div class="main">'
            f'<div class="big" style="padding:18px 26px 14px">{title}</div><div class="content">{body}</div></div></div></div>')


def mac_shot(W, H, eyebrow, head, subl, screen_html, sw=1320, sh=760):
    win_w = W * 0.80
    scale = win_w / sw
    win_h = (sh + 38) * scale
    top = H * 0.30
    menu = '<div class="menubar"><b>DevTools</b><span>File</span><span>Edit</span><span>View</span><span>Window</span><span>Help</span></div>'
    cap = f'''<div class="cap" style="top:{H*0.075}px"><div class="eyebrow" style="font-size:{W*0.0135}px">{eyebrow}</div>
<div class="head" style="font-size:{W*0.036}px">{head}</div><div class="subl" style="font-size:{W*0.0145}px">{subl}</div></div>'''
    win = f'''<div class="win" style="width:{win_w}px;height:{win_h}px;top:{top}px;margin-left:{-win_w/2}px">
<div style="width:{sw}px;height:{sh+38}px;transform:scale({scale});transform-origin:0 0">
<div class="titlebar"><div class="tl" style="background:#FF5F57"></div><div class="tl" style="background:#FEBC2E"></div><div class="tl" style="background:#28C840"></div>
<div class="wtitle">DevTools</div></div>
<div style="height:{sh}px;position:relative;overflow:hidden">{screen_html}</div></div></div>'''
    return page(f'<div class="canvas">{aurora(W, H)}{menu}{cap}{win}</div>', MAC_CSS)


SHOTS = [
    ("01-dashboard", "Developer dashboard", "Your portfolio.<br><em>On your Mac.</em>", "Downloads, proceeds, status and attention items — with your apps in the sidebar.",
     lambda: mac_screen("Home", "Home", f'<div class="cols"><div>{dashboard()}</div><div><div class="card list" style="padding:4px 14px">{"".join(app_row(a) for a in APPS)}</div></div></div>')),
    ("02-app-detail", "Insights", "Every app.<br><em>Every number.</em>", "Install trends, countries, ratings, versions and builds side by side.",
     lambda: mac_screen("Apps", "Trailhead", f'<div class="cols"><div>{app_detail()}</div><div>{testflight()}</div></div>')),
    ("03-release", "Release", "Ship updates<br><em>from your desk.</em>", "What’s New, keywords and build — then submit for review. ⌘R refreshes everything.",
     lambda: mac_screen("Apps", "Version 2.5.0", f'<div class="cols"><div>{version_editor()}</div><div>{reviews()}</div></div>')),
    ("04-insights", "Analytics", "Charts that<br><em>tell the story.</em>", "Installs per app, devices, countries and proceeds — 7 days to a full year.",
     lambda: mac_screen("Insights", "Insights", f'<div class="cols"><div>{insights()}</div><div>{trend_card(series(30,330,70,7,1.2), sel=22, label="688", sub="Sat, Oct 17")}<div class="card list" style="padding:4px 14px">{"".join(app_row(a) for a in APPS[:4])}</div></div></div>')),
]


def main():
    os.makedirs(OUT_BIG, exist_ok=True)
    os.makedirs(OUT_SMALL, exist_ok=True)
    base = os.path.dirname(os.path.abspath(__file__))
    with sync_playwright() as p:
        b = p.chromium.launch()
        for name, eb, head, sub, fn in SHOTS:
            f = os.path.join(base, "_tmp.html")
            open(f, "w").write(mac_shot(1440, 900, eb, head, sub, fn()))
            pg = b.new_page(viewport={"width": 1440, "height": 900}, device_scale_factor=2)
            pg.goto("file://" + f)
            pg.wait_for_timeout(300)
            img = Image.open(io.BytesIO(pg.screenshot())).convert("RGB")
            pg.close()
            img.save(os.path.join(OUT_BIG, f"{name}.png"), optimize=True)
            img.resize((1280, 800), Image.LANCZOS).save(os.path.join(OUT_SMALL, f"{name}.png"), optimize=True)
            print(name, img.size)
        os.remove(os.path.join(base, "_tmp.html"))
        b.close()


if __name__ == "__main__":
    main()
