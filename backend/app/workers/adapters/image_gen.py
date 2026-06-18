from __future__ import annotations
from pathlib import Path
from PIL import Image, ImageDraw

def generate_image(prompt: str, out_path: Path) -> None:
    # Placeholder: replace with Stable Diffusion (local) call
    img = Image.new("RGB", (768, 512), color=(30, 30, 30))
    d = ImageDraw.Draw(img)
    d.text((20, 20), "R2V Placeholder Image", fill=(255, 255, 255))
    d.text((20, 60), prompt[:120], fill=(200, 200, 200))
    img.save(out_path)
