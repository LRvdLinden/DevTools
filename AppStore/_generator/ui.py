"""DevTools app UI fragments (HTML/CSS) that mirror the SwiftUI design, in English."""
import math

ACCENT = "#2F8BFF"; CYAN = "#3CD3FF"; LIVE = "#34D46A"; REVIEW = "#FFA733"; PENDING = "#9B85FF"; RED = "#FF5A5F"
BG = "#111318"; CARD = "#1F2128"; RAISED = "#292B33"; SEP = "#30323B"; SEC = "#9A9DA8"

APPS = [
    # id, name, bundle, colors, glyph, downloads, delta, state, version, rating
    ("trailhead", "Trailhead", "com.pixelforges.trailhead", ("#1FA85A", "#0E6B4F"), "mountain", 5840, 412, "READY_FOR_SALE", "2.4.1", 4.8),
    ("lumen", "Lumen Notes", "com.pixelforges.lumen", ("#FFC93C", "#F08A00"), "bulb", 3120, 188, "WAITING_FOR_REVIEW", "1.9.0", 4.7),
    ("pets", "Pixel Pets", "com.pixelforges.pets", ("#FF6B95", "#C2185B"), "paw", 1985, -64, "READY_FOR_SALE", "3.1.2", 4.6),
    ("tempo", "Tempo Timer", "com.pixelforges.tempo", ("#FF8A3D", "#E5343A"), "timer", 912, 57, "READY_FOR_DISTRIBUTION", "1.2.0", 4.5),
    ("stellar", "Stellar Sky", "com.pixelforges.stellar", ("#6A5CFF", "#2B1C8F"), "star", 488, 21, "READY_FOR_SALE", "1.0.4", 4.9),
    ("harbor", "Harbor Budget", "com.pixelforges.harbor", ("#14B8E6", "#0A4FE0"), "wave", 135, 9, "PREPARE_FOR_SUBMISSION", "1.0.0", None),
]

STATE = {
    "READY_FOR_SALE": ("Live", LIVE),
    "WAITING_FOR_REVIEW": ("Waiting for Review", REVIEW),
    "IN_REVIEW": ("In Review", REVIEW),
    "READY_FOR_DISTRIBUTION": ("Ready for Distribution", CYAN),
    "PREPARE_FOR_SUBMISSION": ("Prepare for Submission", ACCENT),
    "PENDING_DEVELOPER_RELEASE": ("Pending Release", PENDING),
}

GLYPHS = {
    "mountain": '<path d="M8 40 L22 18 L29 28 L33 22 L42 40 Z" fill="white"/><circle cx="36" cy="14" r="4" fill="white" opacity=".85"/>',
    "bulb": '<circle cx="25" cy="21" r="10" fill="white"/><rect x="20" y="31" width="10" height="7" rx="2" fill="white"/><rect x="21" y="39" width="8" height="3" rx="1.5" fill="white" opacity=".8"/>',
    "paw": '<ellipse cx="25" cy="31" rx="9" ry="7" fill="white"/><circle cx="15" cy="20" r="4" fill="white"/><circle cx="21" cy="14" r="4" fill="white"/><circle cx="29" cy="14" r="4" fill="white"/><circle cx="35" cy="20" r="4" fill="white"/>',
    "timer": '<circle cx="25" cy="27" r="13" fill="none" stroke="white" stroke-width="4"/><path d="M25 27 L25 19" stroke="white" stroke-width="4" stroke-linecap="round"/><rect x="21" y="8" width="8" height="4" rx="2" fill="white"/>',
    "star": '<path d="M25 8 L30 20 L43 21 L33 29 L36 42 L25 35 L14 42 L17 29 L7 21 L20 20 Z" fill="white"/>',
    "wave": '<path d="M6 30 Q14 20 22 30 T38 30 T52 30" stroke="white" stroke-width="5" fill="none" stroke-linecap="round"/><path d="M6 39 Q14 29 22 39 T38 39" stroke="white" stroke-width="5" fill="none" stroke-linecap="round" opacity=".7"/>',
}


