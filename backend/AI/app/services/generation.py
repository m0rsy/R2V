from __future__ import annotations

import io
import threading
import time
from contextlib import contextmanager
from typing import Optional, Any

import torch
from PIL import Image

from app.core.pipeline import get_pipelines
from app.core.progress import update_job, set_error, set_done, add_timing, add_warning
from app.services.prompt_refiner import refine_prompt_for_3d_sd
from app.services.bg_remove import remove_bg_and_compose_white
from app.config import (
    OUTPUT_DIR,
    SD_WIDTH,
    SD_HEIGHT,
    SD_STEPS_FAST,
    SD_GUIDANCE_FAST,
    SDXL_TURBO_STEPS_FAST,
    SDXL_TURBO_GUIDANCE_FAST,
    SD_MODEL_ID,
    BACKEND_BASE_URL,
    ENABLE_BG_REMOVE,
    HY_STEPS,
    HY_GUIDANCE,
    HY_OCTREE_RES,
    HY_NUM_CHUNKS,
    HY_ENABLE_PBAR,
    HUNYUAN_PROFILE,
    ENABLE_MESH_SMOOTHING,
    MESH_SMOOTH_ITERATIONS,
    SERIALIZE_GPU_JOBS,
    KEEP_HUNYUAN_ON_GPU,
    MOVE_SD_BACK_TO_CPU_AFTER_USE,
)


_GPU_LOCK = threading.Lock()
_PIPELINE_DEVICE = {
    "sd": "cpu",
    "shape": "cpu",
}


@contextmanager
def _timed(job_id: str, name: str):
    start = time.perf_counter()
    try:
        yield
    finally:
        if torch.cuda.is_available():
            try:
                torch.cuda.synchronize()
            except Exception:
                pass

        elapsed = time.perf_counter() - start
        add_timing(job_id, name, elapsed)
        print(f"[timing] job={job_id} stage={name} seconds={elapsed:.2f}")


@contextmanager
def _gpu_job_lock():
    if SERIALIZE_GPU_JOBS:
        with _GPU_LOCK:
            yield
    else:
        yield


def _cuda_available() -> bool:
    return torch.cuda.is_available()


def _empty_cuda_cache() -> None:
    if torch.cuda.is_available():
        try:
            torch.cuda.empty_cache()
        except Exception:
            pass


def _move_pipeline(pipe: Any, name: str, device: str) -> None:
    if pipe is None:
        return

    current = _PIPELINE_DEVICE.get(name)

    if current == device:
        return

    print(f"[generation] Moving {name} pipeline: {current} → {device}")

    if name == "shape":
        pipe.to(torch.device(device))
    else:
        pipe.to(device)

    _PIPELINE_DEVICE[name] = device

    if device == "cpu":
        _empty_cuda_cache()


def _put_only_sd_on_gpu(sd_pipe: Any, shape_pipe: Any) -> None:
    if not _cuda_available():
        return

    _move_pipeline(shape_pipe, "shape", "cpu")
    _empty_cuda_cache()
    _move_pipeline(sd_pipe, "sd", "cuda")


def _put_only_hunyuan_on_gpu(sd_pipe: Any, shape_pipe: Any) -> None:
    if not _cuda_available():
        return

    _move_pipeline(sd_pipe, "sd", "cpu")
    _empty_cuda_cache()
    _move_pipeline(shape_pipe, "shape", "cuda")


def _maybe_release_sd(sd_pipe: Any) -> None:
    if not _cuda_available():
        return

    if MOVE_SD_BACK_TO_CPU_AFTER_USE:
        _move_pipeline(sd_pipe, "sd", "cpu")
        _empty_cuda_cache()


def _maybe_release_hunyuan(shape_pipe: Any) -> None:
    if not _cuda_available():
        return

    if not KEEP_HUNYUAN_ON_GPU:
        _move_pipeline(shape_pipe, "shape", "cpu")
        _empty_cuda_cache()


