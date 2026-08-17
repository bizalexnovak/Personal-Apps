#!/usr/bin/env python3
"""Render the Foob app icon into the asset catalog.

Gold fork and knife on the emerald vignette — the same engraved gradient the
screen titles use, on the same ground the app runs on. Kept as vector source
here rather than a checked-in binary alone, so the colour or the artwork can
be changed without a design tool and re-rendered reproducibly.

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

# The darkest stop of the vignette, and what alpha is flattened against.
GROUND = "#0f2b21"

OUT = Path(__file__).resolve().parent.parent / \
    "Foob/Assets.xcassets/AppIcon.appiconset/icon-1024.png"

# The glyph occupies the middle ~50% of the canvas, so it still reads at 60px
# once iOS has rounded the corners off everything around it.
SVG = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
  <defs>
    <radialGradient id="ground" cx="50%" cy="40%" r="64%">
      <stop offset="0" stop-color="#1b4433"/>
      <stop offset="1" stop-color="{ground}"/>
    </radialGradient>
    <!-- The engraved title gradient, reused so the icon and the app's
         headings are visibly the same metal. -->
    <linearGradient id="gold" gradientUnits="userSpaceOnUse" x1="0" y1="256" x2="0" y2="768">
      <stop offset="0" stop-color="#e3cb96"/>
      <stop offset="0.55" stop-color="#b3925a"/>
      <stop offset="1" stop-color="#7d6238"/>
    </linearGradient>
  </defs>

  <rect width="1024" height="1024" fill="url(#ground)"/>

  <g stroke="url(#gold)" stroke-width="24" stroke-linecap="round" stroke-linejoin="round">
    <!-- fork -->
    <g fill="none">
      <path d="M379 256 V400"/>
      <path d="M413 256 V400"/>
      <path d="M447 256 V400"/>
      <path d="M481 256 V400"/>
      <path d="M379 400 H481"/>
      <path d="M430 400 V768"/>
    </g>
    <!-- knife: slanted tip, blade tapering into the handle -->
    <path d="M570 256 L622 322 V430 L606 462 H588 L570 430 Z" fill="url(#gold)"/>
    <path d="M596 452 V768" fill="none"/>
  </g>
</svg>"""


def svg() -> str:
    return SVG.format(ground=GROUND)


def render(out: Path = OUT) -> None:
    import cairosvg
    from PIL import Image

    png = cairosvg.svg2png(bytestring=svg().encode(),
                           output_width=1024, output_height=1024)
    # Flatten RGBA onto the ground rather than just dropping alpha, so
    # antialiased edges stay clean instead of fringing against black.
    image = Image.open(io.BytesIO(png)).convert("RGBA")
    flat = Image.new("RGB", image.size, GROUND)
    flat.paste(image, mask=image.split()[3])
    out.parent.mkdir(parents=True, exist_ok=True)
    flat.save(out, format="PNG")
    print(f"wrote {out} ({flat.size[0]}x{flat.size[1]} {flat.mode})")


if __name__ == "__main__":
    if "--svg" in sys.argv:
        print(svg())
    else:
        render()