def icon(app, size):
    _, name, _, (c1, c2), glyph, *_ = app
    r = size * 0.225
    return (f'<div class="icon" style="width:{size}px;height:{size}px;border-radius:{r}px;'
            f'background:linear-gradient(140deg,{c1},{c2})"><svg viewBox="0 0 50 50" width="{size}" height="{size}">{GLYPHS[glyph]}</svg></div>')


def badge(state, small=False):
    label, color = STATE[state]
    dot = '' if small else f'<i style="background:{color}"></i>'
    return f'<span class="badge" style="color:{color};background:{color}26">{dot}{label}</span>'


def series(n, base, amp, trend, seed):
    out = []
    for i in range(n):
        v = base + trend * i + amp * math.sin(i / 2.3 + seed) + amp * 0.5 * math.sin(i / 0.9 + seed * 2) + (12 if i % 7 in (5, 6) else 0)
        out.append(max(0, round(v)))
    return out


def smooth_path(values, w, h, pad=6, close=False, lo=None, hi=None):
    lo = min(values) if lo is None else lo
    hi = max(values) if hi is None else hi
    span = max(hi - lo, 1)
    pts = [(pad + (w - 2 * pad) * i / (len(values) - 1), pad + (h - 2 * pad) * (1 - (v - lo) / span)) for i, v in enumerate(values)]
    d = f"M{pts[0][0]:.1f},{pts[0][1]:.1f}"
    for i in range(1, len(pts)):
        x0, y0 = pts[i - 1]; x1, y1 = pts[i]
        cx = (x0 + x1) / 2
        d += f" C{cx:.1f},{y0:.1f} {cx:.1f},{y1:.1f} {x1:.1f},{y1:.1f}"
    if close:
        d += f" L{pts[-1][0]:.1f},{h} L{pts[0][0]:.1f},{h} Z"
    return d, pts


def area_chart(values, w, h, color=ACCENT, sel=None, label=None, sub=None, axis=True):
    lo = min(values) * 0.8; hi = max(values) * 1.08
    line, pts = smooth_path(values, w, h, lo=lo, hi=hi)
    area, _ = smooth_path(values, w, h, close=True, lo=lo, hi=hi)
    gid = f"g{abs(hash((w, h, color, len(values)))) % 10**6}"
    grid = ""
    if axis:
        for k in range(4):
            y = 6 + (h - 12) * k / 3
            grid += f'<line x1="0" x2="{w}" y1="{y:.1f}" y2="{y:.1f}" stroke="{SEP}" stroke-dasharray="2 3" stroke-width=".6"/>'
    s = f'<svg class="chart" viewBox="0 0 {w} {h}" width="100%" height="{h}" preserveAspectRatio="none"><defs><linearGradient id="{gid}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{color}" stop-opacity=".42"/><stop offset="1" stop-color="{color}" stop-opacity=".02"/></linearGradient></defs>{grid}<path d="{area}" fill="url(#{gid})"/><path d="{line}" fill="none" stroke="{color}" stroke-width="2.4" stroke-linecap="round"/>'
    bubble = ""
    if sel is not None:
        x, y = pts[sel]
        s += f'<line x1="{x:.1f}" x2="{x:.1f}" y1="0" y2="{h}" stroke="{SEC}" stroke-dasharray="3 3" stroke-width="1"/><circle cx="{x:.1f}" cy="{y:.1f}" r="5" fill="{color}" stroke="{BG}" stroke-width="2"/>'
        left = x / w * 100
        bubble = f'<div class="bubble" style="left:calc({left:.1f}% - 48px)"><b>{label}</b><span>{sub}</span></div>'
    else:
        x, y = pts[-1]
        s += f'<circle cx="{x:.1f}" cy="{y:.1f}" r="3.5" fill="{color}"/>'
    s += "</svg>"
    return f'<div class="chartwrap">{bubble}{s}</div>'