def _extract_mesh(shape_result):
    if shape_result is None:
        raise RuntimeError("Hunyuan3D returned None.")

    if isinstance(shape_result, (list, tuple)):
        return shape_result[0]

    if isinstance(shape_result, dict) and "mesh" in shape_result:
        return shape_result["mesh"]

    if isinstance(shape_result, dict) and len(shape_result) > 0:
        return next(iter(shape_result.values()))

    return shape_result


def _smooth_mesh(mesh):
    if not ENABLE_MESH_SMOOTHING or MESH_SMOOTH_ITERATIONS <= 0:
        return mesh

    try:
        import trimesh

        mesh_copy = mesh.copy()

        result = trimesh.smoothing.filter_laplacian(
            mesh_copy,
            lamb=0.25,
            iterations=int(MESH_SMOOTH_ITERATIONS),
            implicit_time_integration=False,
            volume_constraint=True,
        )

        if result is not None:
            print("[generation] Mesh smoothing applied.")
            return result

        print("[generation] Mesh smoothing applied in-place.")
        return mesh_copy

    except Exception as e:
        print(f"[generation] Smoothing failed, using raw mesh: {e}")
        return mesh


def _run_hunyuan(shape_pipe, image: Image.Image, use_cuda: bool):
    if shape_pipe is None:
        raise RuntimeError("Hunyuan shape pipeline is None.")

    kwargs = dict(
        image=image,
        num_inference_steps=HY_STEPS,
        guidance_scale=HY_GUIDANCE,
        octree_resolution=HY_OCTREE_RES,
        num_chunks=HY_NUM_CHUNKS,
        enable_pbar=HY_ENABLE_PBAR,
        output_type="trimesh",
    )

    if use_cuda:
        _empty_cuda_cache()

        try:
            torch.cuda.reset_peak_memory_stats()
        except Exception:
            pass

        with torch.inference_mode(), torch.autocast("cuda", dtype=torch.float16):
            result = shape_pipe(**kwargs)

        try:
            peak_gb = torch.cuda.max_memory_allocated() / 1024**3
            print(f"[generation] Hunyuan peak VRAM allocated: {peak_gb:.2f} GB")
        except Exception:
            pass

        return result

    with torch.inference_mode():
        return shape_pipe(**kwargs)


def _sd_callback_builder(job_id: str, total_steps: int, base_percent: int, span_percent: int):
    def _cb(step: int, timestep: int, latents):
        p = base_percent + int(((step + 1) / max(1, total_steps)) * span_percent)
        update_job(
            job_id,
            percent=min(p, base_percent + span_percent),
            message=f"SD step {step + 1}/{total_steps}",
        )
        return latents

    return _cb


def _ensure_512_rgb(img: Image.Image) -> Image.Image:
    img = img.convert("RGB")

    if img.size != (512, 512):
        img = img.resize((512, 512), Image.BICUBIC)

    return img


def _sd_generate(
    sd_pipe,
    pos_prompt: str,
    neg_prompt: Optional[str],
    steps: int,
    guidance: float,
    job_id: str,
    use_cuda: bool,
) -> Image.Image:
    cb = _sd_callback_builder(
        job_id,
        total_steps=steps,
        base_percent=5,
        span_percent=30,
    )

    common = dict(
        prompt=pos_prompt,
        negative_prompt=neg_prompt,
        num_inference_steps=steps,
        guidance_scale=guidance,
        width=SD_WIDTH,
        height=SD_HEIGHT,
        callback=cb,
        callback_steps=1,
    )

    if use_cuda:
        with torch.inference_mode(), torch.autocast("cuda", dtype=torch.float16):
            return sd_pipe(**common).images[0]

    with torch.inference_mode():
        return sd_pipe(**common).images[0]


