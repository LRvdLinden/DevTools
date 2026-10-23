#!/usr/bin/env python3
"""Renders the Homey app images (assets/images) and the driver images (white background + device icon).

Run: python3 tools/render_images.py   (needs Playwright + Pillow)
"""
import base64
import io
import math
import os
import random

from PIL import Image
from playwright.sync_api import sync_playwright

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICON_PNG = os.path.join(ROOT, 'tools', 'ios-app-icon.png')


def b64(path):
    with open(path, 'rb') as f:
        return base64.b64encode(f.read()).decode()


def chart_path(w, h, seed=7, n=30):
    random.seed(seed)
    vals, v = [], 40
    for i in range(n):
        v += random.uniform(-6, 9) + (2.2 if i > n * .55 else .6)
        vals.append(max(8, v))
    lo, hi = min(vals), max(vals)
    pts = [(i * w / (n - 1), h - 10 - (x - lo) / (hi - lo) * (h - 26)) for i, x in enumerate(vals)]
    d = f'M{pts[0][0]:.1f},{pts[0][1]:.1f}'
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        cx = (x0 + x1) / 2
        d += f' C{cx:.1f},{y0:.1f} {cx:.1f},{y1:.1f} {x1:.1f},{y1:.1f}'
    return d, d + f' L{w},{h} L0,{h} Z', pts[-1]


ICONS = {
    'download': '<path d="M12 4v10m0 0l-4-4m4 4l4-4M5 19h14" stroke="currentColor" stroke-width="2.4" fill="none" stroke-linecap="round" stroke-linejoin="round"/>',
    'tag': '<path d="M4 12V5a1 1 0 0 1 1-1h7l8 8-8 8z" stroke="currentColor" stroke-width="2.2" fill="none" stroke-linejoin="round"/><circle cx="8.5" cy="8.5" r="1.6" fill="currentColor"/>',
    'star': '<path d="M12 3.5l2.6 5.4 5.9.8-4.3 4.1 1 5.8L12 16.9 6.8 19.6l1-5.8L3.5 9.7l5.9-.8z" fill="currentColor"/>',
    'check': '<path d="M5 12.5l4.5 4.5L19 7.5" stroke="currentColor" stroke-width="2.6" fill="none" stroke-linecap="round" stroke-linejoin="round"/>',
    'bell': '<path d="M6 16V11a6 6 0 0 1 12 0v5l1.5 2h-15zM10 20.5a2 2 0 0 0 4 0" stroke="currentColor" stroke-width="2.2" fill="none" stroke-linejoin="round"/>',
    'hammer': '<path d="M14 4l6 6-2 2-6-6zM12 6L4 18l2 2 12-8" stroke="currentColor" stroke-width="2.2" fill="none" stroke-linejoin="round"/>',
}


def ico(name, size=22):
    return f'<svg width="{size}" height="{size}" viewBox="0 0 24 24">{ICONS[name]}</svg>'