CSS = f"""
*{{box-sizing:border-box;margin:0;padding:0}}
body{{font-family:Inter,'Noto Color Emoji',sans-serif;-webkit-font-smoothing:antialiased;color:#fff}}
.screen{{background:{BG};color:#F2F3F7;width:100%;height:100%;position:relative;overflow:hidden;font-size:15px}}
.status{{position:relative;z-index:5;height:54px;display:flex;align-items:center;justify-content:space-between;padding:14px 32px 0 36px;font-weight:600;font-size:16px}}
.status .r{{display:flex;gap:6px;align-items:center}}
.bat{{width:26px;height:12px;border:1.5px solid #fff;border-radius:4px;position:relative;opacity:.9}}.bat:after{{content:"";position:absolute;inset:1.5px;right:5px;background:#fff;border-radius:1.5px}}
.bars{{display:flex;gap:2px;align-items:flex-end}}.bars i{{width:3px;background:#fff;border-radius:1px}}
.nav{{padding:6px 18px 4px;display:flex;align-items:center;justify-content:space-between}}
.big{{font-size:33px;font-weight:800;letter-spacing:-.5px;padding:2px 18px 10px}}
.navtitle{{font-size:16px;font-weight:600;text-align:center;flex:1}}
.back{{color:{ACCENT};font-size:16px;display:flex;align-items:center;gap:4px;min-width:70px}}
.content{{padding:0 16px 120px;display:flex;flex-direction:column;gap:14px}}
.card{{background:{CARD};border-radius:14px;padding:14px;border:1px solid rgba(255,255,255,.06);box-shadow:0 6px 18px rgba(0,0,0,.25)}}
.grid{{display:grid;grid-template-columns:repeat(auto-fill,minmax(150px,1fr));gap:10px}}
.tile{{background:{CARD};border-radius:13px;padding:11px 12px}}
.tile .t{{font-size:11.5px;color:{SEC};font-weight:500;display:flex;gap:5px;align-items:center}}
.tile .v{{font-size:23px;font-weight:700;margin-top:5px;letter-spacing:-.3px;font-variant-numeric:tabular-nums}}
.tile .f{{font-size:10.5px;color:{SEC};margin-top:3px;font-weight:500}}
.h{{font-size:16px;font-weight:700}}.sub{{font-size:12px;color:{SEC}}}
.row{{display:flex;align-items:center;gap:11px}}
.sp{{flex:1}}
.icon{{display:flex;align-items:center;justify-content:center;flex:none;box-shadow:inset 0 0 0 .5px rgba(255,255,255,.15)}}
.icon svg{{width:62%;height:62%}}
.badge{{font-size:10.5px;font-weight:700;padding:3px 8px;border-radius:99px;display:inline-flex;gap:5px;align-items:center;white-space:nowrap}}
.badge i{{width:6px;height:6px;border-radius:9px;display:inline-block}}
.seg{{display:flex;background:{RAISED};border-radius:9px;padding:2px;margin:10px 0}}
.seg span{{flex:1;text-align:center;font-size:12.5px;font-weight:600;padding:5px 0;color:#ddd}}
.seg span.on{{background:#5A5D66;border-radius:7px;color:#fff;box-shadow:0 2px 4px rgba(0,0,0,.3)}}
.chips{{display:flex;gap:6px;margin-bottom:8px}}
.chip{{font-size:11.5px;font-weight:600;padding:5px 10px;border-radius:99px;background:{RAISED};color:{SEC}}}
.chartwrap{{position:relative;padding-top:6px}}
.bubble{{position:absolute;top:-6px;width:96px;background:rgba(60,62,72,.92);border-radius:9px;padding:5px 0;text-align:center;z-index:2}}
.bubble b{{display:block;font-size:14px}}.bubble span{{font-size:10px;color:{SEC}}}
.mini{{display:flex;margin-top:10px}}.mini div{{flex:1;text-align:center}}.mini b{{display:block;font-size:13.5px}}.mini span{{font-size:10px;color:{SEC}}}
.bar{{height:9px;border-radius:9px;background:rgba(255,255,255,.07);display:flex;overflow:hidden;gap:2px}}
.list .item{{padding:10px 0;border-bottom:1px solid {SEP}}}.list .item:last-child{{border:none}}
.tabbar{{position:absolute;bottom:0;left:0;right:0;height:96px;background:rgba(24,26,32,.94);border-top:1px solid {SEP};display:flex;justify-content:space-around;padding-top:9px;backdrop-filter:blur(20px)}}
.tab{{display:flex;flex-direction:column;align-items:center;gap:3px;font-size:10.5px;font-weight:600;color:#8E9099}}
.tab.on{{color:{ACCENT}}}
.tab svg{{width:26px;height:24px}}
.home{{position:absolute;bottom:8px;left:50%;width:140px;height:5px;margin-left:-70px;border-radius:5px;background:#fff;opacity:.9}}
.field{{background:{RAISED};border-radius:10px;padding:10px 11px;font-size:13.5px;line-height:1.45;color:#EDEEF2;overflow-wrap:anywhere}}
.lbl{{display:flex;justify-content:space-between;font-size:11.5px;color:{SEC};font-weight:600;margin:4px 0 6px}}
.btn{{background:linear-gradient(90deg,#2F6BFF,#21C8F0);border-radius:99px;text-align:center;padding:13px;font-weight:700;font-size:15px;box-shadow:0 6px 18px rgba(33,200,240,.35)}}
.btn2{{background:{ACCENT}22;color:{ACCENT};border-radius:10px;padding:9px 12px;font-weight:600;font-size:13px;display:inline-flex;gap:6px;align-items:center}}
.toggle{{width:46px;height:28px;border-radius:99px;background:{LIVE};position:relative;flex:none}}.toggle:after{{content:"";position:absolute;right:2px;top:2px;width:24px;height:24px;border-radius:99px;background:#fff}}
.toggle.off{{background:#3A3C45}}.toggle.off:after{{right:auto;left:2px}}
.stars{{color:#FFD60A;letter-spacing:1px;font-size:12px}}
.caret{{width:14px;height:14px;color:#666}}
"""

