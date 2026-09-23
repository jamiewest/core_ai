"""Saves an .mlpackage so it survives being bundled as Flutter assets.

Flutter only bundles files, never empty directories. coremltools always writes
a `Data/com.apple.CoreML/weights` item into the package manifest, and for a
model without weights that directory is empty, so the bundled package would
reference a missing item and Core ML would refuse to read it. Drop manifest
items whose directory is empty.
"""

import json
from pathlib import Path


def save_for_flutter(model, path: Path) -> None:
    model.save(str(path))
    prune_empty_items(path)


def prune_empty_items(path: Path) -> None:
    manifest_path = path / "Manifest.json"
    manifest = json.loads(manifest_path.read_text())
    items = manifest["itemInfoEntries"]
    for identifier, item in list(items.items()):
        item_path = path / "Data" / item["path"]
        if item_path.is_dir() and not any(item_path.iterdir()):
            item_path.rmdir()
            del items[identifier]
    manifest_path.write_text(json.dumps(manifest, indent=4) + "\n")
