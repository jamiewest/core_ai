import asyncio, sys
from pathlib import Path
import numpy as np
import torch, torch.nn as nn
import coreai_torch
from coreai.runtime import AIModel, NDArray

OUT = Path(sys.argv[1])

class Affine(nn.Module):
    def forward(self, x):
        return x * 2.0 + 1.0

ep = torch.export.export(Affine().eval(), (torch.zeros(3, dtype=torch.float32),))
ep = ep.run_decompositions(coreai_torch.get_decomp_table())
conv = coreai_torch.TorchConverter()
conv.add_exported_program(ep, input_names=["x"], output_names=["y"])
prog = conv.to_coreai()
prog.optimize()
asset = prog.save_asset(OUT / "affine.aimodel")
print("saved", asset.path)

async def main():
    m = await AIModel.load(str(OUT / "affine.aimodel"))
    print("model:", m)
    f = m.load_function("main") if hasattr(m, "load_function") else None
    print("fn:", f)
    r = await f({"x": NDArray(np.array([1, 2, 3], dtype=np.float32))})
    print({k: np.asarray(v) for k, v in r.items()})
asyncio.run(main())