TABS = [("Home", '<path d="M3 11 L12 3 L21 11 V21 H15 V15 H9 V21 H3 Z" fill="currentColor"/>'),
        ("Apps", '<rect x="4" y="4" width="16" height="5" rx="2" fill="currentColor"/><rect x="4" y="10" width="16" height="5" rx="2" fill="currentColor" opacity=".75"/><rect x="4" y="16" width="16" height="5" rx="2" fill="currentColor" opacity=".5"/>'),
        ("TestFlight", '<path d="M2 13 L22 4 L16 21 L12 15 Z" fill="currentColor"/>'),
        ("Insights", '<path d="M3 19 L9 11 L13 15 L21 5" stroke="currentColor" stroke-width="2.6" fill="none" stroke-linecap="round" stroke-linejoin="round"/>'),
        ("Account", '<circle cx="12" cy="12" r="10" fill="currentColor" opacity=".35"/><circle cx="12" cy="9" r="4" fill="currentColor"/><path d="M5 18 C7 14 17 14 19 18" fill="currentColor"/>')]


def status_bar():
    return ('<div class="status"><span>9:41</span><span class="r"><span class="bars"><i style="height:5px"></i><i style="height:7px"></i>'
            '<i style="height:9px"></i><i style="height:11px"></i></span><svg width="17" height="12" viewBox="0 0 17 12"><path d="M8.5 2.5C11 2.5 13.2 3.5 14.9 5.1L16 4C14 2 11.4.9 8.5.9S3 2 1 4L2.1 5.1C3.8 3.5 6 2.5 8.5 2.5ZM8.5 5.8c1.6 0 3 .6 4.1 1.6l1.1-1.1C12.3 5 10.5 4.2 8.5 4.2S4.7 5 3.3 6.3l1.1 1.1c1.1-1 2.5-1.6 4.1-1.6ZM8.5 9c.7 0 1.3.3 1.8.7L8.5 11.5 6.7 9.7c.5-.4 1.1-.7 1.8-.7Z" fill="white"/></svg><span class="bat"></span></span></div>')


