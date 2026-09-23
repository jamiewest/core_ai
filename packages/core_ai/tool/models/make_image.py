import asyncio, sys, warnings
warnings.filterwarnings("ignore")
from pathlib import Path
from typing import Annotated
import numpy as np
from PIL import Image
from coreai.authoring import Module, AIProgram, ImageSpec, TensorSpec
from coreai._compiler.dialects import coreai as cai
from coreai._compiler.dialects.coreai import FourCC
from coreai._compiler.ir import Value
from coreai.runtime import AIModel, NDArray

OUT = Path(sys.argv[1]); H = W = 4

with Module.create() as mod:
    @cai.graph
    def main(
        image: Annotated[Value, ImageSpec(FourCC.BGRA32, H, W, "image")],
    ) -> Annotated[Value, TensorSpec((H, W, 4), np.float32, "pixels")]:
        t = cai.image_to_tensor(image)          # uint8 [H, W, 4] (BGRA byte order)
        return cai.cast(t, np.float32)
mod.verify()
print(mod)
prog = AIProgram(mod)
prog.optimize()
p = OUT / "image_to_tensor.aimodel"
prog.save_asset(p)
print("saved", p)

async def main_():
    m = await AIModel.load(str(p))
    f = m.load_function("main")
    print(f)
    img = Image.new("RGBA", (W, H), (10, 20, 30, 255))
    r = await f({"image": img})
    print("pixels[0,0,:] =", r["pixels"].numpy()[0, 0], "shape", r["pixels"].numpy().shape)
asyncio.run(main_())
