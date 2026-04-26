#!/usr/bin/env python3
"""Slice 5-level sprite sheets into individual alpha-keyed PNGs."""
from PIL import Image
import os
from collections import deque

CLANS = ['iron-guard', 'ember-hand', 'dawn-watch', 'storm-riders']
SRC_DIR = '/tmp/sprite-sources'
OUT_DIR = '/tmp/wt-sprite-sheets/apps/web/public/bases'
os.makedirs(OUT_DIR, exist_ok=True)


def alpha_key(im, threshold=235):
    """Flood-fill near-white from corners only, leaves interior whites alone."""
    im = im.convert('RGBA')
    px = im.load()
    w, h = im.size
    visited = [[False] * h for _ in range(w)]
    queue = deque()
    for x, y in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]:
        queue.append((x, y))
    while queue:
        x, y = queue.popleft()
        if x < 0 or y < 0 or x >= w or y >= h:
            continue
        if visited[x][y]:
            continue
        r, g, b, a = px[x, y]
        if r < threshold or g < threshold or b < threshold:
            continue
        visited[x][y] = True
        px[x, y] = (r, g, b, 0)
        for dx, dy in [(-1, 0), (1, 0), (0, -1), (0, 1)]:
            queue.append((x + dx, y + dy))
    return im


def crop_and_save(name):
    src = Image.open(f'{SRC_DIR}/{name}-source.png')
    w, h = src.size
    cell_w = w // 5
    print(f'{name}: source {w}x{h}, cell_w={cell_w}')
    for level in range(1, 6):
        cell = src.crop(((level - 1) * cell_w, 0, level * cell_w, h))
        cell = alpha_key(cell)
        bbox = cell.getbbox()
        if bbox:
            cell = cell.crop(bbox)
        cell.thumbnail((128, 128), Image.LANCZOS)
        out_path = f'{OUT_DIR}/{name}-lv{level}.png'
        cell.save(out_path, 'PNG', optimize=True)
        print(f'  lv{level}: {cell.size} -> {out_path}')


for clan in CLANS:
    crop_and_save(clan)

print('done')