def tabbar(active):
    out = '<div class="tabbar">'
    for name, svg in TABS:
        out += f'<div class="tab{" on" if name == active else ""}"><svg viewBox="0 0 24 24">{svg}</svg>{name}</div>'
    return out + '</div><div class="home"></div>'


def tile(title, value, color, foot="", icon_svg=""):
    return f'<div class="tile"><div class="t">{icon_svg}{title}</div><div class="v" style="color:{color}">{value}</div>{f"<div class=f>{foot}</div>" if foot else ""}</div>'


def trend_card(values, title="Downloads & proceeds", total="12,480", sel=None, label="", sub="", height=170, metric="Installs"):
    chips = "".join(f'<span class="chip" style="{"background:#2F8BFF2e;color:#5DA5FF" if m == metric else ""}">{m}</span>' for m in ["Installs", "New downloads", "Updates", "Proceeds"])
    return f'''<div class="card"><div class="row"><div><div class="h">{title}</div><div class="sub">Last 30 days</div></div><div class="sp"></div><div style="font-size:21px;font-weight:800;color:{ACCENT}">{total}</div></div>
<div class="seg"><span>7d</span><span class="on">30d</span><span>90d</span><span>1y</span></div><div class="chips">{chips}</div>
{area_chart(values, 360, height, ACCENT, sel, label, sub)}
<div class="mini"><div><b>212</b><span>Minimum</span></div><div><b>416</b><span>Avg / day</span></div><div><b>688</b><span>Maximum</span></div></div></div>'''


def dashboard(wide=False):
    vals = series(30, 330, 70, 7, 1.2)
    tiles = (tile("Installs", "12,480", ACCENT, "Last 30 days") + tile("Proceeds", "€3,214", LIVE, "1,204 in-app purchases") +
             tile("Live", "4", LIVE, "of 6 apps") + tile("In review", "1", REVIEW) + tile("Updates", "8,902", PENDING) + tile("Avg. rating", "4.7 ★", "#FFD60A"))
    bars = ""
    mx = APPS[0][5]
    for a in APPS[:5]:
        w1 = a[5] * .78 / mx * 100; w2 = a[5] * .22 / mx * 100
        bars += f'''<div class="row" style="margin-bottom:12px">{icon(a, 30)}<div style="flex:1"><div class="row" style="margin-bottom:5px"><span style="font-size:13.5px;font-weight:600">{a[1]}</span><div class="sp"></div><b style="font-size:13.5px">{a[5]:,}</b></div>
<div class="bar"><div style="width:{w1:.0f}%;background:{ACCENT}"></div><div style="width:{w2:.0f}%;background:{CYAN}"></div></div></div></div>'''
    head = f'''<div class="row" style="padding:0 2px"><img src="logo.png" style="width:44px;height:44px"><div><div style="font-size:19px;font-weight:700">Good afternoon</div><div class="sub">PixelForges · updated just now</div></div></div>'''
    attention = f'''<div class="card" style="background:#FFA73318;border-color:#FFA73330"><div class="h" style="color:{REVIEW};margin-bottom:10px">⚠︎ Attention needed</div>
<div class="row">{icon(APPS[1], 30)}<div><div style="font-size:13.5px;font-weight:600">Lumen Notes</div><div class="sub">Version 1.9.0 is with App Review</div></div><div class="sp"></div>{badge("WAITING_FOR_REVIEW", True)}</div>
<div class="row" style="margin-top:10px">{icon(APPS[3], 30)}<div><div style="font-size:13.5px;font-weight:600">Tempo Timer</div><div class="sub">Version 1.2.0 is about to go live</div></div><div class="sp"></div>{badge("READY_FOR_DISTRIBUTION", True)}</div></div>'''
    body = f'''{head}<div class="grid">{tiles}</div>{trend_card(vals, sel=22, label="688", sub="Sat, Oct 17")}
<div class="card"><div class="h">Downloads per app</div><div class="sub" style="margin-bottom:12px">Last 30 days</div>{bars}</div>{attention}'''
    return body


