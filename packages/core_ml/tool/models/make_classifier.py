"""Generates classifier.mlpackage: a three-class softmax classifier.

Gives the integration tests a model with `classLabels`,
`predictedFeatureName`, `predictedProbabilitiesName`, a string output and a
dictionary output.
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
LABELS = ["ant", "bee", "cat"]


@mb.program(input_specs=[mb.TensorSpec(shape=(1, 3), dtype=types.fp32)])
def classifier(scores):
    return mb.softmax(x=scores, axis=1, name="probabilities")


model = ct.convert(
    classifier,
    convert_to="mlprogram",
    minimum_deployment_target=ct.target.iOS18,
    compute_precision=ct.precision.FLOAT32,
    classifier_config=ct.ClassifierConfig(class_labels=LABELS),
)
model.short_description = "Softmax over three classes"
path = OUT / "classifier.mlpackage"
save_for_flutter(model, path)
print("saved", path)
print(model.get_spec().description)
print(model.predict({"scores": np.array([[0.0, 5.0, 1.0]], dtype=np.float32)}))
