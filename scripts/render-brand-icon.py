#!/usr/bin/env python3
"""Render TechPie's launcher icon sources on macOS with sips and Pillow."""

import json
from pathlib import Path
import subprocess
import tempfile

from PIL import Image, ImageColor, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
BRAND = ROOT / "docs/brand-icon"
ICONS = ROOT / "assets/icon"


def resize(image, size):
    return image.resize((size, size), Image.Resampling.LANCZOS)


def gradient(width, height, palette):
    top = ImageColor.getrgb(palette["top"]["$value"]["hex"])
    bottom = ImageColor.getrgb(palette["bottom"]["$value"]["hex"])
    strip = Image.new("RGB", (1, height))
    strip.putdata([
        tuple(round(a + (b - a) * row / (height - 1)) for a, b in zip(top, bottom))
        for row in range(height)
    ])
    return strip.resize((width, height))


def macos_fallback(square):
    # Legacy macOS bitmap icons have a centered 824px tile on a 1024px canvas.
    tile_size = 824
    scale = 4
    mask_size = tile_size * scale
    mask = Image.new("L", (mask_size, mask_size))
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, mask_size - 1, mask_size - 1), radius=184 * scale, fill=255
    )
    tile = resize(square, tile_size).convert("RGBA")
    tile.putalpha(resize(mask, tile_size))
    icon = Image.new("RGBA", square.size)
    inset = (square.width - tile_size) // 2
    icon.paste(tile, (inset, inset))
    return icon


def main():
    tokens = json.loads((BRAND / "brand-icon.tokens.json").read_text())
    spec = tokens["brand"]["appIcon"]
    with tempfile.TemporaryDirectory() as directory:
        raster = Path(directory) / "mark.png"
        subprocess.run(
            ["sips", "-s", "format", "png", str(BRAND / "01-TechPie-P.svg"),
             "--out", str(raster)],
            check=True, stdout=subprocess.DEVNULL,
        )
        mark = Image.open(raster).convert("RGBA")

    # Only the alpha represents the P in Android's themed icon mode.
    monochrome = Image.new("RGBA", mark.size, "white")
    monochrome.putalpha(mark.getchannel("A"))
    for name, layer in (
        ("icon_foreground.png", mark),
        ("icon_monochrome.png", monochrome),
    ):
        destination = ICONS / name
        if destination.is_symlink():
            destination.unlink()
        layer.save(destination)

    palette = spec["color"]["default"]
    background = gradient(*mark.size, palette)
    square = Image.alpha_composite(background.convert("RGBA"), mark).convert("RGB")
    square.save(ICONS / "icon.png")
    macos_fallback(square).save(ICONS / "icon_macos.png")
    # A one-pixel strip expands to a full-bleed Android gradient per density.
    gradient(1, mark.height, palette).save(ICONS / "icon_background.png")

    square.save(ROOT / "ios/TechPieWatch/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
    ohos_media = ROOT / "ohos/AppScope/resources/base/media"
    background.save(ohos_media / "background.png")
    mark.save(ohos_media / "foreground.png")
    resize(square, 500).save(ROOT / "ohos/entry/src/main/resources/base/media/icon.png")
    resize(square, 216).save(ICONS / "appgallery-216.png")


if __name__ == "__main__":
    main()
