"""Generates image_input.mlpackage: a 4x4 BGR image in, float32 pixels out.

The image input carries no scale or bias, so the model's `pixels` output is the
raw channel values of the input image (planar, `[1, 3, 4, 4]`, B then G then R).
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
SIZE = 4


@mb.program(input_specs=[mb.TensorSpec(shape=(1, 3, SIZE, SIZE), dtype=types.fp32)])
def image_input(image):
    return mb.identity(x=image, name="pixels")


model = ct.convert(
    image_input,
    convert_to="mlprogram",
    minimum_deployment_target=ct.target.iOS18,
    compute_precision=ct.precision.FLOAT32,
    inputs=[
        ct.ImageType(
            name="image",
            shape=(1, 3, SIZE, SIZE),
            color_layout=ct.colorlayout.BGR,
            scale=1.0,
            bias=[0.0, 0.0, 0.0],
        )
    ],
)
model.short_description = "Copies a 4x4 BGR image into a float32 tensor"
path = OUT / "image_input.mlpackage"
save_for_flutter(model, path)
print("saved", path)
print(model.get_spec().description)

from PIL import Image  # noqa: E402

image = Image.new("RGB", (SIZE, SIZE), (10, 20, 30))
result = model.predict({"image": image})["pixels"]
print("pixels[0, :, 0, 0] =", result[0, :, 0, 0], "shape", result.shape)