def app_row(a, dl=True):
    label = f'<span style="color:{LIVE}">Live {a[8]}</span>' if a[7] == "READY_FOR_SALE" else f'<span style="color:{STATE[a[7]][1]}">{STATE[a[7]][0]} {a[8]}</span>'
    right = f'<div style="text-align:right"><b style="font-size:16px">{a[5]/1000:.1f}K</b><div class="sub" style="font-size:10px">downloads</div></div>' if dl else badge(a[7], True)
    return f'<div class="row item">{icon(a, 46)}<div style="flex:1"><div style="font-weight:700;font-size:15px">{a[1]}</div><div style="font-size:12px;font-weight:600;margin-top:2px">{label}</div></div>{right}</div>'


def app_detail():
    a = APPS[0]
    vals = series(30, 170, 40, 3, 0.4)
    countries = [("🇺🇸", "United States", 1840), ("🇳🇱", "Netherlands", 1210), ("🇩🇪", "Germany", 868), ("🇬🇧", "United Kingdom", 642), ("🇫🇷", "France", 395)]
    clist = "".join(f'''<div class="row" style="margin-bottom:11px"><span style="font-size:21px">{f}</span><div style="flex:1"><div class="row" style="margin-bottom:4px"><span style="font-size:13.5px">{n}</span><div class="sp"></div><b style="font-size:13.5px">{v:,}</b></div><div style="height:5px;width:{v/1840*100:.0f}%;background:{ACCENT};border-radius:5px"></div></div></div>''' for f, n, v in countries)
    return f'''<div class="card"><div class="row">{icon(a, 84)}<div><div style="font-size:23px;font-weight:800">{a[1]}</div><div class="sub" style="font-family:monospace;margin:3px 0 7px">{a[2]}</div>
<div class="row" style="gap:6px"><span class="badge" style="color:{LIVE};background:{LIVE}26">Live 2.4.1</span>{badge("WAITING_FOR_REVIEW")}</div>
<div class="sub" style="margin-top:7px">📱 iOS &nbsp; 🖥 macOS</div></div></div></div>
<div class="grid">{tile("Installs", "5,840", ACCENT, "Last 30 days")}{tile("Proceeds", "€1,482", LIVE)}{tile("Rating", "4.8 ★", "#FFD60A", "2,316 ratings")}{tile("Latest build", "318", CYAN, "2 hours ago")}</div>
{trend_card(vals, title="Downloads", total="5,840", sel=24, label="241", sub="Mon, Oct 19")}
<div class="card"><div class="h" style="margin-bottom:12px">Top countries</div>{clist}</div>'''


def version_editor():
    return f'''<div class="card"><div class="row">{icon(APPS[0], 52)}<div><div style="font-size:20px;font-weight:800">iOS 2.5.0</div>{badge("PREPARE_FOR_SUBMISSION")}</div></div></div>
<div class="card"><div class="lbl"><span>WHAT’S NEW IN THIS VERSION</span><span>214/4000</span></div>
<div class="field" style="min-height:150px">• New: offline trail maps for 40+ national parks<br>• Live elevation profile while you hike<br>• Apple Watch: start and pause tracking from your wrist<br>• Faster sync and many small fixes<span style="border-left:2px solid {ACCENT};margin-left:1px"></span></div>
<div class="btn2" style="margin-top:12px">⧉ Copy to all 11 other languages</div></div>
<div class="card"><div class="lbl"><span>PROMOTIONAL TEXT</span><span>98/170</span></div><div class="field">Autumn is here 🍂 Discover 1,200 new trails with offline maps — now free for the first 7 days.</div>
<div class="lbl" style="margin-top:12px"><span>KEYWORDS</span><span>84/100</span></div><div class="field">hiking,trails,maps,offline,outdoor,walking,gps,elevation,nature,national park</div></div>
<div class="card"><div class="h" style="margin-bottom:10px">Build</div><div class="row">{icon(APPS[0], 38)}<div><div style="font-weight:700">2.5.0 (318)</div><div class="sub">Uploaded 2 hours ago</div></div><div class="sp"></div><span class="badge" style="color:{LIVE};background:{LIVE}26">Ready</span></div></div>
<div class="btn">✈︎ Submit for Review</div>'''


