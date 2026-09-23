"""Generates affine.mlpackage: `y = x * 2 + 1` on float32 `[3]`.

Built with the MIL builder so no PyTorch/TensorFlow frontend is needed.
FLOAT32 compute precision keeps the outputs exact for the integration tests.
"""

import sys
from pathlib import Path

import coremltools as ct
import numpy as np
from coremltools.converters.mil import Builder as mb
from coremltools.converters.mil.mil import types
from flutter_bundle import save_for_flutter

OUT = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
OUT.mkdir(parents=True, exist_ok=True)


@mb.program(input_specs=[mb.TensorSpec(shape=(3,), dtype=types.fp32)])
def affine(x):
    return mb.add(x=mb.mul(x=x, y=np.float32(2.0)), y=np.float32(1.0), name="y")


model = ct.convert(
    affine,
    convert_to="mlprogram",
    minimum_deployment_target=ct.target.iOS18,
    compute_precision=ct.precision.FLOAT32,
)
model.author = "core_ml tests"
model.license = "MIT"
model.short_description = "y = x * 2 + 1"
model.version = "1.0"
path = OUT / "affine.mlpackage"
save_for_flutter(model, path)
print("saved", path)
print(model.get_spec().description)
print(model.predict({"x": np.array([1, 2, 3], dtype=np.float32)}))
