"""Generates stateful.mlpackage: `total += x; y = total` on float16 `[3]`.

Core ML states (`MLState`) need the iOS 18 / macOS 15 opset. Core ML state
buffers are float16, so the input and output are float16 too.
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
        mb.TensorSpec(shape=(3,), dtype=types.fp16),
        mb.StateTensorSpec((3,), dtype=types.fp16),
    ],
    opset_version=ct.target.iOS18,
)
def accumulator(x, total):
    updated = mb.add(x=mb.read_state(input=total), y=x)
    mb.coreml_update_state(state=total, value=updated)
    return mb.identity(x=updated, name="y")


model = ct.convert(
    accumulator,
    convert_to="mlprogram",
    minimum_deployment_target=ct.target.iOS18,
)
model.short_description = "total += x; y = total"
path = OUT / "stateful.mlpackage"
save_for_flutter(model, path)
print("saved", path)
print(model.get_spec().description)

state = model.make_state()
for step in range(3):
    out = model.predict({"x": np.array([1, 2, 3], dtype=np.float16)}, state=state)
    print("step", step, out)
