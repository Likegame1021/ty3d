# Recovery and scope

This is a source-only recovery, not a new completed release. The original-map source was reconstructed in the verified sequence R26 volumes → R37 (606 files) → R48 accepted delta (618 files) → early-corn/contact checkpoint (622 files). Every pre-packaging file matched its archived SHA-256. All 13 input ZIP archives matched their recorded SHA-256 and passed ZIP CRC checks.

The R48 checkpoint remains an experimental candidate, not an accepted full-route release. Later R62 / October 11 original-map candidates were not available in the recovered archive set and are not claimed to be present.

## Packaging changes

- Main project: select `scenes/modular/modular_slice.tscn` in `game/project.godot`; remove a historical absolute source path from the corn contact-anchor metadata. No gameplay script or scene changed.
- Separate static-2D sample: remove three historical absolute provenance paths and update the two corresponding manifest hash references. Image pixels, meshes, scenes and gameplay scripts remain unchanged. The original default `main.tscn` remains unchanged; explicitly open the static-hero scene.
- Omit historical execution logs from the public sample; distinguish historical documentation from this recovery. Update the sample byte-verification manifest to preserve old and current metadata hashes.
- Exclude private coordination, asset-production ledgers, recovery tooling, archives, engine binaries, `.godot` import caches and local test state.

The pre-existing top-level `art/`, `tools/`, `docs/` and old launchers are retained in the repository. They are historical material, not all validated against this snapshot. In particular, legacy validation/render scripts may reference helpers not included in the recovered project. Use the root README for the current entry points.

## Asset provenance and licensing

The recovered project contains existing project assets, including Meshy-generated character/environment assets, and original Blender/procedural additions. The R48 wayfinding sign, drying rack and corn sentinel have original Blender provenance in the archived production records. No new third-party asset was downloaded for this recovery. Existing copyright and service terms remain applicable; no blanket MIT, CC0, or other new license is granted by this packaging. Public availability alone is not a grant of redistribution rights.

## GitHub transport packaging

Two new GLB assets exceed the connector's conservative 12,000,000-byte raw-file ceiling. They are stored as lossless pieces no larger than 6 MiB in `_asset_parts/`, with sizes and SHA-256 in `_asset_parts/manifest.json`. Run `python3 restore_assets.py` before Godot import. Reconstruction restores the exact reviewed bytes; no game script, scene, texture, animation or model was changed. The complete un-split recovery remains separately preserved. The Python 3.8+ offline restorer validates inputs and refuses differing existing output files; verified temporary files are installed by atomic no-clobber hard link, requiring a hard-link-capable local filesystem. All pieces remain available for verification.
