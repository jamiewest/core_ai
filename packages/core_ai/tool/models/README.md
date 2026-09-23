# Test models

The example app and integration tests use four tiny Core AI models, stored in
`example/assets/models/`. These scripts regenerate them with Apple's Python
packages.

| Model | Function `main` |
|---|---|
| `affine.aimodel` | `y = x * 2 + 1`; `x`, `y`: float32 `[3]` |
| `accumulator.aimodel` | state `total += x`; `y = total`; all float32 `[3]` |
| `image_to_tensor.aimodel` | `image`: 4x4 `BGRA` pixel buffer → `pixels`: float32 `[4, 4, 4]` |
| `matmul_add.aimodel` | `y = a @ b + c`, `a_plus_1 = a + 1`; `a` `[2,3]`, `b` `[3,2]`, `c` `[2,2]` |

## Regenerating

`coreai-core` needs Python 3.11 to 3.13.

```sh
python3.13 -m venv .venv
.venv/bin/pip install coreai-torch 'torch==2.13.0' pillow
for script in tool/models/make_*.py; do
  .venv/bin/python "$script" example/assets/models
done
```

`coreai_torch` converts PyTorch modules (register a buffer and mutate it in
`forward` to get a state). It has no image support, so `make_image.py` builds
its graph with `coreai.authoring` directly.

An `.aimodel` is a directory (`main.mlirb`, `main.hash`, `metadata.json`), so
list each model directory under `flutter: assets:`.