def _prepare_for_hunyuan(image: Image.Image, image_bytes: bytes, job_id: str) -> Image.Image:
    if ENABLE_BG_REMOVE:
        update_job(
            job_id,
            stage="bg_remove",
            percent=36,
            message="Removing background for 3D...",
        )

        bg = remove_bg_and_compose_white(
            image_bytes,
            pad_ratio=0.12,
            bg_tol=75,
        )

        hunyuan_img = Image.open(io.BytesIO(bg.composited_rgb_png_bytes))
    else:
        update_job(
            job_id,
            stage="bg_remove",
            percent=36,
            message="BG removal disabled. Using raw image...",
        )
        hunyuan_img = image

    return _ensure_512_rgb(hunyuan_img)


def _job_settings() -> dict:
    return {
        "hunyuan_profile": HUNYUAN_PROFILE,
        "hy_steps": HY_STEPS,
        "hy_guidance": HY_GUIDANCE,
        "hy_octree_resolution": HY_OCTREE_RES,
        "hy_num_chunks": HY_NUM_CHUNKS,
        "mesh_smoothing": ENABLE_MESH_SMOOTHING,
        "mesh_smooth_iterations": MESH_SMOOTH_ITERATIONS,
        "sd_width": SD_WIDTH,
        "sd_height": SD_HEIGHT,
        "sd_model": SD_MODEL_ID,
        "serialize_gpu_jobs": SERIALIZE_GPU_JOBS,
        "keep_hunyuan_on_gpu": KEEP_HUNYUAN_ON_GPU,
    }


def run_text_job(job_id: str, prompt: str, preset: str) -> None:
    try:
        update_job(
            job_id,
            status="running",
            stage="refining",
            percent=2,
            message="Building 3D-friendly prompt...",
            settings=_job_settings(),
        )

        with _timed(job_id, "get_pipelines"):
            pipes = get_pipelines()
            sd_pipe = pipes["sd"]
            shape_pipe = pipes["shape"]

        use_cuda = _cuda_available()

        with _timed(job_id, "prompt_refine"):
            refined = refine_prompt_for_3d_sd(prompt, preset=preset)
            pos_prompt = refined.positive
            neg_prompt = refined.negative

        update_job(
            job_id,
            refined_prompt_positive=pos_prompt,
            refined_prompt_negative=neg_prompt,
            percent=5,
            message="Prompt ready",
            stage="sd",
        )

        is_turbo = "sdxl-turbo" in SD_MODEL_ID.lower()
        steps = SDXL_TURBO_STEPS_FAST if is_turbo else SD_STEPS_FAST
        guidance = SDXL_TURBO_GUIDANCE_FAST if is_turbo else SD_GUIDANCE_FAST
        sd_neg = None if is_turbo else neg_prompt

        job_dir = OUTPUT_DIR / job_id
        job_dir.mkdir(parents=True, exist_ok=True)

        with _gpu_job_lock():
            with _timed(job_id, "move_sd_to_gpu"):
                _put_only_sd_on_gpu(sd_pipe, shape_pipe)

            update_job(
                job_id,
                stage="sd",
                percent=6,
                message="Generating reference image...",
            )

            with _timed(job_id, "sd_generate"):
                image = _sd_generate(
                    sd_pipe,
                    pos_prompt,
                    sd_neg,
                    steps,
                    guidance,
                    job_id,
                    use_cuda,
                )

            with _timed(job_id, "release_sd"):
                _maybe_release_sd(sd_pipe)

            with _timed(job_id, "save_generated_image"):
                image.save(job_dir / "generated.png")
                buf = io.BytesIO()
                image.save(buf, format="PNG")
                image_bytes = buf.getvalue()

            with _timed(job_id, "bg_remove_prepare"):
                hunyuan_img = _prepare_for_hunyuan(image, image_bytes, job_id)
                hunyuan_img.save(job_dir / "generated_bg_removed.png")

            with _timed(job_id, "move_hunyuan_to_gpu"):
                _put_only_hunyuan_on_gpu(sd_pipe, shape_pipe)

            update_job(
                job_id,
                percent=40,
                stage="hunyuan",
                message="Running Hunyuan3D...",
            )

            with _timed(job_id, "hunyuan_generate"):
                shape_result = _run_hunyuan(
                    shape_pipe,
                    image=hunyuan_img,
                    use_cuda=use_cuda,
                )

            with _timed(job_id, "release_hunyuan"):
                _maybe_release_hunyuan(shape_pipe)

        update_job(job_id, percent=88, message="Decoding mesh...")

        with _timed(job_id, "extract_mesh"):
            mesh = _extract_mesh(shape_result)

        if mesh is None:
            raise RuntimeError("Mesh is None after extraction.")

        update_job(
            job_id,
            percent=92,
            stage="exporting",
            message="Smoothing mesh...",
        )

        with _timed(job_id, "mesh_smoothing"):
            mesh = _smooth_mesh(mesh)

        update_job(job_id, percent=95, message="Exporting GLB...")

        with _timed(job_id, "export_glb"):
            mesh.export(str(job_dir / "model.glb"))

        set_done(
            job_id,
            image_url=f"{BACKEND_BASE_URL}/outputs/{job_id}/generated.png",
            model_glb_url=f"{BACKEND_BASE_URL}/outputs/{job_id}/model.glb",
            texture_url=None,
        )

    except Exception as e:
        print(f"[generation] run_text_job ERROR job={job_id}: {e}")
        set_error(job_id, str(e))


