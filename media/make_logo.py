# Generates media/logo.svg. The "GEAR SCALE" lettering is Cinzel Black (SIL Open Font
# License 1.1, https://github.com/NDISCOVER/Cinzel), converted to outlines so the
# SVG needs no font installed.
#
# Usage: pip install fonttools brotli
#        python3 media/make_logo.py path/to/cinzel-latin-900-normal.woff media/logo.svg
# Then render the PNGs (512/256/64) from the SVG with any SVG renderer.
import math, sys
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen

font = TTFont(sys.argv[1]); out = sys.argv[2]
gs = font.getGlyphSet(); cmap = font.getBestCmap(); upem = font['head'].unitsPerEm

def text_path(s, size, cx, baseline, tracking=0):
    scale = size / upem
    names = [cmap[ord(c)] for c in s]
    width = sum(gs[n].width for n in names) + tracking * (len(names) - 1)
    x = cx / scale - width / 2
    pen = SVGPathPen(gs)
    for n in names:
        tp = TransformPen(pen, (scale, 0, 0, -scale, x * scale, baseline))
        gs[n].draw(tp)
        x += gs[n].width + tracking
    return pen.getCommands()

W = 512
cx, cy = 256, 186

# light rays
rays = []
for i in range(16):
    a = i * 2 * math.pi / 16 + math.pi / 16
    a1, a2 = a - 0.09, a + 0.09
    R = 300
    rays.append(f"M{cx},{cy} L{cx+R*math.cos(a1):.1f},{cy+R*math.sin(a1):.1f} L{cx+R*math.cos(a2):.1f},{cy+R*math.sin(a2):.1f}Z")

# cog outline: 14 teeth
teeth, ro, ri = 14, 128, 112
pts = []
for i in range(teeth):
    base = i * 2 * math.pi / teeth
    step = 2 * math.pi / teeth
    for frac, r in ((0.0, ri), (0.12, ro), (0.42, ro), (0.54, ri)):
        a = base + frac * step
        pts.append(f"{cx+r*math.cos(a):.1f},{cy+r*math.sin(a):.1f}")
cog = "M" + " L".join(pts) + "Z"

# balance scale
bl, br, by = cx - 70, cx + 70, cy - 46        # beam ends
pan_y = cy + 22
def pan(x):
    return f"M{x-34},{pan_y} Q{x},{pan_y+34} {x+34},{pan_y} Z"
scale_parts = f'''
  <g stroke="#5c3a08" stroke-width="4" stroke-linejoin="round" stroke-linecap="round">
    <line x1="{bl}" y1="{by}" x2="{bl-30}" y2="{pan_y}" stroke="#f2c94c" stroke-width="3"/>
    <line x1="{bl}" y1="{by}" x2="{bl+30}" y2="{pan_y}" stroke="#f2c94c" stroke-width="3"/>
    <line x1="{br}" y1="{by}" x2="{br-30}" y2="{pan_y}" stroke="#f2c94c" stroke-width="3"/>
    <line x1="{br}" y1="{by}" x2="{br+30}" y2="{pan_y}" stroke="#f2c94c" stroke-width="3"/>
    <path d="{pan(bl)}" fill="url(#gold)"/>
    <path d="{pan(br)}" fill="url(#gold)"/>
    <rect x="{cx-7}" y="{by-6}" width="14" height="{pan_y+40-(by-6)}" rx="3" fill="url(#gold)"/>
    <rect x="{bl-6}" y="{by-6}" width="{br-bl+12}" height="12" rx="6" fill="url(#gold)"/>
    <path d="M{cx-38},{pan_y+52} L{cx+38},{pan_y+52} L{cx+24},{pan_y+36} L{cx-24},{pan_y+36} Z" fill="url(#gold)"/>
    <circle cx="{cx}" cy="{by-14}" r="11" fill="url(#gold)"/>
  </g>'''

title = text_path("GEAR SCALE", 58, 256, 384, tracking=40)

# three axis bars: DPS (red), Defense (blue), Sustain (green)
bars = ""
bw, gap, base_y = 40, 16, 472
heights = [62, 46, 32]
colors = [("#ff7a6b", "#c0281c"), ("#7fb6ff", "#2659c9"), ("#8be38f", "#2a9c3a")]
x0 = 256 - (3 * bw + 2 * gap) / 2
for i, (h, (c1, c2)) in enumerate(zip(heights, colors)):
    x = x0 + i * (bw + gap)
    bars += f'''
  <linearGradient id="b{i}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{c1}"/><stop offset="1" stop-color="{c2}"/></linearGradient>
  <rect x="{x:.1f}" y="{base_y-h}" width="{bw}" height="{h}" rx="5" fill="url(#b{i})" stroke="url(#goldEdge)" stroke-width="4"/>
  <rect x="{x+4:.1f}" y="{base_y-h+4}" width="{bw-8}" height="{h/2-4:.1f}" rx="3" fill="#ffffff" opacity="0.2"/>'''

svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {W}" width="{W}" height="{W}">
  <defs>
    <radialGradient id="bg" cx="50%" cy="38%" r="70%">
      <stop offset="0" stop-color="#1d3a66"/>
      <stop offset="0.6" stop-color="#0f1f3d"/>
      <stop offset="1" stop-color="#070d1c"/>
    </radialGradient>
    <linearGradient id="gold" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#fff2b0"/>
      <stop offset="0.45" stop-color="#f2c94c"/>
      <stop offset="1" stop-color="#a86b12"/>
    </linearGradient>
    <linearGradient id="goldEdge" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#ffe9a0"/>
      <stop offset="0.5" stop-color="#c9932b"/>
      <stop offset="1" stop-color="#7a4b0c"/>
    </linearGradient>
    <radialGradient id="rayFade" cx="{cx}" cy="{cy}" r="260" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#ffe08a" stop-opacity="0.55"/>
      <stop offset="1" stop-color="#ffe08a" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="medal" cx="50%" cy="35%" r="65%">
      <stop offset="0" stop-color="#244a80"/>
      <stop offset="1" stop-color="#0b1730"/>
    </radialGradient>
    <clipPath id="frame"><rect x="8" y="8" width="496" height="496" rx="88"/></clipPath>
  </defs>

  <g clip-path="url(#frame)">
    <rect width="{W}" height="{W}" fill="url(#bg)"/>
    <path d="{' '.join(rays)}" fill="url(#rayFade)"/>
  </g>
  <rect x="8" y="8" width="496" height="496" rx="88" fill="none" stroke="url(#goldEdge)" stroke-width="10"/>
  <rect x="22" y="22" width="468" height="468" rx="76" fill="none" stroke="#c9932b" stroke-opacity="0.45" stroke-width="2"/>

  <!-- cog medallion with balance scale -->
  <path d="{cog}" fill="url(#goldEdge)" stroke="#5c3a08" stroke-width="3" stroke-linejoin="round"/>
  <circle cx="{cx}" cy="{cy}" r="100" fill="url(#medal)" stroke="#5c3a08" stroke-width="3"/>
  <circle cx="{cx}" cy="{cy}" r="92" fill="none" stroke="#f2c94c" stroke-opacity="0.5" stroke-width="2"/>
  {scale_parts}

  <!-- GEAR SCALE -->
  <path d="{title}" fill="#06101f" transform="translate(0,4)" opacity="0.7"/>
  <path d="{title}" fill="url(#gold)" stroke="#4a2c06" stroke-width="3" stroke-linejoin="round" paint-order="stroke"/>

  <!-- DPS / Defense / Sustain bars -->
  {bars}
</svg>
'''
open(out, 'w').write(svg)
print("wrote", out)
