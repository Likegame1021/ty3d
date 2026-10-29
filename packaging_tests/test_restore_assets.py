"""Offline packaging tests: python3 -m unittest discover -s packaging_tests -v."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parents[1] / 'restore_assets.py'

class RestoreTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.parts = self.root / '_asset_parts'
        self.parts.mkdir()
        self.destination = self.root / 'game/assets/example.glb'
        self.destination.parent.mkdir(parents=True)
        self.expected = b'first piece\x00second piece'
        self.assets = [self.asset('game/assets/example.glb', [b'first piece\x00', b'second piece'])]
        self.save_manifest()
        if SOURCE.exists(): shutil.copyfile(SOURCE, self.root / 'restore_assets.py')

    def asset(self, destination, pieces):
        entries = []
        for piece in pieces:
            name = hashlib.sha256(piece).hexdigest() + '.part'
            (self.parts / name).write_bytes(piece)
            entries.append({'path': '_asset_parts/' + name, 'size': len(piece), 'sha256': hashlib.sha256(piece).hexdigest()})
        whole = b''.join(pieces)
        return {'path': destination, 'size': len(whole), 'sha256': hashlib.sha256(whole).hexdigest(), 'parts': entries}

    def save_manifest(self):
        (self.parts / 'manifest.json').write_text(json.dumps({'version': 1, 'assets': self.assets}))

    def run_restore(self):
        return subprocess.run([sys.executable, str(self.root / 'restore_assets.py')], cwd=self.root.parent, capture_output=True, text=True)

    def assert_refused(self):
        result = self.run_restore()
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertFalse(self.destination.exists())
        self.assertEqual(list(self.root.rglob(".restore-assets-*.tmp")), [])

    def test_exact_bytes_and_parts_retained(self):
        result = self.run_restore()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.destination.read_bytes(), self.expected)
        self.assertTrue(all((self.root / p['path']).exists() for p in self.assets[0]['parts']))

    def test_idempotent_existing_valid_file_is_not_rewritten(self):
        self.destination.write_bytes(self.expected)
        before = self.destination.stat().st_mtime_ns
        result = self.run_restore()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.destination.stat().st_mtime_ns, before)
        self.assertEqual(self.destination.read_bytes(), self.expected)

    def test_corrupt_existing_file_is_not_overwritten(self):
        self.destination.write_bytes(b'user-edited')
        self.assertNotEqual(self.run_restore().returncode, 0)
        self.assertEqual(self.destination.read_bytes(), b'user-edited')

    def test_missing_part_refused(self):
        (self.root / self.assets[0]['parts'][0]['path']).unlink()
        self.assert_refused()

    def test_corrupt_part_refused(self):
        (self.root / self.assets[0]['parts'][0]['path']).write_bytes(b'wrong')
        self.assert_refused()

    def test_wrong_order_and_final_hash_refused(self):
        self.assets[0]['parts'].reverse()
        self.save_manifest()
        self.assert_refused()

    def test_destination_traversal_refused(self):
        self.assets[0]['path'] = '../escape.glb'
        self.save_manifest()
        self.assert_refused()
        self.assertFalse((self.root.parent / 'escape.glb').exists())

    def test_part_traversal_refused(self):
        self.assets[0]['parts'][0]['path'] = '../escape.part'
        self.save_manifest()
        self.assert_refused()

    def test_symlink_destination_parent_refused(self):
        self.destination.parent.rmdir()
        outside = self.root / 'outside'
        outside.mkdir()
        self.destination.parent.symlink_to(outside, target_is_directory=True)
        self.assert_refused()
        self.assertFalse((outside / 'example.glb').exists())

    def test_symlink_part_refused(self):
        part = self.root / self.assets[0]['parts'][0]['path']
        raw = part.read_bytes()
        part.unlink()
        target = self.root / 'external.part'
        target.write_bytes(raw)
        part.symlink_to(target)
        self.assert_refused()

    def test_all_inputs_preflight_before_install(self):
        self.assets.append(self.asset('game/assets/second.glb', [b'next']))
        (self.root / self.assets[1]['parts'][0]['path']).unlink()
        self.save_manifest()
        self.assert_refused()

    def test_absolute_destination_refused(self):
        self.assets[0]['path'] = str(self.root / 'absolute.glb')
        self.save_manifest()
        self.assert_refused()

    def test_absolute_part_refused(self):
        self.assets[0]['parts'][0]['path'] = str(self.root / self.assets[0]['parts'][0]['path'])
        self.save_manifest()
        self.assert_refused()

    def test_same_size_corruption_refused(self):
        part = self.root / self.assets[0]['parts'][0]['path']
        part.write_bytes(b'X' * part.stat().st_size)
        self.assert_refused()

    def test_symlink_manifest_refused(self):
        manifest = self.parts / 'manifest.json'
        raw = manifest.read_bytes()
        manifest.unlink()
        target = self.root / 'other-manifest.json'
        target.write_bytes(raw)
        manifest.symlink_to(target)
        self.assert_refused()

    def test_duplicate_destination_refused(self):
        self.assets.append(self.assets[0].copy())
        self.save_manifest()
        self.assert_refused()

if __name__ == '__main__': unittest.main()
