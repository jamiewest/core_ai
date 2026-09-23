import asyncio, sys, warnings
warnings.filterwarnings("ignore")
from pathlib import Path
import numpy as np
import torch, torch.nn as nn
import coreai_torch
from coreai.runtime import AIModel, NDArray

OUT = Path(sys.argv[1])

class MatmulAdd(nn.Module):
    def forward(self, a, b, c):
        return a @ b + c, a + 1.0     # two outputs

ex = (torch.zeros(2, 3), torch.zeros(3, 2), torch.zeros(2, 2))
ep = torch.export.export(MatmulAdd().eval(), ex).run_decompositions(coreai_torch.get_decomp_table())
conv = coreai_torch.TorchConverter()
conv.add_exported_program(ep, input_names=["a", "b", "c"], output_names=["y", "a_plus_1"])
prog = conv.to_coreai(); prog.optimize()
p = OUT / "matmul_add.aimodel"; prog.save_asset(p); print("saved", p)

async def main():
    f = (await AIModel.load(str(p))).load_function("main"); print(f)
    a = np.arange(6, dtype=np.float32).reshape(2, 3); b = np.ones((3, 2), np.float32); c = np.full((2, 2), 0.5, np.float32)
    r = await f({"a": NDArray(a), "b": NDArray(b), "c": NDArray(c)})
    print("y =", r["y"].numpy().tolist(), " expected", (a @ b + c).tolist())
    print("a_plus_1 =", r["a_plus_1"].numpy().tolist())
asyncio.run(main())
