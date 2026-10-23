"""Product page assets: Header (21:9), Search Results (3:2) and the universal 16:9 image.

Run from AppStore/_generator:  python3 product_page.py ../ProductPage
Output is PNG without an alpha channel (Apple rejects transparency).
"""
import io
import os
import sys

from PIL import Image
from playwright.sync_api import sync_playwright

from render import aurora, page
from ui import *  # noqa: F401,F403  (phone_screen, dashboard, app_detail, insights, ...)

OUT = sys.argv[1] if len(sys.argv) > 1 else "../ProductPage"
SW, SH = 402, 874

EXTRA = """
.pchip{position:absolute;display:flex;align-items:center;gap:.5em;padding:.55em .95em;border-radius:999px;color:#fff;font-weight:700;
  background:rgba(255,255,255,.12);border:1px solid rgba(255,255,255,.28);box-shadow:0 18px 40px rgba(0,0,0,.35);white-space:nowrap;z-index:9}
.pchip .d{width:.62em;height:.62em;border-radius:50%}
.pchip small{font-weight:600;opacity:.72}
"""


def phone(ph_w, x, y, rot, html, z):
    scale = (ph_w * 0.93) / SW
    dev_h = SH * scale + ph_w * 0.07
    return f'''<div class="device" style="width:{ph_w}px;height:{dev_h}px;left:{x}px;top:{y}px;border-radius:{ph_w*0.16}px;transform:rotate({rot}deg);z-index:{z};margin-left:0">
<div class="glass" style="left:{ph_w*0.035}px;top:{ph_w*0.035}px;width:{ph_w*0.93}px;height:{SH*scale}px;border-radius:{ph_w*0.125}px">
<div class="island" style="top:{11*scale}px;width:{ph_w*0.93*0.31}px;height:{36*scale}px"></div>
<div class="scaled" style="width:{SW}px;height:{SH}px;transform:scale({scale})">{html}</div></div></div>'''


def screens():
    return (
        phone_screen("", app_detail(), "Apps", back="Apps", large=False, nav_title="Trailhead"),
        phone_screen("Home", dashboard(), "Home"),
        phone_screen("Insights", insights(), "Insights"),
    )


def fan(cx, top, ph_w):
    """Three phones fanned around centre x `cx` (middle one in front)."""
    left, mid, right = screens()
    gap = ph_w * 0.78
    return (phone(ph_w * 0.9, cx - gap - ph_w * 0.45, top + ph_w * 0.16, -8, left, 1)
            + phone(ph_w * 0.9, cx + gap - ph_w * 0.45, top + ph_w * 0.16, 8, right, 1)
            + phone(ph_w, cx - ph_w / 2, top, 0, mid, 3))


def chip(x, y, size, dot, text, sub=""):
    s = f' <small>{sub}</small>' if sub else ''
    return f'<div class="pchip" style="left:{x}px;top:{y}px;font-size:{size}px"><span class="d" style="background:{dot}"></span>{text}{s}</div>'


def headline(x, y, w, size, align="left", logo=True):
    lg = (f'<div class="row" style="gap:{size*0.3}px;justify-content:{"center" if align=="center" else "flex-start"}">'
          f'<img src="logo.png" style="width:{size*1.15}px;border-radius:{size*0.26}px"><div style="font-size:{size*0.8}px;font-weight:800">DevTools</div></div>') if logo else ''
    return f'''<div style="position:absolute;left:{x}px;top:{y}px;width:{w}px;text-align:{align}">{lg}
<div class="head" style="font-size:{size}px;margin-top:{size*0.45}px">Your App Store Connect.<br><em>In your pocket.</em></div>
<div class="subl" style="font-size:{size*0.34}px;margin-top:{size*0.4}px">Downloads, versions, TestFlight, reviews, widgets and Apple Watch.</div></div>'''


def header(W, H):
    # 21:9 — sits above the app icon and name, so no title text; subject centred.
    ph_w = H * 0.46
    body = fan(W / 2, H * 0.12, ph_w)
    c = H * 0.034
    body += chip(W * 0.18, H * 0.26, c, "#34D46A", "Live 2.4.1", "Trailhead")
    body += chip(W * 0.15, H * 0.56, c, "#2F8BFF", "12,480 installs", "30 days")
    body += chip(W * 0.69, H * 0.30, c, "#FFA733", "Build 318", "In Review")
    body += chip(W * 0.70, H * 0.60, c, "#FFD60A", "4.8 ★", "2,316 ratings")
    return page(f'<div class="canvas">{aurora(W, H)}{body}</div>', EXTRA)


def search(W, H):
    # 3:2 — headline on top, phones rising from the bottom.
    body = headline(W * 0.08, H * 0.08, W * 0.84, H * 0.075, align="center")
    body += fan(W / 2, H * 0.50, W * 0.25)
    c = H * 0.026
    body += chip(W * 0.07, H * 0.62, c, "#34D46A", "Live 2.4.1")
    body += chip(W * 0.75, H * 0.66, c, "#FFA733", "In Review")
    return page(f'<div class="canvas">{aurora(W, H)}{body}</div>', EXTRA)


def universal(W, H):
    # 16:9 — used for both placements. Header crops top/bottom (to 21:9), search crops the sides (to 3:2),
    # so everything stays inside the middle 84% width x 76% height.
    sx, sy = W * 0.08, H * 0.12
    sw, sh = W * 0.84, H * 0.76
    body = headline(sx + sw * 0.02, sy + sh * 0.12, sw * 0.46, sh * 0.095)
    body += fan(sx + sw * 0.74, sy + sh * 0.02, sh * 0.42)
    c = sh * 0.03
    body += chip(sx + sw * 0.02, sy + sh * 0.84, c, "#34D46A", "Live 2.4.1")
    body += chip(sx + sw * 0.17, sy + sh * 0.84, c, "#FFA733", "Build 318 · In Review")
    return page(f'<div class="canvas">{aurora(W, H)}{body}</div>', EXTRA)


JOBS = [
    # (file, builder, css width, css height, scale, final size)
    ("header-3840x1646.png", header, 1920, 823, 2, (3840, 1646)),
    ("search-results-3840x2560.png", search, 1920, 1280, 2, (3840, 2560)),
    ("search-results-1920x1280.png", search, 1920, 1280, 1, (1920, 1280)),
    ("universal-5244x2950.png", universal, 2622, 1475, 2, (5244, 2950)),
]


def main():
    os.makedirs(OUT, exist_ok=True)
    base = os.path.dirname(os.path.abspath(__file__))
    with sync_playwright() as p:
        b = p.chromium.launch()
        for name, fn, w, h, s, final in JOBS:
            f = os.path.join(base, "_tmp.html")
            open(f, "w").write(fn(w, h))
            pg = b.new_page(viewport={"width": w, "height": h}, device_scale_factor=s)
            pg.goto("file://" + f)
            pg.wait_for_timeout(300)
            img = Image.open(io.BytesIO(pg.screenshot())).convert("RGB")  # no alpha
            pg.close()
            if img.size != final:
                img = img.crop((0, 0, min(img.width, final[0]), min(img.height, final[1]))).resize(final, Image.LANCZOS)
            img.save(os.path.join(OUT, name), optimize=True)
            print(name, img.size, img.mode)
        b.close()


if __name__ == "__main__":
    main()
