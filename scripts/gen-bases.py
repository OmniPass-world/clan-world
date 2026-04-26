#!/usr/bin/env python3
"""Generate 4 base sprites (96x96 PNG with transparency) for ClanWorld clans.

Each sprite is a distinctive pixel-art structure tinted to the clan's color.
Drawn deterministically with PIL — no external API calls.
"""
from PIL import Image, ImageDraw
import os

OUT = os.path.join(os.path.dirname(__file__), "..", "apps", "web", "public", "bases")
os.makedirs(OUT, exist_ok=True)

SIZE = 96


def base_canvas():
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


def shadow(d):
    # Soft elliptical ground shadow
    d.ellipse([18, 80, 78, 92], fill=(0, 0, 0, 120))


def darken(rgb, amt=0.55):
    return tuple(int(c * amt) for c in rgb)


def lighten(rgb, amt=1.4):
    return tuple(min(255, int(c * amt)) for c in rgb)


def stroke_rect(d, box, fill, outline=(0, 0, 0, 255)):
    d.rectangle(box, fill=fill, outline=outline)


def iron_guard():
    """Red banner tower — squat stone keep with red banner on top."""
    color = (204, 68, 34)  # 0xCC4422 ish — actually iron guard is red 0xcc... wait check
    # Iron Guard color in MOCK_CLANS = 0x4488cc (blue)? Let me re-read...
    # MOCK_CLANS: iron=0x4488cc (blue), ember=0xcc4422 (red), dawn=0xccaa22 (yellow), storm=0x44aacc (cyan)
    # User says: Iron Guard (red), Ember Hand (orange/red), Dawn Watch (yellow), Storm Riders (blue)
    # User's color description differs from code. Use the CODE colors so it stays consistent.
    # Iron Guard = blue (0x4488cc). Render: stone tower with blue banner.
    color = (0x44, 0x88, 0xcc)
    img, d = base_canvas()
    shadow(d)
    # Stone keep base
    stroke_rect(d, [28, 40, 68, 82], (140, 130, 110, 255))
    # Crenellations
    for x in range(28, 68, 8):
        stroke_rect(d, [x, 36, x + 4, 42], (140, 130, 110, 255))
    # Door
    stroke_rect(d, [44, 64, 52, 82], (60, 40, 30, 255))
    # Windows
    stroke_rect(d, [34, 50, 38, 56], (40, 30, 20, 255))
    stroke_rect(d, [58, 50, 62, 56], (40, 30, 20, 255))
    # Tall flagpole
    d.line([(48, 36), (48, 8)], fill=(70, 50, 30, 255), width=2)
    # Banner
    d.polygon([(48, 10), (76, 16), (48, 22)], fill=color, outline=(0, 0, 0, 255))
    img.save(os.path.join(OUT, "iron-guard.png"))


def ember_hand():
    """Orange longhouse — broad wood roof with orange flame banner."""
    color = (0xcc, 0x44, 0x22)  # red/orange
    img, d = base_canvas()
    shadow(d)
    # Longhouse body
    stroke_rect(d, [16, 50, 80, 84], (110, 75, 45, 255))
    # Wood plank stripes
    for y in range(56, 84, 6):
        d.line([(16, y), (80, y)], fill=(70, 45, 25, 255), width=1)
    # Roof (triangle)
    d.polygon([(12, 52), (48, 24), (84, 52)], fill=color, outline=(0, 0, 0, 255))
    # Roof shadow stripe
    d.polygon([(12, 52), (48, 28), (84, 52), (48, 50)], fill=darken(color, 0.7))
    # Door
    stroke_rect(d, [42, 66, 54, 84], (50, 30, 20, 255))
    # Flame finial on roof peak
    d.polygon([(48, 24), (44, 14), (48, 18), (52, 14), (48, 8)], fill=(255, 180, 60, 255), outline=(120, 60, 0, 255))
    img.save(os.path.join(OUT, "ember-hand.png"))


def dawn_watch():
    """Yellow watchtower — tall slim tower with sun banner."""
    color = (0xcc, 0xaa, 0x22)  # gold/yellow
    img, d = base_canvas()
    shadow(d)
    # Tall tower shaft
    stroke_rect(d, [38, 30, 58, 84], (180, 165, 130, 255))
    # Brick lines
    for y in range(36, 84, 8):
        d.line([(38, y), (58, y)], fill=(120, 105, 75, 255), width=1)
    # Top observation deck (wider)
    stroke_rect(d, [32, 22, 64, 32], (160, 145, 110, 255))
    # Crenellations on deck
    for x in range(32, 64, 6):
        stroke_rect(d, [x, 18, x + 3, 22], (160, 145, 110, 255))
    # Window slit
    stroke_rect(d, [45, 50, 51, 60], (40, 30, 20, 255))
    # Sun finial banner
    d.line([(48, 22), (48, 6)], fill=(70, 50, 30, 255), width=2)
    d.ellipse([42, 4, 54, 16], fill=color, outline=(0, 0, 0, 255))
    # Sun rays
    for dx, dy in [(0, -6), (6, 0), (-6, 0), (4, -4), (-4, -4), (4, 4), (-4, 4)]:
        d.line([(48, 10), (48 + dx, 10 + dy)], fill=color, width=1)
    img.save(os.path.join(OUT, "dawn-watch.png"))


def storm_riders():
    """Cyan dockmaster's keep — a hut on a stone pier with wave banner."""
    color = (0x44, 0xaa, 0xcc)  # cyan
    img, d = base_canvas()
    shadow(d)
    # Stone pier base
    stroke_rect(d, [12, 70, 84, 84], (130, 130, 145, 255))
    # Pier blocks
    for x in range(20, 84, 12):
        d.line([(x, 70), (x, 84)], fill=(80, 80, 95, 255), width=1)
    # Hut body
    stroke_rect(d, [28, 44, 68, 70], (110, 90, 70, 255))
    # Plank lines
    for x in range(34, 68, 6):
        d.line([(x, 44), (x, 70)], fill=(70, 55, 40, 255), width=1)
    # Roof (slanted)
    d.polygon([(24, 46), (48, 26), (72, 46)], fill=darken(color, 0.6), outline=(0, 0, 0, 255))
    # Door
    stroke_rect(d, [44, 56, 52, 70], (40, 30, 20, 255))
    # Flagpole + wave banner
    d.line([(72, 44), (72, 18)], fill=(70, 50, 30, 255), width=2)
    # Wavy banner — use small triangle stack
    d.polygon([(72, 20), (90, 24), (78, 28), (90, 32), (72, 34)], fill=color, outline=(0, 0, 0, 255))
    img.save(os.path.join(OUT, "storm-riders.png"))


if __name__ == "__main__":
    iron_guard()
    ember_hand()
    dawn_watch()
    storm_riders()
    print("OK")
    for f in ["iron-guard", "ember-hand", "dawn-watch", "storm-riders"]:
        print(f, os.path.getsize(os.path.join(OUT, f + ".png")))