def app_html(compact=False):
    icon = b64(ICON_PNG)
    line, area, last = chart_path(372, 150)
    bars = ''.join(
        f'<div class="bar" style="height:{h}%"></div>' for h in [38, 52, 44, 61, 57, 72, 66, 84, 79, 100])
    if compact:
        body = f'''
        <div class="compact">
          <img class="cicon" src="data:image/png;base64,{icon}">
          <div class="ctitle">App Store<br>Connect</div>
        </div>'''
    else:
        body = f'''
        <div class="left">
          <img class="icon" src="data:image/png;base64,{icon}">
          <div class="title">App Store<br>Connect</div>
          <div class="sub">Downloads, App Review, TestFlight and reviews of your apps in Homey</div>
          <div class="tokens">
            <span class="tok">{ico('download',18)} Downloads <b>128</b></span>
            <span class="tok">{ico('tag',18)} Live <b>1.4.2</b></span>
            <span class="tok">{ico('star',18)} <b>4.8</b></span>
          </div>
        </div>

        <div class="card insights">
          <div class="chead"><span class="dot"></span>Downloads · 30 days</div>
          <div class="big">3,482 <span class="up">▲ 18%</span></div>
          <svg class="chart" viewBox="0 0 372 150" preserveAspectRatio="none">
            <defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0" stop-color="#0A84FF" stop-opacity=".38"/><stop offset="1" stop-color="#0A84FF" stop-opacity="0"/></linearGradient></defs>
            <path d="{area}" fill="url(#g)"/>
            <path d="{line}" fill="none" stroke="#0A84FF" stroke-width="4" stroke-linecap="round"/>
            <circle cx="{last[0]-9:.1f}" cy="{last[1]:.1f}" r="7" fill="#fff" stroke="#0A84FF" stroke-width="4"/>
          </svg>
          <div class="axis"><span>min 61</span><span>avg 116</span><span>max 214</span></div>
        </div>

        <div class="card flow">
          <div class="fcard when">
            <div class="ficon blue">{ico('check',24)}</div>
            <div><div class="fl">WHEN</div><div class="ft">A version is <b>Ready for Sale</b></div></div>
          </div>
          <div class="connector"></div>
          <div class="fcard then">
            <div class="ficon green">{ico('bell',22)}</div>
            <div><div class="fl">THEN</div><div class="ft"><span class="pill">App</span> <span class="pill">Version</span> is live!</div></div>
          </div>
        </div>

        <div class="card mini">
          <div class="mhead">{ico('hammer',18)} Build 214</div>
          <div class="bars">{bars}</div>
          <div class="state"><span class="sdot"></span>In Review</div>
        </div>
        '''
    return f'''<!doctype html><html><head><meta charset="utf-8"><style>
    *{{box-sizing:border-box;margin:0}}
    body{{width:1000px;height:700px;overflow:hidden;font-family:Inter,sans-serif;-webkit-font-smoothing:antialiased;color:#fff;
      background:radial-gradient(circle at 12% 8%,#47D6FF 0,transparent 42%),radial-gradient(circle at 95% 100%,#0033D9 0,transparent 55%),
      linear-gradient(140deg,#0A9BFF 0%,#0484FD 40%,#0257F0 100%);position:relative}}
    .wave{{position:absolute;inset:0}}
    .left{{position:absolute;left:64px;top:70px;width:430px}}
    .icon{{width:132px;height:132px;border-radius:30px;box-shadow:0 18px 40px rgba(0,20,90,.45),0 0 0 2px rgba(255,255,255,.35)}}
    .title{{font-size:66px;font-weight:800;letter-spacing:-2px;line-height:1.0;margin-top:30px;text-shadow:0 4px 24px rgba(0,30,120,.25)}}
    .sub{{font-size:21px;line-height:1.38;opacity:.9;margin-top:18px;font-weight:500;width:400px}}
    .tokens{{display:flex;gap:8px;margin-top:34px;width:340px;flex-wrap:wrap}}
    .tok{{display:inline-flex;align-items:center;gap:7px;padding:8px 12px;border-radius:99px;font-size:15px;font-weight:600;
      background:rgba(255,255,255,.18);border:1.5px solid rgba(255,255,255,.4);backdrop-filter:blur(8px)}}
    .tok b{{font-weight:800}}
    .card{{position:absolute;background:#fff;color:#14161C;border-radius:28px;box-shadow:0 30px 60px rgba(0,25,110,.38),0 2px 0 rgba(255,255,255,.6) inset}}
    .insights{{left:540px;top:64px;width:420px;padding:24px 24px 18px;transform:rotate(-2deg)}}
    .chead{{font-size:16px;font-weight:700;color:#6B6E78;display:flex;align-items:center;gap:8px}}
    .dot{{width:10px;height:10px;border-radius:5px;background:#0A84FF}}
    .big{{font-size:44px;font-weight:800;letter-spacing:-1.2px;margin-top:6px}}
    .up{{font-size:18px;color:#1FA851;font-weight:700;letter-spacing:0;vertical-align:middle}}
    .chart{{width:372px;height:150px;display:block;margin-top:8px}}
    .axis{{display:flex;justify-content:space-between;font-size:14px;color:#9A9DA8;font-weight:600;margin-top:8px}}
    .flow{{left:566px;top:400px;width:394px;padding:18px;background:#F4F6FA;transform:rotate(1.5deg)}}
    .fcard{{display:flex;gap:14px;align-items:center;background:#fff;border-radius:18px;padding:14px 16px;box-shadow:0 4px 14px rgba(20,40,90,.10)}}
    .ficon{{width:46px;height:46px;border-radius:14px;display:flex;align-items:center;justify-content:center;color:#fff;flex:none}}
    .blue{{background:linear-gradient(135deg,#2FB4FF,#0A6CFF)}} .green{{background:linear-gradient(135deg,#43D97A,#1FA851)}}
    .fl{{font-size:12px;font-weight:800;letter-spacing:1.2px;color:#9A9DA8}}
    .ft{{font-size:18px;font-weight:600;margin-top:2px}}
    .pill{{display:inline-block;background:#E6F1FF;color:#0A6CFF;border-radius:8px;padding:1px 8px;font-size:16px;font-weight:700}}
    .connector{{width:3px;height:16px;background:#C9D3E3;margin-left:38px}}
    .mini{{left:400px;top:452px;width:170px;padding:16px;transform:rotate(-4deg);z-index:2}}
    .mhead{{display:flex;align-items:center;gap:6px;font-size:15px;font-weight:700;color:#0A6CFF}}
    .bars{{display:flex;align-items:flex-end;gap:5px;height:62px;margin-top:12px}}
    .bar{{flex:1;border-radius:4px;background:linear-gradient(#5AC8FF,#0A84FF)}}
    .state{{margin-top:12px;font-size:14px;font-weight:700;color:#C27200;display:flex;align-items:center;gap:6px}}
    .sdot{{width:9px;height:9px;border-radius:5px;background:#FFA733}}
    .compact{{position:absolute;inset:0;display:flex;align-items:center;justify-content:center;gap:56px}}
    .cicon{{width:330px;height:330px;border-radius:76px;box-shadow:0 30px 60px rgba(0,20,90,.45),0 0 0 4px rgba(255,255,255,.35)}}
    .ctitle{{font-size:112px;font-weight:800;letter-spacing:-3px;line-height:.98}}
    </style></head><body>
    <svg class="wave" viewBox="0 0 1000 700" preserveAspectRatio="none">
      <path d="M0 520 C220 430 420 640 1000 470 L1000 700 L0 700Z" fill="#fff" opacity=".06"/>
      <path d="M0 600 C300 520 600 700 1000 580 L1000 700 L0 700Z" fill="#fff" opacity=".05"/>
      <path d="M-50 140 C250 40 520 260 1050 60" stroke="#fff" stroke-opacity=".10" stroke-width="2" fill="none"/>
    </svg>
    {body}
    </body></html>'''


