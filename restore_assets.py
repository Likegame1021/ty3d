#!/usr/bin/env python3
"""Restore the two losslessly split assets offline, before importing Godot.

Python 3 standard library only. Existing differing files are never overwritten.
All input pieces and full-file hashes are checked before installing any asset.
Pieces are retained. Run from any working directory: python3 restore_assets.py
"""
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import sys
import tempfile


def bounded_path(root, name, prefix):
    if not isinstance(name, str) or not name or '\\' in name or ':' in name:
        raise ValueError('Invalid asset path')
    relative = PurePosixPath(name)
    if relative.is_absolute() or '..' in relative.parts or relative.parts[:len(prefix)] != prefix:
        raise ValueError('Asset path is outside its allowed directory: ' + name)
    result = root
    for component in relative.parts:
        result = result / component
        if result.is_symlink():
            raise ValueError('Symbolic links are not allowed: ' + name)
    return result


def checked_bytes(path, entry):
    size = entry.get('size')
    digest = entry.get('sha256')
    if type(size) is not int or size < 0 or not isinstance(digest, str) or not re.fullmatch('[0-9a-f]{64}', digest):
        raise ValueError('Invalid size or SHA-256 declaration')
    if path.is_symlink() or not path.is_file():
        raise ValueError('Missing regular file: ' + str(path))
    if path.stat().st_size != size:
        raise ValueError('Size mismatch: ' + str(path))
    raw = path.read_bytes()
    if hashlib.sha256(raw).hexdigest() != digest:
        raise ValueError('SHA-256 mismatch: ' + str(path))
    return raw


def restore(root):
    manifest_path = bounded_path(root, '_asset_parts/manifest.json', ('_asset_parts',))
    manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
    if not isinstance(manifest, dict) or manifest.get('version') != 1:
        raise ValueError('Unsupported asset manifest')
    assets = manifest.get('assets')
    if not isinstance(assets, list) or not assets:
        raise ValueError('Asset manifest must contain assets')
    pending = []
    destinations = set()
    for entry in assets:
        if not isinstance(entry, dict):
            raise ValueError('Invalid asset entry')
        destination = bounded_path(root, entry.get('path'), ('game', 'assets'))
        if destination in destinations:
            raise ValueError('Duplicate asset destination')
        destinations.add(destination)
        if destination.exists():
            checked_bytes(destination, entry)
            print('Already verified: ' + entry['path'])
            continue
        parts = entry.get('parts')
        if not isinstance(parts, list) or not parts:
            raise ValueError('Asset has no pieces')
        pieces = []
        for part in parts:
            if not isinstance(part, dict):
                raise ValueError('Invalid piece entry')
            path = bounded_path(root, part.get('path'), ('_asset_parts',))
            pieces.append(checked_bytes(path, part))
        raw = b''.join(pieces)
        if type(entry.get('size')) is not int or len(raw) != entry['size'] or hashlib.sha256(raw).hexdigest() != entry.get('sha256'):
            raise ValueError('Reconstructed asset size or SHA-256 mismatch: ' + entry['path'])
        pending.append((destination, raw, entry))
    # No destination is written until every required input passed preflight.
    for destination, raw, entry in pending:
        destination.parent.mkdir(parents=True, exist_ok=True)
        temporary = None
        try:
            with tempfile.NamedTemporaryFile(prefix='.restore-assets-', suffix='.tmp', dir=destination.parent, delete=False) as stream:
                temporary = Path(stream.name)
                stream.write(raw)
                stream.flush()
                os.fsync(stream.fileno())
            checked_bytes(temporary, entry)
            # Atomic, no-clobber installation. NTFS and ordinary Unix filesystems
            # support hard links; no existing destination is replaced, even if
            # another invocation created it after preflight.
            try:
                os.link(temporary, destination)
            except FileExistsError:
                checked_bytes(destination, entry)
            print('Restored and verified: ' + entry['path'])
        finally:
            if temporary is not None:
                temporary.unlink(missing_ok=True)
    print('Assets ready. You can now import game/project.godot.')


if __name__ == '__main__':
    try:
        restore(Path(__file__).resolve().parent)
    except (OSError, ValueError, TypeError) as error:
        print('Asset restoration stopped: ' + str(error), file=sys.stderr)
        sys.exit(1)
