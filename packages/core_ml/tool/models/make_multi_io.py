"""Generates multi_io.mlpackage: two outputs from three float32 inputs.

`y = a @ b + c` with `a` `[2, 3]`, `b` `[3, 2]`, `c` `[2, 2]`, plus a second
output `a_plus_1 = a + 1`.
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


@mb.program(
    input_specs=[
        mb.TensorSpec(shape=(2, 3), dtype=types.fp32),
        mb.TensorSpec(shape=(3, 2), dtype=types.fp32),
        mb.TensorSpec(shape=(2, 2), dtype=types.fp32),
    ]
)
def multi_io(a, b, c):
    product = mb.matmul(x=a, y=b)
    return (
        mb.add(x=product, y=c, name="y"),
        mb.add(x=a, y=np.float32(1.0), name="a_plus_1"),
    )


model = ct.convert(
    multi_io,
    convert_to="mlprogram",
    minimum_deployment_target=ct.target.iOS18,
    compute_precision=ct.precision.FLOAT32,
)
model.short_description = "y = a @ b + c, a_plus_1 = a + 1"
path = OUT / "multi_io.mlpackage"
save_for_flutter(model, path)
print("saved", path)
print(model.get_spec().description)
print(
    model.predict(
        {
            "a": np.arange(6, dtype=np.float32).reshape(2, 3),
            "b": np.ones((3, 2), dtype=np.float32),
            "c": np.full((2, 2), 0.5, dtype=np.float32),
        }
    )
)
