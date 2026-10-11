#!/usr/bin/env python3
"""Generate the community-approved school-building icon for Navigator."""
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
SIZE = 512
SCALE = 3
N = SIZE * SCALE
im = Image.new("RGBA", (N, N), (5, 28, 94, 255))
d = ImageDraw.Draw(im)

def p(points):
    return [(round(x * SCALE), round(y * SCALE)) for x, y in points]

navy = (5, 28, 94, 255)
white = (250, 251, 255, 255)
cyan = (30, 211, 220, 255)
gold = (255, 194, 38, 255)

# Deep-blue rounded tile and subtle inset border.
d.rounded_rectangle((0, 0, N - 1, N - 1), radius=104 * SCALE, fill=navy)
d.rounded_rectangle((9*SCALE, 9*SCALE, (SIZE-9)*SCALE, (SIZE-9)*SCALE),
                    radius=96*SCALE, outline=(20, 53, 129, 255), width=2*SCALE)

# Roof, split at the golden central ridge.
d.polygon(p([(120, 151), (211, 109), (211, 126), (120, 168)]), fill=white)
d.polygon(p([(301, 109), (392, 151), (392, 168), (301, 126)]), fill=white)
d.polygon(p([(220, 104), (256, 86), (292, 104), (292, 118), (256, 100), (220, 118)]), fill=gold)

# Side wings and central facade.
d.polygon(p([(54, 224), (147, 190), (147, 365), (55, 365)]), fill=white)
d.polygon(p([(365, 190), (458, 224), (457, 365), (365, 365)]), fill=white)
d.polygon(p([(153, 158), (359, 158), (358, 360), (385, 393),
             (333, 393), (300, 355), (300, 190), (212, 190),
             (212, 355), (179, 393), (127, 393), (154, 360)]), fill=white)

# Main entrance recess and six bright window panes.
d.rectangle((212*SCALE, 190*SCALE, 300*SCALE, 355*SCALE), fill=navy)
for x in (234, 261):
    for y in (229, 262, 295):
        d.rectangle((x*SCALE, y*SCALE, (x+16)*SCALE, (y+27)*SCALE), fill=cyan)

# Symmetric windows in the wings.
for x in (68, 106, 382, 420):
    for y in (246, 292):
        d.rectangle((x*SCALE, y*SCALE, (x+23)*SCALE, (y+32)*SCALE), fill=navy)

# Broad entry steps echo the approved reference image.
d.polygon(p([(216, 354), (296, 354), (307, 365), (205, 365)]), fill=white)
d.polygon(p([(201, 371), (311, 371), (322, 382), (190, 382)]), fill=white)
d.polygon(p([(185, 389), (327, 389), (339, 401), (173, 401)]), fill=white)

im = im.resize((SIZE, SIZE), Image.Resampling.LANCZOS)
assets = ROOT / "assets"
assets.mkdir(exist_ok=True)
im.save(assets / "navigator_icon.png", optimize=True)

sizes = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
for density, size in sizes.items():
    folder = ROOT / "android" / "app" / "src" / "main" / "res" / f"mipmap-{density}"
    folder.mkdir(parents=True, exist_ok=True)
    icon = im.resize((size, size), Image.Resampling.LANCZOS)
    icon.save(folder / "ic_launcher.png", optimize=True)
    icon.save(folder / "ic_launcher_round.png", optimize=True)

print("Generated approved school-building launcher icon.")
