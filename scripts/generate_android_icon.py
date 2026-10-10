#!/usr/bin/env python3
"""Generate Navigator's Android launcher icon in all density buckets."""
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
SIZE = 512
SCALE = 3
N = SIZE * SCALE
im = Image.new("RGBA", (N, N), (8, 24, 64, 255))
d = ImageDraw.Draw(im)

def pts(points):
    return [(int(x*SCALE), int(y*SCALE)) for x, y in points]

# Rounded navy tile, with a subtle blue inset glow.
d.rounded_rectangle((0, 0, N-1, N-1), radius=92*SCALE, fill=(9, 25, 67, 255))
d.rounded_rectangle((12*SCALE, 12*SCALE, N-12*SCALE, N-12*SCALE), radius=82*SCALE, outline=(35, 66, 129, 255), width=2*SCALE)

# School silhouette.
white = (246, 249, 255, 255)
navy = (10, 27, 70, 255)
d.polygon(pts([(92, 228), (256, 139), (420, 228), (420, 360), (92, 360)]), fill=white)
d.polygon(pts([(66, 232), (256, 126), (446, 232), (423, 252), (256, 160), (89, 252)]), fill=white)
# Main entrance and windows.
d.rectangle((221*SCALE, 253*SCALE, 291*SCALE, 360*SCALE), fill=navy)
d.rectangle((233*SCALE, 265*SCALE, 254*SCALE, 310*SCALE), fill=white)
d.rectangle((260*SCALE, 265*SCALE, 280*SCALE, 310*SCALE), fill=white)
for x, y in [(123, 258), (161, 258), (326, 258), (364, 258)]:
    d.rounded_rectangle((x*SCALE, y*SCALE, (x+24)*SCALE, (y+34)*SCALE), radius=4*SCALE, fill=navy)
# Flag.
d.line(pts([(256, 128), (256, 76)]), fill=(255, 202, 50, 255), width=6*SCALE)
d.polygon(pts([(258, 78), (305, 90), (258, 105)]), fill=(255, 202, 50, 255))
# Navigation route.
teal = (32, 219, 199, 255)
d.line(pts([(184, 391), (234, 391), (274, 407), (317, 407), (347, 424), (392, 424)]), fill=teal, width=13*SCALE, joint="curve")
d.ellipse((374*SCALE, 406*SCALE, 410*SCALE, 442*SCALE), fill=teal)
# Location pin on the left.
yellow = (255, 197, 43, 255)
d.ellipse((98*SCALE, 350*SCALE, 154*SCALE, 406*SCALE), fill=yellow)
d.polygon(pts([(105, 391), (147, 391), (126, 431)]), fill=yellow)
d.ellipse((113*SCALE, 365*SCALE, 139*SCALE, 391*SCALE), fill=navy)

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
print("Generated Navigator icon: assets/navigator_icon.png and 10 Android launcher images.")
