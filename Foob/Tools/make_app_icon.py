#!/usr/bin/env python3
"""Render the Foob app icon into the asset catalog.

The icon is a spiral-bound notebook with a fork, spoon and knife on it —
white line art on mint. Kept as vector source here rather than a checked-in
binary alone, so the colour or the artwork can be changed without a design
tool and re-rendered reproducibly.

    pip install cairosvg pillow
    python3 Tools/make_app_icon.py           # writes the asset catalog PNG
    python3 Tools/make_app_icon.py --svg     # dumps the SVG to stdout

Note the PNG is flattened to RGB on the way out: App Store Connect rejects
app icons containing an alpha channel ("Invalid Image - The app icon can't
be transparent nor contain an alpha channel"), and cairosvg emits RGBA.
"""
import io
import sys
from pathlib import Path

BACKGROUND = "#9CC5B0"  # mint
FOREGROUND = "#FFFFFF"

OUT = Path(__file__).resolve().parent.parent / \
    "Foob/Assets.xcassets/AppIcon.appiconset/icon-1024.png"

SVG = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
  <rect width="1024" height="1024" fill="{bg}"/>

  <!-- notebook body -->
  <rect x="310" y="212" width="440" height="600" rx="52"
        fill="none" stroke="{fg}" stroke-width="16"/>

  <!-- spiral binding: capsules straddling the left edge -->
  <g fill="none" stroke="{fg}" stroke-width="14">
    <rect x="262" y="290" width="96" height="32" rx="16"/>
    <rect x="262" y="372" width="96" height="32" rx="16"/>
    <rect x="262" y="454" width="96" height="32" rx="16"/>
    <rect x="262" y="536" width="96" height="32" rx="16"/>
    <rect x="262" y="618" width="96" height="32" rx="16"/>
    <rect x="262" y="700" width="96" height="32" rx="16"/>
  </g>

  <g stroke="{fg}" stroke-width="17" stroke-linecap="round" stroke-linejoin="round">
    <!-- fork -->
    <g fill="none">
      <path d="M406 300 V410"/>
      <path d="M429 300 V410"/>
      <path d="M452 300 V410"/>
      <path d="M475 300 V410"/>
      <path d="M406 410 H475"/>
      <path d="M440 410 V730"/>
    </g>
    <!-- spoon -->
    <ellipse cx="530" cy="352" rx="42" ry="60" fill="{fg}"/>
    <path d="M530 412 V730" fill="none"/>
    <!-- knife: slanted tip, blade tapering into the handle -->
    <path d="M604 302 L636 350 V416 L625 436 H615 L604 416 Z" fill="{fg}"/>
    <path d="M620 430 V730" fill="none"/>
  </g>
</svg>"""


def svg() -> str:
    return SVG.format(bg=BACKGROUND, fg=FOREGROUND)


def render(out: Path = OUT) -> None:
    import cairosvg
    from PIL import Image

    png = cairosvg.svg2png(bytestring=svg().encode(),
                           output_width=1024, output_height=1024)
    # Flatten RGBA onto the background rather than just dropping alpha, so
    # antialiased edges stay clean instead of fringing against black.
    image = Image.open(io.BytesIO(png)).convert("RGBA")
    flat = Image.new("RGB", image.size, BACKGROUND)
    flat.paste(image, mask=image.split()[3])
    out.parent.mkdir(parents=True, exist_ok=True)
    flat.save(out, format="PNG")
    print(f"wrote {out} ({flat.size[0]}x{flat.size[1]} {flat.mode})")


if __name__ == "__main__":
    if "--svg" in sys.argv:
        print(svg())
    else:
        render()
