#!/usr/bin/env python3
"""Crop horizontal sprite sheets into 5 progression stages.

Input PNGs are RGB with a faux-transparency checkerboard (alternating
near-white pixels ~254 and ~242). We detect content as anything sufficiently
different from both background shades.
"""
from __future__ import annotations

import sys
import argparse
from collections import Counter
from pathlib import Path

import numpy as np
from PIL import Image


def compute_content_metrics(arr: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    a = arr.astype(int)
    R, G, B = a[:, :, 0], a[:, :, 1], a[:, :, 2]
    saturation = np.maximum(np.maximum(np.abs(R - G), np.abs(G - B)), np.abs(R - B))
    brightness = (R + G + B) / 3
    return saturation, brightness


def content_mask(arr: np.ndarray, *, sat_max: int = 3, bright_min: int = 225) -> np.ndarray:
    """Boolean mask: True where pixel is sprite content.

    The faux-transparency checkerboard is near-grayscale (R≈G≈B) and bright
    (>=~225). A pixel is treated as content if EITHER it's coloured (any
    channel-pair differs by more than sat_max) OR it's darker than bright_min.
    This robustly distinguishes off-white cream sprites from the bg checker
    while still catching dark stone, lava, etc.
    """
    saturation, brightness = compute_content_metrics(arr)
    is_bg = (brightness >= bright_min) & (saturation <= sat_max)
    return ~is_bg


def find_stage_bboxes(
    path: Path,
    num_stages: int = 5,
    min_col_pixels: int = 5,
    min_run_width: int = 50,
) -> tuple[list[tuple[int, int, int, int]], tuple[int, int], int, Image.Image]:
    img = Image.open(path).convert("RGB")
    arr = np.array(img)
    mask = content_mask(arr)
    col_count = mask.sum(axis=0)
    col_has = col_count >= min_col_pixels

    raw_runs = []
    in_run = False
    rs = None
    for x, m in enumerate(col_has):
        if m and not in_run:
            rs = x
            in_run = True
        elif not m and in_run:
            raw_runs.append((rs, x - 1))
            in_run = False
    if in_run:
        raw_runs.append((rs, len(col_has) - 1))

    def merge(runs, gap):
        if not runs:
            return []
        out = [list(runs[0])]
        for s, e in runs[1:]:
            if s - out[-1][1] <= gap:
                out[-1][1] = e
            else:
                out.append([s, e])
        return [tuple(r) for r in out]

    chosen_gap = None
    chosen_bb = None
    for g in (1, 5, 10, 15, 20, 25, 30):
        m = merge(raw_runs, g)
        m = [r for r in m if r[1] - r[0] + 1 >= min_run_width]
        if len(m) == num_stages:
            chosen_gap = g
            chosen_bb = m
            break

    if chosen_bb is None:
        raise SystemExit(
            f"FAIL {path.name}: expected {num_stages} stages, raw_runs={len(raw_runs)}; "
            "none of the gap merges + width filter produced exactly 5"
        )

    full_bboxes = []
    for x1, x2 in chosen_bb:
        col_slice = mask[:, x1 : x2 + 1]
        rows_with_content = col_slice.any(axis=1)
        ys = np.where(rows_with_content)[0]
        y1, y2 = int(ys.min()), int(ys.max())
        full_bboxes.append((int(x1), y1, int(x2), y2))

    return full_bboxes, img.size, chosen_gap, img


DEFAULT_SOURCE_DIR = Path("/home/claude/.claude/channels/telegram/inbox")
DEFAULT_OUT_DIR = Path("/tmp/wt-base-sprites/apps/web/public/bases")

# Mapping decided via vision inspection (see PR description).
MAPPING = [
    ("1777422652093-AgADWgcAAv0tiEc.PNG", "iron-guard", False),       # dark stone, navy roofs
    ("1777422653564-AgADWwcAAv0tiEc.PNG", "white-cathedral", True),   # white cream cathedral
    ("1777422655301-AgADXAcAAv0tiEc.PNG", "ember-hand", False),       # lava forge
    ("1777422657773-AgADXQcAAv0tiEc.PNG", "purple-gothic", True),     # purple crystal gothic
    ("1777422659967-AgADXgcAAv0tiEc.PNG", "verdant-forest", True),    # green treehouse
    ("1777422660632-AgADXwcAAv0tiEc.PNG", "dawn-watch", False),       # gold royal palace
    ("1777422661542-AgADYAcAAv0tiEc.PNG", "storm-riders", False),     # naval blue water/docks
    ("1777422662177-AgADYQcAAv0tiEc.PNG", "crimson-red", True),       # red flags war camp
]


def main(source_dir: Path, out_dir: Path, dry_run: bool = False) -> None:
    future_dir = out_dir / "future"
    out_dir.mkdir(parents=True, exist_ok=True)
    future_dir.mkdir(parents=True, exist_ok=True)

    pad = 4

    print(f"{'Source':<46} {'OutBase':<18} {'Future':<7} {'Stages':<7} {'Gap'}")
    print("-" * 96)
    for src_name, base_name, is_future in MAPPING:
        src = source_dir / src_name
        bboxes, size, gt, img = find_stage_bboxes(src)
        print(f"{src_name:<46} {base_name:<18} {str(is_future):<7} {len(bboxes):<7} {gt}")
        for i, (x1, y1, x2, y2) in enumerate(bboxes, 1):
            print(f"    lv{i}: x=[{x1},{x2}] (w={x2-x1+1}) y=[{y1},{y2}] (h={y2-y1+1})")

        if dry_run:
            continue

        target_dir = future_dir if is_future else out_dir

        # Convert the checkerboard background to true alpha transparency.
        # The checker is bright (>=225) and near-grayscale; sprites are
        # either coloured or darker. We compute a soft alpha based on how
        # much a pixel deviates from "bright neutral gray".
        rgb_arr = np.array(img)
        saturation, brightness = compute_content_metrics(rgb_arr)
        # Two factors that drive opacity:
        #   - colour saturation (any sat>=3 means non-bg)
        #   - darkness below 225 (each step below adds opacity)
        sat_score = np.clip((saturation - 2) * 32, 0, 255)
        dark_score = np.clip((225 - brightness) * 4, 0, 255)
        alpha = np.maximum(sat_score, dark_score).astype(np.uint8)
        rgba_arr = np.dstack([rgb_arr, alpha])
        rgba_img = Image.fromarray(rgba_arr, "RGBA")

        crops = []
        for i, (x1, y1, x2, y2) in enumerate(bboxes, 1):
            px1 = max(0, x1 - pad)
            py1 = max(0, y1 - pad)
            px2 = min(size[0], x2 + 1 + pad)
            py2 = min(size[1], y2 + 1 + pad)
            crop = rgba_img.crop((px1, py1, px2, py2))
            out = target_dir / f"{base_name}-lv{i}.png"
            crop.save(out, "PNG", optimize=True)
            crops.append(crop)

        # Default sprite = mid progression
        default_out = target_dir / f"{base_name}.png"
        crops[len(crops) // 2].save(default_out, "PNG", optimize=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", default=DEFAULT_SOURCE_DIR, type=Path)
    parser.add_argument("--out", default=DEFAULT_OUT_DIR, type=Path)
    parser.add_argument("--dry", action="store_true")
    args = parser.parse_args()
    main(source_dir=args.source, out_dir=args.out, dry_run=args.dry)