def testflight():
    groups = [("Internal Team", "Internal", True), ("Beta Testers", "External · 248 testers", True), ("Press & Friends", "External · public link", False)]
    g = "".join(f'<div class="row item"><div style="flex:1"><div style="font-weight:600">{n}</div><div class="sub">{s}</div></div><div class="toggle{"" if on else " off"}"></div></div>' for n, s, on in groups)
    builds = "".join(f'''<div class="row item">{icon(APPS[0], 36)}<div style="flex:1"><div style="font-weight:700">{v}</div><div class="sub">{t}</div></div><span class="badge" style="color:{c};background:{c}26">{l}</span></div>''' for v, t, l, c in
                     [("2.5.0 (318)", "2 hours ago · expires in 89 d", "In Testing", LIVE), ("2.5.0 (317)", "Yesterday · expires in 88 d", "Ready to Test", ACCENT), ("2.4.1 (309)", "Oct 2 · expires in 70 d", "Beta Approved", LIVE)])
    return f'''<div class="card"><div class="row">{icon(APPS[0], 52)}<div><div style="font-size:20px;font-weight:800">2.5.0 (318)</div><span class="badge" style="color:{LIVE};background:{LIVE}26"><i style="background:{LIVE}"></i>In Testing</span></div></div></div>
<div class="card"><div class="lbl"><span>🇺🇸 WHAT TO TEST</span><span>128/4000</span></div><div class="field" style="min-height:84px">Please test the new offline maps: download a park, switch on Airplane Mode and start a hike. Report anything that looks off!</div></div>
<div class="card list"><div class="h" style="margin-bottom:4px">Test groups</div>{g}</div>
<div class="card"><div class="row"><span style="flex:1;font-weight:600">Notify testers automatically</span><div class="toggle"></div></div></div>
<div class="card list"><div class="h" style="margin-bottom:4px">Recent builds</div>{builds}</div>'''


def reviews():
    dist = [(5, 82), (4, 12), (3, 3), (2, 1), (1, 2)]
    bars = "".join(f'<div class="row" style="gap:8px;margin:3px 0"><span style="font-size:11px;width:22px;color:{SEC}">{s}★</span><div style="height:8px;width:{p}%;background:#FFD60A;border-radius:4px"></div></div>' for s, p in dist)
    revs = [("Finally a great trail app", "Offline maps work perfectly in the mountains. The elevation profile is a game changer!", "alpine_anna", "🇩🇪", 5, "Thank you Anna! More parks are coming in the next update 🙌"),
            ("Love it, one request", "Could you add a dark map style for night hikes? Otherwise perfect.", "nightowl", "🇳🇱", 4, None)]
    rv = ""
    for t, b, n, f, s, reply in revs:
        rep = f'<div style="background:{ACCENT}18;border-radius:10px;padding:10px;margin-top:9px"><div style="font-size:11.5px;font-weight:700;color:{ACCENT}">↩︎ Your reply</div><div style="font-size:13px;margin-top:3px">{reply}</div></div>' if reply else ""
        rv += f'''<div class="card"><div class="row"><span class="stars">{"★"*s}{"☆"*(5-s)}</span><div class="sp"></div><span class="sub">{f} Oct {20 if s==5 else 21}</span></div>
<div style="font-weight:700;margin-top:7px">{t}</div><div style="font-size:13.5px;margin-top:4px;line-height:1.4">{b}</div><div class="sub" style="margin-top:5px">{n}</div>{rep}
<div class="btn2" style="margin-top:10px">↩︎ {"Edit reply" if reply else "Reply"}</div></div>'''
    return f'''<div class="card"><div class="row" style="gap:18px"><div style="text-align:center"><div style="font-size:46px;font-weight:800">4.7</div><div class="sub">2,316 reviews</div></div><div style="flex:1">{bars}</div></div>
<div class="seg"><span class="on">All</span><span>5★</span><span>4★</span><span>3★</span><span>2★</span><span>1★</span></div></div>{rv}'''


