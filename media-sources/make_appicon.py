#!/usr/bin/env python3
"""Exports Vervellum's app icon from media-sources/icon.png for every platform.

The artwork is a full-bleed square with no transparency. Each platform wants a
different shape cut out of it:

* macOS gets the rounded square (corner radius 22.37% of the edge — the Big Sur
  grid) on the full canvas, matching the sibling apps, at the ten sizes the
  asset catalog lists.
* Linux gets the same rounded square, at the sizes the hicolor icon theme
  indexes, under packaging/icons. The 48 and 64 pixel sizes matter there: GNOME's
  app grid and Shell pick them first and scale a neighbour only when they are
  missing.

The mask is drawn at 4× and downsampled so the corner edge is anti-aliased at
every size; a mask drawn at 16 pixels would be a staircase.

    python3 media-sources/make_appicon.py
"""
import json
import os

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
SOURCE = os.path.join(HERE, "icon.png")
APPICONSET = os.path.join(HERE, "..", "Vervellum", "Resources", "Assets.xcassets", "AppIcon.appiconset")
HICOLOR = os.path.join(HERE, "..", "packaging", "icons", "hicolor")
LINUX_ICON_NAME = "ch.lkmc.Vervellum.png"

MASTER = 1024
CORNER = 0.2237          # of the edge; the macOS icon grid's radius
SUPERSAMPLE = 4
LINUX_SIZES = (16, 24, 32, 48, 64, 128, 256, 512)


def square(image):
    """Centre-crops to a square, in case the artwork is ever re-exported off-square."""
    w, h = image.size
    if w == h:
        return image
    edge = min(w, h)
    left, top = (w - edge) // 2, (h - edge) // 2
    return image.crop((left, top, left + edge, top + edge))


def rounded_mask(size):
    big = size * SUPERSAMPLE
    mask = Image.new("L", (big, big), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, big - 1, big - 1), radius=int(round(big * CORNER)), fill=255)
    return mask.resize((size, size), Image.LANCZOS)


def build_master():
    """The artwork at MASTER pixels with the platform shape cut out."""
    art = square(Image.open(SOURCE).convert("RGB")).resize((MASTER, MASTER), Image.LANCZOS)
    master = art.convert("RGBA")
    master.putalpha(rounded_mask(MASTER))
    return master


def export(master, size):
    # Resizing the masked master rather than re-masking per size keeps the alpha
    # edge and the artwork resampled by the same filter, so nothing fringes.
    return master if size == MASTER else master.resize((size, size), Image.LANCZOS)


def write_appiconset(master):
    os.makedirs(APPICONSET, exist_ok=True)
    images = []
    for point in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            name = f"icon_{point}x{point}@{scale}x.png"
            export(master, point * scale).save(os.path.join(APPICONSET, name), optimize=True)
            images.append({"filename": name, "idiom": "mac",
                           "scale": f"{scale}x", "size": f"{point}x{point}"})
    with open(os.path.join(APPICONSET, "Contents.json"), "w") as f:
        json.dump({"images": images, "info": {"author": "xcode", "version": 1}}, f, indent=2)
        f.write("\n")
    return len(images)


def write_hicolor(master):
    for size in LINUX_SIZES:
        directory = os.path.join(HICOLOR, f"{size}x{size}", "apps")
        os.makedirs(directory, exist_ok=True)
        export(master, size).save(os.path.join(directory, LINUX_ICON_NAME), optimize=True)
    return len(LINUX_SIZES)


def main():
    master = build_master()
    print(f"wrote {write_appiconset(master)} icons to {os.path.normpath(APPICONSET)}")
    print(f"wrote {write_hicolor(master)} icons to {os.path.normpath(HICOLOR)}")


if __name__ == "__main__":
    main()
