# Draws Resources/AppIcon.png (1024x1024). Needs Pillow: pip install pillow
# Usage: python3 scripts/make_icon.py Resources/AppIcon.png
import sys
from PIL import Image, ImageDraw, ImageFilter

out = sys.argv[1]
S = 4                      # draw at 4x, then downscale for smooth edges
N = 1024 * S
def s(v): return int(round(v * S))

# macOS icon grid: 824pt body centred on a 1024 canvas.
x0, y0, x1, y1 = 100, 100, 924, 924
radius = 186

canvas = Image.new("RGBA", (N, N), (0, 0, 0, 0))

# Soft drop shadow.
shadow = Image.new("RGBA", (N, N), (0, 0, 0, 0))
ImageDraw.Draw(shadow).rounded_rectangle([s(x0), s(y0 + 12), s(x1), s(y1 + 12)], s(radius), fill=(0, 0, 0, 90))
canvas = Image.alpha_composite(canvas, shadow.filter(ImageFilter.GaussianBlur(s(14))))

# Sunset gradient body.
top, bottom = (255, 184, 77), (238, 76, 106)
grad = Image.new("RGBA", (N, N))
gd = ImageDraw.Draw(grad)
for y in range(N):
    t = min(max((y - s(y0)) / (s(y1) - s(y0)), 0), 1)
    gd.line([(0, y), (N, y)], fill=tuple(int(a + (b - a) * t) for a, b in zip(top, bottom)) + (255,))
mask = Image.new("L", (N, N), 0)
ImageDraw.Draw(mask).rounded_rectangle([s(x0), s(y0), s(x1), s(y1)], s(radius), fill=255)
body = Image.new("RGBA", (N, N), (0, 0, 0, 0))
body.paste(grad, (0, 0), mask)

# Gentle highlight on the top half.
hl = Image.new("RGBA", (N, N), (0, 0, 0, 0))
hd = ImageDraw.Draw(hl)
for y in range(s(y0), s(512)):
    a = int(38 * (1 - (y - s(y0)) / (s(512) - s(y0))))
    hd.line([(0, y), (N, y)], fill=(255, 255, 255, a))
hl.putalpha(Image.composite(hl.getchannel("A"), Image.new("L", (N, N), 0), mask))
body = Image.alpha_composite(body, hl)
canvas = Image.alpha_composite(canvas, body)

# Five EQ sliders making a "smile" curve: bass and treble up, mids down.
d = ImageDraw.Draw(canvas)
levels = [0.72, 0.48, 0.32, 0.52, 0.78]
xs = [272 + i * 120 for i in range(5)]
track_top, track_bottom = 286, 738
track_w, knob_r = 30, 50
for x, level in zip(xs, levels):
    ky = track_bottom - level * (track_bottom - track_top)
    # Draw on separate layers so the translucent white blends with the gradient.
    for top_y, alpha in ((track_top, 85), (ky, 240)):
        layer = Image.new("RGBA", (N, N), (0, 0, 0, 0))
        ImageDraw.Draw(layer).rounded_rectangle(
            [s(x - track_w / 2), s(top_y), s(x + track_w / 2), s(track_bottom)], s(track_w / 2),
            fill=(255, 255, 255, alpha))
        canvas = Image.alpha_composite(canvas, layer)
    # Knob with a soft shadow.
    ks = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    ImageDraw.Draw(ks).ellipse([s(x - knob_r), s(ky - knob_r + 8), s(x + knob_r), s(ky + knob_r + 8)], fill=(120, 20, 40, 90))
    canvas = Image.alpha_composite(canvas, ks.filter(ImageFilter.GaussianBlur(s(8))))
    d = ImageDraw.Draw(canvas)
    d.ellipse([s(x - knob_r), s(ky - knob_r), s(x + knob_r), s(ky + knob_r)], fill=(255, 255, 255, 255))
    d.ellipse([s(x - 16), s(ky - 16), s(x + 16), s(ky + 16)], fill=(242, 110, 96, 255))

canvas.resize((1024, 1024), Image.LANCZOS).save(out)
print("saved", out)
