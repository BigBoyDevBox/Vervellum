#!/usr/bin/env python3
"""Renders Vervellum's app icon into Vervellum/Resources/Assets.xcassets.

The mark: a magnifier ring over three "evidence" rules, the middle one struck
through in the accent colour — search plus a verdict, which is what the app does.
Everything is drawn at 8x and downsampled, so the small sizes stay legible
without hand-hinting.

    python3 media-sources/make_appicon.py
"""
import json
import os

from PIL import Image, ImageDraw

SS = 8  # supersample factor
OUT = os.path.join(os.path.dirname(__file__), "..", "Vervellum", "Resources",
                   "Assets.xcassets", "AppIcon.appiconset")

INK = (247, 248, 252, 255)
ACCENT = (255, 138, 76, 255)
TOP = (46, 40, 92)
BOTTOM = (16, 14, 38)


def rounded_mask(size, radius):
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size - 1, size - 1), radius=radius, fill=255)
    return mask


def render(px):
    """Draws one square icon of `px` points at SS× and returns it downsampled."""
    s = px * SS
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))

    # Vertical gradient plate, masked to the macOS-ish squircle radius (~22%).
    plate = Image.new("RGBA", (s, s))
    pd = ImageDraw.Draw(plate)
    for y in range(s):
        t = y / max(1, s - 1)
        pd.line([(0, y), (s, y)], fill=tuple(
            int(TOP[i] + (BOTTOM[i] - TOP[i]) * t) for i in range(3)) + (255,))
    # A soft highlight arc across the top third, so the plate is not flat.
    gloss = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    ImageDraw.Draw(gloss).ellipse(
        (-s * 0.35, -s * 0.95, s * 1.35, s * 0.42), fill=(255, 255, 255, 26))
    plate = Image.alpha_composite(plate, gloss)
    img.paste(plate, (0, 0), rounded_mask(s, int(s * 0.2237)))

    u = s / 100.0  # one "unit" = 1% of the icon edge
    cx, cy, r = 45.0 * u, 45.0 * u, 27.0 * u
    ring_w = 6.6 * u

    # A pane of glass over three evidence rules: the lens is a faint white wash,
    # the rules are cut *out* of the plate colour, and only the verdict rule
    # carries the accent. Drawn on its own layer and clipped to the lens interior
    # so the marks read as contents under the glass, not strokes across it.
    inner = r - ring_w * 0.55
    rules = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    rd = ImageDraw.Draw(rules)
    rd.ellipse((cx - inner, cy - inner, cx + inner, cy + inner), fill=INK[:3] + (30,))
    for y, half, colour, alpha, weight in ((32.0, 16.0, INK, 190, 3.2),
                                           (45.0, 19.5, ACCENT, 255, 5.4),
                                           (58.0, 12.0, INK, 190, 3.2)):
        rd.line([(cx - half * u, y * u), (cx + half * u, y * u)],
                fill=colour[:3] + (alpha,), width=int(round(weight * u)))
    lens = Image.new("L", (s, s), 0)
    ImageDraw.Draw(lens).ellipse((cx - inner, cy - inner, cx + inner, cy + inner), fill=255)
    # Multiply the layer's own alpha by the lens mask, then composite. A plain
    # paste(mask=) would overwrite the plate's alpha and punch a hole in the icon.
    rules.putalpha(Image.composite(rules.getchannel("A"), Image.new("L", (s, s), 0), lens))
    img = Image.alpha_composite(img, rules)

    # The magnifier: ring plus a handle running to the lower-right corner.
    d = ImageDraw.Draw(img)
    w = int(round(ring_w))
    d.ellipse((cx - r, cy - r, cx + r, cy + r), outline=INK, width=w)
    hx0, hy0 = cx + r * 0.707, cy + r * 0.707
    hx1, hy1 = 79.0 * u, 79.0 * u
    d.line([(hx0, hy0), (hx1, hy1)], fill=INK, width=w)
    for (px_, py_) in ((hx0, hy0), (hx1, hy1)):   # round the handle's caps
        d.ellipse((px_ - w / 2, py_ - w / 2, px_ + w / 2, py_ + w / 2), fill=INK)

    return img.resize((px, px), Image.LANCZOS)


def main():
    os.makedirs(OUT, exist_ok=True)
    images = []
    for point in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            name = f"icon_{point}x{point}@{scale}x.png"
            render(point * scale).save(os.path.join(OUT, name))
            images.append({"filename": name, "idiom": "mac",
                           "scale": f"{scale}x", "size": f"{point}x{point}"})
    with open(os.path.join(OUT, "Contents.json"), "w") as f:
        json.dump({"images": images, "info": {"author": "xcode", "version": 1}}, f, indent=2)
        f.write("\n")
    print(f"wrote {len(images)} icons to {os.path.normpath(OUT)}")


if __name__ == "__main__":
    main()