def insights():
    lines = ""
    colors = [ACCENT, CYAN, PENDING, REVIEW, LIVE]
    allv = []
    for i, a in enumerate(APPS[:4]):
        vals = series(30, a[5] / 30, a[5] / 30 * .25, a[6] / 300, i * 1.3)
        allv.append(vals)
    hi = max(max(v) for v in allv); lo = 0
    for i, vals in enumerate(allv):
        d, _ = smooth_path(vals, 360, 200, lo=lo, hi=hi)
        lines += f'<path d="{d}" fill="none" stroke="{colors[i]}" stroke-width="2.2"/>'
    legend = "".join(f'<span style="display:inline-flex;align-items:center;gap:5px;margin-right:12px;font-size:11.5px;color:{SEC}"><i style="width:9px;height:9px;border-radius:9px;background:{colors[i]}"></i>{a[1]}</span>' for i, a in enumerate(APPS[:4]))
    donut = '<svg width="118" height="118" viewBox="0 0 42 42">'
    off = 25
    for p, c in [(64, ACCENT), (24, CYAN), (9, PENDING), (3, REVIEW)]:
        donut += f'<circle cx="21" cy="21" r="15.9" fill="none" stroke="{c}" stroke-width="5.5" stroke-dasharray="{p-1} {101-p}" stroke-dashoffset="{off}"/>'
        off -= p
    donut += "</svg>"
    dev = "".join(f'<div class="row" style="gap:8px;margin:5px 0;font-size:12.5px"><i style="width:9px;height:9px;border-radius:9px;background:{c}"></i>{n}<div class="sp"></div><span style="color:{SEC}">{p}%</span></div>' for n, p, c in [("iPhone", 64, ACCENT), ("iPad", 24, CYAN), ("Mac", 9, PENDING), ("Apple Watch", 3, REVIEW)])
    return f'''<div class="grid">{tile("Installs", "12,480", ACCENT, "▲ 1,036 vs first half", )}{tile("New downloads", "9,736", CYAN)}{tile("Updates", "8,902", PENDING)}{tile("Proceeds", "€3,214", LIVE)}</div>
<div class="card"><div class="h">Installs per app</div><div class="sub" style="margin-bottom:10px">Top 4 · last 30 days</div><svg viewBox="0 0 360 200" width="100%" height="200" preserveAspectRatio="none">{lines}</svg><div style="margin-top:8px">{legend}</div></div>
<div class="card"><div class="h" style="margin-bottom:10px">Devices</div><div class="row" style="gap:18px">{donut}<div style="flex:1">{dev}</div></div></div>'''


def apps_list():
    return '<div class="card list" style="padding:4px 14px">' + "".join(app_row(a) for a in APPS) + '</div>'


def phone_screen(title, body, active="Home", back=None, large=True, nav_title=None):
    nav = ""
    if back:
        nav = f'<div class="nav"><span class="back">‹ {back}</span><span class="navtitle">{nav_title or ""}</span><span style="min-width:70px;text-align:right;color:{ACCENT};font-size:20px">⋯</span></div>'
    big = f'<div class="big">{title}</div>' if large and title else ""
    return f'<div class="screen">{status_bar()}{nav}{big}<div class="content">{body}</div>{tabbar(active)}</div>'
