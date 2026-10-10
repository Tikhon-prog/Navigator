#!/usr/bin/env python3
"""Generate a school-first launcher icon for Navigator in Android density buckets."""
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
SIZE, SCALE = 512, 3
N = SIZE * SCALE
im = Image.new("RGBA", (N, N), (8, 23, 64, 255))
d = ImageDraw.Draw(im)

def p(points):
    return [(int(x*SCALE), int(y*SCALE)) for x, y in points]

navy = (8, 23, 64, 255)
white = (248, 250, 255, 255)
cyan = (41, 218, 205, 255)
gold = (255, 198, 48, 255)
d.rounded_rectangle((0, 0, N-1, N-1), radius=96*SCALE, fill=(8, 23, 64, 255))
d.rounded_rectangle((12*SCALE, 12*SCALE, N-12*SCALE, N-12*SCALE), radius=84*SCALE, outline=(35, 71, 143, 255), width=2*SCALE)

# A bold, architectural Cyrillic П silhouette: central portal with two wings.
# The overall silhouette reads as both the school's initial and a school building.
d.polygon(p([(92, 366), (92, 184), (150, 184), (150, 126), (362, 126), (362, 184), (420, 184), (420, 366), (350, 366), (350, 216), (310, 216), (310, 366)]), fill=white)
d.rectangle((202*SCALE, 210*SCALE, 310*SCALE, 366*SCALE), fill=navy)
# Cyan entrance panels, simple and legible at small icon sizes.
d.rounded_rectangle((219*SCALE, 235*SCALE, 246*SCALE, 320*SCALE), radius=5*SCALE, fill=cyan)
d.rounded_rectangle((260*SCALE, 235*SCALE, 287*SCALE, 320*SCALE), radius=5*SCALE, fill=cyan)
# Symmetric windows in the wings.
for x in (112, 154, 354, 396):
    d.rounded_rectangle((x*SCALE, 238*SCALE, (x+18)*SCALE, 286*SCALE), radius=4*SCALE, fill=navy)
    d.rounded_rectangle((x*SCALE, 300*SCALE, (x+18)*SCALE, 334*SCALE), radius=4*SCALE, fill=navy)
# Restrained golden roof accent, not a navigation pin.
d.polygon(p([(222, 126), (256, 92), (290, 126)]), fill=gold)
# A few clean entry steps anchor the school motif.
d.rounded_rectangle((190*SCALE, 378*SCALE, 322*SCALE, 390*SCALE), radius=5*SCALE, fill=white)
d.rounded_rectangle((208*SCALE, 398*SCALE, 304*SCALE, 409*SCALE), radius=5*SCALE, fill=(78, 111, 178, 255))

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
print("Generated school-first П icon: assets/navigator_icon.png and Android launcher images.")
