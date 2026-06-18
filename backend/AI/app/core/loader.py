from __future__ import annotations

from typing import Any, Dict, Optional

import torch
from diffusers import StableDiffusionPipeline, DPMSolverMultistepScheduler

from app.config import (
    SD_MODEL_ID,
    HUNYUAN_MODEL_ID,
    LOAD_PIPELINES_TO_GPU_ON_STARTUP,
)


def _load_sd_pipeline(
    device: str,
    dtype: torch.dtype,
    cache_dir: Optional[str] = None,
) -> Any:
    is_sdxl_turbo = "sdxl-turbo" in SD_MODEL_ID.lower()

    if is_sdxl_turbo:
        from diffusers import AutoPipelineForText2Image

        pipe = AutoPipelineForText2Image.from_pretrained(
            SD_MODEL_ID,
            torch_dtype=dtype,
            variant="fp16" if dtype == torch.float16 else None,
            cache_dir=cache_dir,
            local_files_only=True,
        )
    else:
        pipe = StableDiffusionPipeline.from_pretrained(
            SD_MODEL_ID,
            torch_dtype=dtype,
            safety_checker=None,
            requires_safety_checker=False,
            cache_dir=cache_dir,
            local_files_only=True,
        )

        pipe.scheduler = DPMSolverMultistepScheduler.from_config(
            pipe.scheduler.config,
            use_karras_sigmas=True,
        )

    pipe.to(device)

    if hasattr(pipe, "enable_xformers_memory_efficient_attention"):
        try:
            pipe.enable_xformers_memory_efficient_attention()
            print("[loader] SD: xformers enabled")
        except Exception as e:
            print(f"[loader] SD: xformers skipped ({e})")

    for method in ("enable_vae_slicing", "enable_vae_tiling"):
        if hasattr(pipe, method):
            try:
                getattr(pipe, method)()
            except Exception:
                pass

    if hasattr(pipe, "unet"):
        try:
            pipe.unet.to(memory_format=torch.channels_last)
            print("[loader] SD: channels_last enabled")
        except Exception as e:
            print(f"[loader] SD: channels_last skipped ({e})")

    print(f"[loader] SD loaded → {SD_MODEL_ID[:80]}  device={device}  dtype={dtype}")
    return pipe


def _load_hunyuan_pipeline(
    device: str,
    dtype: torch.dtype,
    cache_dir: Optional[str] = None,
) -> Any:
    try:
        from hy3dgen.shapegen import Hunyuan3DDiTFlowMatchingPipeline
    except ImportError as exc:
        raise ImportError("hy3dgen is not installed. Run: pip install hy3dgen") from exc

    shape = Hunyuan3DDiTFlowMatchingPipeline.from_pretrained(
        HUNYUAN_MODEL_ID,
        torch_dtype=dtype,
        cache_dir=cache_dir,
        local_files_only=True,
    )

    shape.to(torch.device(device))

    if hasattr(shape, "enable_xformers_memory_efficient_attention"):
        try:
            shape.enable_xformers_memory_efficient_attention()
            print("[loader] Hunyuan: xformers enabled")
        except Exception as e:
            print(f"[loader] Hunyuan: xformers skipped ({e})")

    print(f"[loader] Hunyuan3D loaded → {HUNYUAN_MODEL_ID}  device={device}  dtype={dtype}")
    return shape


def load_all_pipelines(cache_dir: Optional[str] = None) -> Dict[str, Any]:
    cuda_available = torch.cuda.is_available()
    runtime_device = "cuda" if cuda_available else "cpu"
    load_device = runtime_device if LOAD_PIPELINES_TO_GPU_ON_STARTUP else "cpu"
    dtype = torch.float16 if cuda_available else torch.float32

    print(
        f"[loader] cuda_available={cuda_available}  "
        f"runtime_device={runtime_device}  load_device={load_device}  "
        f"dtype={dtype}  cache_dir={cache_dir or '(env default)'}"
    )

    if not cuda_available:
        print("[loader] ⚠️ Running on CPU — generation will be very slow.")

    try:
        sd = _load_sd_pipeline(device=load_device, dtype=dtype, cache_dir=cache_dir)
    except Exception as exc:
        raise RuntimeError(f"Failed to load SD pipeline: {exc}") from exc

    try:
        shape = _load_hunyuan_pipeline(device=load_device, dtype=dtype, cache_dir=cache_dir)
    except Exception as exc:
        raise RuntimeError(f"Failed to load Hunyuan3D pipeline: {exc}") from exc

    assert sd is not None and callable(sd), "SD pipeline is None or not callable"
    assert shape is not None and callable(shape), "Hunyuan pipeline is None or not callable"

    print("[loader] ✅ All pipelines loaded.")
    return {
        "sd": sd,
        "shape": shape,
        "_meta": {
            "runtime_device": runtime_device,
            "load_device": load_device,
            "dtype": str(dtype),
        },
    }