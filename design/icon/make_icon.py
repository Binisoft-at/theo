#!/usr/bin/env python3
"""Generates the Theo app icon: an abstract butler (head, bow tie, tuxedo) whose shirt
front is a bold check mark. Writes SVG sources; render.js turns them into PNGs."""
import os
import sys

OUT = os.path.dirname(os.path.abspath(__file__))

# Palette
AMBER_TOP = "#FFD45E"
AMBER_MID = "#FDB52A"
AMBER_BOTTOM = "#F28A00"
NAVY_TOP = "#24385F"
NAVY_BOTTOM = "#0C1428"


def figure(navy="url(#navy)", accent="#FFFFFF", shadow=True, check_color=None, tie_color=None, ring=None):
    """The butler mark on a 1024 canvas."""
    check_color = check_color or accent
    tie_color = tie_color or accent
    shadow_attr = 'filter="url(#shadow)"' if shadow else ""
    ring_svg = ""
    if ring:
        # A thin HUD-style ring around the head: a nod to JARVIS.
        ring_svg = f'''
  <circle cx="512" cy="282" r="172" fill="none" stroke="{ring}" stroke-width="14" stroke-linecap="round"
          stroke-dasharray="300 60 120 60 400 141" transform="rotate(-120 512 282)" opacity="0.75"/>'''
    return ring_svg + f"""
  <g {shadow_attr}>
    <!-- head -->
    <circle cx="512" cy="282" r="122" fill="{navy}"/>
    <!-- tuxedo shoulders -->
    <path d="M 176 1060 L 176 690 C 176 580 262 492 372 492 L 652 492 C 762 492 848 580 848 690 L 848 1060 Z" fill="{navy}"/>
  </g>
  <!-- shirt front = check mark -->
  <path d="M 352 744 L 466 856 L 704 612" fill="none" stroke="{check_color}" stroke-width="98"
        stroke-linecap="round" stroke-linejoin="round"/>
  <!-- bow tie -->
  <g fill="{tie_color}" stroke="{tie_color}" stroke-width="22" stroke-linejoin="round">
    <path d="M 512 566 L 424 524 L 424 608 Z"/>
    <path d="M 512 566 L 600 524 L 600 608 Z"/>
  </g>
  <rect x="487" y="539" width="50" height="54" rx="17" fill="{tie_color}"/>
  <rect x="497" y="549" width="30" height="34" rx="10" fill="#000000" opacity="0.12"/>
"""


def defs(bg_top, bg_mid, bg_bottom, glow_opacity=0.5, shadow_color="#7A3E00", shadow_opacity=0.35):
    return f"""
  <defs>
    <linearGradient id="bg" x1="0.2" y1="0" x2="0.65" y2="1">
      <stop offset="0" stop-color="{bg_top}"/>
      <stop offset="0.55" stop-color="{bg_mid}"/>
      <stop offset="1" stop-color="{bg_bottom}"/>
    </linearGradient>
    <radialGradient id="glow" cx="0.28" cy="0.08" r="0.8">
      <stop offset="0" stop-color="#FFFFFF" stop-opacity="{glow_opacity}"/>
      <stop offset="0.55" stop-color="#FFFFFF" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="navy" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="{NAVY_TOP}"/>
      <stop offset="1" stop-color="{NAVY_BOTTOM}"/>
    </linearGradient>
    <linearGradient id="amberGlyph" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="{AMBER_TOP}"/>
      <stop offset="1" stop-color="{AMBER_BOTTOM}"/>
    </linearGradient>
    <filter id="shadow" x="-30%" y="-30%" width="160%" height="160%">
      <feDropShadow dx="0" dy="20" stdDeviation="24" flood-color="{shadow_color}" flood-opacity="{shadow_opacity}"/>
    </filter>
  </defs>"""


def light_icon():
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
{defs(AMBER_TOP, AMBER_MID, AMBER_BOTTOM)}
  <rect width="1024" height="1024" fill="url(#bg)"/>
  <rect width="1024" height="1024" fill="url(#glow)"/>
{figure(ring="#FFFFFF")}
</svg>"""


def dark_icon():
    # iOS dark appearance: dark backdrop, amber figure, white accents.
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
{defs("#2A2A2E", "#18181B", "#0B0B0D", glow_opacity=0.12, shadow_color="#000000", shadow_opacity=0.6)}
  <rect width="1024" height="1024" fill="url(#bg)"/>
  <rect width="1024" height="1024" fill="url(#glow)"/>
{figure(navy="url(#amberGlyph)", accent="#FFFFFF", check_color="#16213D", tie_color="#16213D", ring="#FDB52A")}
</svg>"""


def tinted_icon():
    # iOS tinted appearance: grayscale artwork on black, the system applies the tint.
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
{defs("#000000", "#000000", "#000000", glow_opacity=0, shadow_color="#000000", shadow_opacity=0)}
  <rect width="1024" height="1024" fill="#000000"/>
{figure(navy="#E6E6E6", accent="#000000", shadow=False, check_color="#000000", tie_color="#000000", ring="#BBBBBB")}
</svg>"""


def mac_icon():
    # macOS: artwork inside the standard rounded-rect plate (824pt on a 1024 canvas) with a shadow.
    return f"""<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 1024 1024" width="1024" height="1024">
{defs(AMBER_TOP, AMBER_MID, AMBER_BOTTOM)}
  <defs>
    <clipPath id="plate"><rect x="100" y="100" width="824" height="824" rx="185" ry="185"/></clipPath>
    <filter id="plateShadow" x="-20%" y="-20%" width="140%" height="140%">
      <feDropShadow dx="0" dy="12" stdDeviation="14" flood-color="#000000" flood-opacity="0.28"/>
    </filter>
  </defs>
  <rect x="100" y="100" width="824" height="824" rx="185" ry="185" fill="#F5A300" filter="url(#plateShadow)"/>
  <g clip-path="url(#plate)">
    <g transform="translate(100 100) scale(0.8046875)">
      <rect width="1024" height="1024" fill="url(#bg)"/>
      <rect width="1024" height="1024" fill="url(#glow)"/>
{figure(ring="#FFFFFF")}
    </g>
  </g>
  <rect x="100.5" y="100.5" width="823" height="823" rx="185" ry="185" fill="none" stroke="#FFFFFF" stroke-opacity="0.18" stroke-width="2"/>
</svg>"""


def main():
    files = {
        "icon-light.svg": light_icon(),
        "icon-dark.svg": dark_icon(),
        "icon-tinted.svg": tinted_icon(),
        "icon-mac.svg": mac_icon(),
    }
    for name, svg in files.items():
        with open(os.path.join(OUT, name), "w") as f:
            f.write(svg)
        print("wrote", name)


if __name__ == "__main__":
    sys.exit(main())
