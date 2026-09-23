import asyncio, sys, warnings
warnings.filterwarnings("ignore")
from pathlib import Path
import numpy as np
import torch, torch.nn as nn
import coreai_torch
from coreai.runtime import AIModel, NDArray

OUT = Path(sys.argv[1])

class Acc(nn.Module):
    def __init__(self):
        super().__init__()
        self.register_buffer("total", torch.zeros(3, dtype=torch.float32))
    def forward(self, x):
        self.total.add_(x)
        return self.total.clone()

ep = torch.export.export(Acc().eval(), (torch.zeros(3, dtype=torch.float32),))
ep = ep.run_decompositions(coreai_torch.get_decomp_table())
print(ep.graph_signature)
conv = coreai_torch.TorchConverter()
conv.add_exported_program(ep, input_names=["x"], output_names=["y"], state_names=["total"])
prog = conv.to_coreai()
prog.optimize()
p = OUT / "accumulator.aimodel"
prog.save_asset(p)
print("saved", p)

async def main():
    m = await AIModel.load(str(p))
    f = m.load_function("main")
    print(f)
    st = NDArray(np.zeros(3, dtype=np.float32))
    for i in range(3):
        r = await f({"x": NDArray(np.array([1, 2, 3], dtype=np.float32))}, state={"total": st})
        print("call", i, "y =", r["y"].numpy(), "state =", st.numpy())
asyncio.run(main())