def device_html(svg):
    return f'''<!doctype html><html><head><style>
    html,body{{margin:0;width:1000px;height:1000px;background:#fff}}
    .wrap{{width:1000px;height:1000px;display:flex;align-items:center;justify-content:center}}
    .wrap svg{{width:640px;height:640px}}
    </style></head><body><div class="wrap">{svg}</div></body></html>'''


def shot(page, html, w, h, out_sizes):
    page.set_viewport_size({'width': w, 'height': h})
    page.set_content(html)
    page.wait_for_timeout(250)
    img = Image.open(io.BytesIO(page.screenshot())).convert('RGB')
    for path, size in out_sizes:
        img.resize(size, Image.LANCZOS).save(path, optimize=True)
        print('wrote', os.path.relpath(path, ROOT), size)


def main():
    with sync_playwright() as p:
        browser = p.chromium.launch()
        page = browser.new_page(device_scale_factor=2)
        img = os.path.join(ROOT, 'assets', 'images')
        shot(page, app_html(), 1000, 700, [(f'{img}/xlarge.png', (1000, 700)), (f'{img}/large.png', (500, 350))])
        shot(page, app_html(compact=True), 1000, 700, [(f'{img}/small.png', (250, 175))])
        for drv in ('asc_app', 'asc_portfolio'):
            d = os.path.join(ROOT, 'drivers', drv, 'assets')
            with open(os.path.join(d, 'icon.svg')) as f:
                svg = f.read()
            shot(page, device_html(svg), 1000, 1000, [(f'{d}/images/xlarge.png', (1000, 1000)),
                                                     (f'{d}/images/large.png', (500, 500)),
                                                     (f'{d}/images/small.png', (75, 75))])
        browser.close()


if __name__ == '__main__':
    main()
