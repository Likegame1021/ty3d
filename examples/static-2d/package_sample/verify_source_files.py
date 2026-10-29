"""Verify all retained sealed source bytes; needs only Python 3 standard library."""
from pathlib import Path
import hashlib
import json

root = Path(__file__).resolve().parents[1]
manifest = json.loads((root / "package_sample/source-file-manifest.json").read_text())
errors = []
for entry in manifest["retained"]:
    path = root / entry["path"]
    if not path.is_file():
        errors.append("Missing: " + entry["path"])
    elif len(path.read_bytes()) != entry["bytes"] or hashlib.sha256(path.read_bytes()).hexdigest() != entry["sha256"]:
        errors.append("Changed: " + entry["path"])
for error in errors:
    print(error)
print("Retained source files:", len(manifest["retained"]), "mismatches:", len(errors))
raise SystemExit(1 if errors else 0)