def run_image_job(job_id: str, image_bytes: bytes, preset: str = "product") -> None:
    try:
        update_job(
            job_id,
            status="running",
            stage="bg_remove",
            percent=5,
            message="Loading image...",
            settings=_job_settings(),
        )

        with _timed(job_id, "get_pipelines"):
            pipes = get_pipelines()
            sd_pipe = pipes.get("sd")
            shape_pipe = pipes["shape"]

        use_cuda = _cuda_available()

        job_dir = OUTPUT_DIR / job_id
        job_dir.mkdir(parents=True, exist_ok=True)

        with _timed(job_id, "load_input_image"):
            image = Image.open(io.BytesIO(image_bytes)).convert("RGB")
            image.save(job_dir / "input.png")

        with _timed(job_id, "bg_remove_prepare"):
            hunyuan_img = _prepare_for_hunyuan(image, image_bytes, job_id)
            hunyuan_img.save(job_dir / "input_bg_removed.png")

        with _gpu_job_lock():
            with _timed(job_id, "move_hunyuan_to_gpu"):
                _put_only_hunyuan_on_gpu(sd_pipe, shape_pipe)

            update_job(
                job_id,
                stage="hunyuan",
                percent=15,
                message="Running Hunyuan3D...",
            )

            with _timed(job_id, "hunyuan_generate"):
                shape_result = _run_hunyuan(
                    shape_pipe,
                    image=hunyuan_img,
                    use_cuda=use_cuda,
                )

            with _timed(job_id, "release_hunyuan"):
                _maybe_release_hunyuan(shape_pipe)

        update_job(job_id, percent=88, message="Decoding mesh...")

        with _timed(job_id, "extract_mesh"):
            mesh = _extract_mesh(shape_result)

        if mesh is None:
            raise RuntimeError("Mesh is None after extraction.")

        update_job(
            job_id,
            percent=92,
            stage="exporting",
            message="Smoothing mesh...",
        )

        with _timed(job_id, "mesh_smoothing"):
            mesh = _smooth_mesh(mesh)

        update_job(job_id, percent=95, message="Exporting GLB...")

        with _timed(job_id, "export_glb"):
            mesh.export(str(job_dir / "model.glb"))

        set_done(
            job_id,
            image_url=f"{BACKEND_BASE_URL}/outputs/{job_id}/input.png",
            model_glb_url=f"{BACKEND_BASE_URL}/outputs/{job_id}/model.glb",
            texture_url=None,
        )

    except Exception as e:
        print(f"[generation] run_image_job ERROR job={job_id}: {e}")
        set_error(job_id, str(e))