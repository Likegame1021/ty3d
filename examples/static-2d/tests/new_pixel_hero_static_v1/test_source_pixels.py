"""Read-only raster audit. Never crops, edits, redraws or saves any image."""
import hashlib
import json
from pathlib import Path
import numpy as np
from PIL import Image
from scipy.ndimage import label, find_objects

ROOT = Path(__file__).resolve().parents[2]
profile_path = ROOT / "profiles/new_pixel_hero_static_v1.json"
assert profile_path.exists(), "New measured 2D atlas profile missing"
p = json.loads(profile_path.read_text())
source = ROOT / p["source"].removeprefix("res://")
assert hashlib.sha256(source.read_bytes()).hexdigest() == p["source_sha256"] == "3daffa7b35471ee21ee3750e71600fc0f03e2a75eda2c82c7051de27bf64058a"
im = Image.open(source)
assert im.mode == "RGBA" and im.size == (1536, 1024)
alpha = np.asarray(im)[:, :, 3]
labels, count = label(alpha >= 128)
assert count == 8, f"Expected exactly 8 retained silhouettes, got {count}"
objects = find_objects(labels)
seen = set()
for d in p["directions"]:
    x,y,w,h = d["region"]
    ids = set(np.unique(labels[y:y+h,x:x+w])) - {0}
    assert len(ids) == 1, f"{d['name']} includes missing/neighboring silhouette"
    component = ids.pop()
    assert component not in seen, "Direction reuses another silhouette"
    seen.add(component)
    sy,sx = objects[component-1]
    assert [sx.start,sy.start,sx.stop,sy.stop] == d["visible_bbox"]
    assert x < sx.start and y < sy.start and x+w > sx.stop and y+h > sy.stop
    assert int((labels[y:y+h,x:x+w] == component).sum()) == int((labels == component).sum()), "A retained body or stick pixel is clipped"
    _,shoe_x = np.where(labels[sy.stop-35:sy.stop] == component)
    anchor_global = [(int(shoe_x.min())+int(shoe_x.max())+1)/2, sy.stop]
    assert d["feet_anchor"] == [anchor_global[0]-x, anchor_global[1]-y], "Anchor is not derived from this direction's actual shoes"
assert sum(int((labels == i).sum()) for i in seen) == 531507
assert p["directions"][7]["region"][0] < 1152, "SW stick would be cut by blind 4x2 slicing"
assert p["frame_count"] == 1 and p["art_type"] == "new_2d_static_eight_directions"
print("PASS: 8 distinct complete silhouettes, 531507 retained pixels, exact original PNG hash, independent shoe anchors, no raster edits")
