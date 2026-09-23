"""Generates multifunction.mlpackage: two functions in one package.

`double` computes `y = x * 2` and `negate` computes `y = -x`, both on float32
`[3]`. `double` is the default function. Select one with
`MLModelConfiguration.functionName`.
"""

import sys
import tempfile
from pathlib import Path

import coremltools as ct
import numpy as np
from coremltools.converters.mil import Builder as mb
from coremltools.converters.mil.mil import types
from coremltools.models.utils import MultiFunctionDescriptor, save_multifunction
from flutter_bundle import prune_empty_items

OUT = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
OUT.mkdir(parents=True, exist_ok=True)


@mb.program(input_specs=[mb.TensorSpec(shape=(3,), dtype=types.fp32)])
def double(x):
    return mb.mul(x=x, y=np.float32(2.0), name="y")


@mb.program(input_specs=[mb.TensorSpec(shape=(3,), dtype=types.fp32)])
def negate(x):
    return mb.mul(x=x, y=np.float32(-1.0), name="y")


with tempfile.TemporaryDirectory() as scratch:
    desc = MultiFunctionDescriptor()
    for name, program in [("double", double), ("negate", negate)]:
        source = Path(scratch) / f"{name}.mlpackage"
        ct.convert(
            program,
            convert_to="mlprogram",
            minimum_deployment_target=ct.target.iOS18,
            compute_precision=ct.precision.FLOAT32,
        ).save(str(source))
        desc.add_function(
            str(source), src_function_name="main", target_function_name=name
        )
    desc.default_function_name = "double"
    path = OUT / "multifunction.mlpackage"
    save_multifunction(desc, str(path))
    prune_empty_items(path)
print("saved", path)

x = {"x": np.array([1, 2, 3], dtype=np.float32)}
for name in ["double", "negate"]:
    model = ct.models.MLModel(str(path), function_name=name)
    print(name, model.predict(x))
