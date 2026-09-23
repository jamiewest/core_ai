# Test models

The example app and integration tests use six tiny Core ML models, stored in
`example/assets/models/` as `.mlpackage` directories. These scripts
regenerate them with `coremltools`' MIL builder (no PyTorch needed).

| Model | Inputs → outputs |
|---|---|
| `affine.mlpackage` | `x` float32 `[3]` → `y = x * 2 + 1`; carries author, license, description and version metadata |
| `multi_io.mlpackage` | `a` `[2,3]`, `b` `[3,2]`, `c` `[2,2]` → `y = a @ b + c`, `a_plus_1 = a + 1` |
| `image_input.mlpackage` | `image` 4x4 BGR (`BGRA` pixel buffer) → `pixels` float32 `[1,3,4,4]` (B, G, R planes, no scaling) |
| `stateful.mlpackage` | `x` float16 `[3]`, state `total` float16 `[3]` → `total += x; y = total` |
| `multifunction.mlpackage` | functions `double` (`y = x * 2`, the default) and `negate` (`y = -x`), `x` float32 `[3]` |
| `classifier.mlpackage` | `scores` float32 `[1,3]` → `classLabel` (string), `classLabel_probs` (dictionary) over `ant`, `bee`, `cat` |

All use the iOS 18 / macOS 15 ML Program format and FLOAT32 compute
precision (except the float16 stateful model), so outputs are exact.

## Regenerating

`coremltools` needs Python 3.11 to 3.13.

```sh
python3.13 -m venv .venv
.venv/bin/pip install coremltools pillow
for script in tool/models/make_*.py; do
  .venv/bin/python "$script" example/assets/models
done
```

Each script prints the model's description and a Python-side prediction,
which the integration tests' expectations are taken from.

## Bundling

`flutter_bundle.py` saves each package and then removes manifest items whose
directory is empty. These models have no weights, so the `weights` directory
`coremltools` always writes is empty; Flutter never bundles empty
directories, and Core ML refuses a package whose manifest names a missing
item. List every directory that holds files under `flutter: assets:` (asset
directory entries are not recursive), for example:

```yaml
- assets/models/affine.mlpackage/
- assets/models/affine.mlpackage/Data/com.apple.CoreML/
```
