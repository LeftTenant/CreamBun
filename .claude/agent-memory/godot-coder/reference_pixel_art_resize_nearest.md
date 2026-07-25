---
name: reference-pixel-art-resize-nearest
description: How to resize pixel-art PNGs without introducing blur/anti-aliasing
metadata:
  type: reference
---

Never resize a pixel-art texture with macOS `sips -z` — it has no nearest-neighbor option and
applies smooth interpolation, which blurs flat placeholder colors into dozens/hundreds of
intermediate shades. This softness is baked into the pixel data; it survives even when the
project's texture filter is already `Nearest` (Godot's runtime filter can't un-blur pixels that
were already blended at resize time).

**How to apply:** Resize pixel art with nearest-neighbor sampling instead, e.g.:

```python
from PIL import Image
im = Image.open(src).convert("RGBA")
im.resize((new_w, new_h), Image.NEAREST).save(dst)
```

Sanity-check the result by counting unique colors (`im.getcolors()`) before/after — a flat
placeholder texture should keep a small, similar color count; a big jump (e.g. 9 → 275) means
smooth interpolation was used somewhere in the pipeline. Caught in [[project_world_collision_feature]]
slice 2, where `sips -z 16 32` visibly softened the terrain tiles in-game.
