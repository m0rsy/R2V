from __future__ import annotations

import os
import sys
import threading
import uuid
from pathlib import Path

from dotenv import load_dotenv


# --------------------------------------------------
# PROJECT PATH
# --------------------------------------------------
PROJECT_ROOT = Path(__file__).resolve().parent

if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))


# --------------------------------------------------
# ENVIRONMENT — MUST run before torch / model imports
# --------------------------------------------------
load_dotenv()

BASE_CACHE = os.getenv("R2V_MODEL_CACHE", r"D:/Grademodels/model_cache")
HY3D_CACHE = os.getenv("R2V_HY3D_CACHE", f"{BASE_CACHE}/hy3dgen")

BASE_CACHE = BASE_CACHE.replace("\\", "/")
HY3D_CACHE = HY3D_CACHE.replace("\\", "/")

os.environ["R2V_MODEL_CACHE"] = BASE_CACHE

# Hunyuan3D cache dirs
os.environ["HY3DGEN_CACHE"] = HY3D_CACHE
os.environ["HY3DGEN_HOME"] = HY3D_CACHE
os.environ["HY3DGEN_MODEL_HOME"] = HY3D_CACHE

# General cache dirs
os.environ["XDG_CACHE_HOME"] = BASE_CACHE

# HuggingFace cache
os.environ["HF_HOME"] = BASE_CACHE
os.environ["HF_HUB_CACHE"] = f"{BASE_CACHE}/hub"
os.environ["HUGGINGFACE_HUB_CACHE"] = f"{BASE_CACHE}/hub"
os.environ["HF_HUB_DISABLE_SYMLINKS"] = "1"

# Windows path fallbacks
os.environ["USERPROFILE"] = BASE_CACHE
os.environ["HOME"] = BASE_CACHE

# Temp dirs
_tmp = f"{BASE_CACHE}/tmp"
os.environ["TEMP"] = _tmp
os.environ["TMP"] = _tmp
os.makedirs(_tmp, exist_ok=True)

# Remove old legacy cache var
os.environ.pop("TRANSFORMERS_CACHE", None)

# CUDA memory behavior — must be before importing torch
os.environ.setdefault("PYTORCH_CUDA_ALLOC_CONF", "max_split_size_mb:128")


# --------------------------------------------------
# TORCH PERFORMANCE FLAGS
# --------------------------------------------------
import torch

if torch.cuda.is_available():
    torch.backends.cuda.matmul.allow_tf32 = True
    torch.backends.cudnn.allow_tf32 = True
    torch.backends.cudnn.benchmark = True
    print(f"[main] CUDA available: {torch.cuda.get_device_name(0)}")
else:
    print("[main] WARNING: No CUDA detected. Generation will be very slow.")


# --------------------------------------------------
# APP IMPORTS
# --------------------------------------------------
from fastapi import FastAPI, UploadFile, File, Form, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from app.schemas import (
    Generate3DRequest,
    JobStartResponse,
    JobStatusResponse,
)
from app.core.pipeline import init_pipelines, is_ready
from app.core.progress import (
    init_job,
    get_job,
    update_job,
    list_jobs,
    cleanup_old_jobs,
)
from app.services.generation import run_text_job, run_image_job
from app.services.voice_service import transcribe_and_translate_to_english
from app.config import OUTPUT_DIR


# --------------------------------------------------
# FASTAPI APP
# --------------------------------------------------
app = FastAPI(
    title="R2V Text-to-3D Backend",
    description="Real2Virtual — text / image / voice → 3D GLB via SD + Hunyuan3D-2",
    version="1.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.mount("/outputs", StaticFiles(directory=OUTPUT_DIR), name="outputs")


# --------------------------------------------------
# HELPERS
# --------------------------------------------------
def _start_background_job(target, *args) -> None:
    thread = threading.Thread(
        target=target,
        args=args,
        daemon=True,
        name=f"r2v-job-{uuid.uuid4().hex[:8]}",
    )
    thread.start()


# --------------------------------------------------
# STARTUP
# --------------------------------------------------
@app.on_event("startup")
def on_startup() -> None:
    """
    Load pipelines once.

    Important:
    Do not run SD warmup here.
    The generation service controls when SD/Hunyuan move to GPU.
    This avoids keeping SD and Hunyuan on GPU at the same time.
    """
    try:
        init_pipelines(cache_dir=BASE_CACHE)
        print("[main] Pipelines loaded. GPU movement will happen per generation stage.")
    except Exception as exc:
        print(f"[main] Pipeline startup load failed: {exc}")
        raise


# --------------------------------------------------
# HEALTH
# --------------------------------------------------
@app.get("/health", tags=["Meta"])
def health():
    return {
        "ok": True,
        "pipelines_ready": is_ready(),
        "cuda": torch.cuda.is_available(),
        "cuda_device": torch.cuda.get_device_name(0) if torch.cuda.is_available() else None,
        "base_cache": BASE_CACHE,
        "hy3d_cache": HY3D_CACHE,
    }


# --------------------------------------------------
# TEXT → 3D
# --------------------------------------------------
@app.post("/api/generate-3d", response_model=JobStartResponse, tags=["Generate"])
async def start_text_job(payload: Generate3DRequest):
    job_id = uuid.uuid4().hex

    init_job(job_id)
    update_job(
        job_id,
        message="Queued",
        stage="queued",
        percent=0,
    )

    _start_background_job(
        run_text_job,
        job_id,
        payload.prompt,
        payload.preset,
    )

    return JobStartResponse(job_id=job_id)


# --------------------------------------------------
# IMAGE → 3D
# --------------------------------------------------
@app.post("/api/generate-3d-from-image", response_model=JobStartResponse, tags=["Generate"])
async def start_image_job(
    file: UploadFile = File(...),
    preset: str = Form("product"),
):
    image_bytes = await file.read()

    if not image_bytes:
        raise HTTPException(status_code=400, detail="Empty file uploaded.")

    job_id = uuid.uuid4().hex

    init_job(job_id)
    update_job(
        job_id,
        message="Image received. Queued.",
        stage="queued",
        percent=0,
    )

    _start_background_job(
        run_image_job,
        job_id,
        image_bytes,
        preset,
    )

    return JobStartResponse(job_id=job_id)


# --------------------------------------------------
# VOICE → 3D
# --------------------------------------------------
@app.post("/api/voice-to-3d", response_model=JobStartResponse, tags=["Generate"])
async def start_voice_job(
    file: UploadFile = File(...),
    preset: str = Form("product"),
):
    audio_bytes = await file.read()

    if not audio_bytes:
        raise HTTPException(status_code=400, detail="Empty audio file.")

    job_id = uuid.uuid4().hex

    init_job(job_id)
    update_job(
        job_id,
        status="running",
        stage="refining",
        percent=1,
        message="Transcribing voice...",
    )

    try:
        vr = transcribe_and_translate_to_english(audio_bytes)
    except Exception as exc:
        update_job(
            job_id,
            status="error",
            stage="error",
            percent=100,
            error=f"Transcription failed: {exc}",
            message="Transcription failed.",
        )
        raise HTTPException(status_code=500, detail=f"Transcription failed: {exc}")

    prompt_used = (vr.text_english or vr.transcript_original or "").strip()

    if not prompt_used:
        update_job(
            job_id,
            status="error",
            stage="error",
            percent=100,
            error="Could not transcribe audio — empty result",
            message="Could not transcribe audio.",
        )
        raise HTTPException(status_code=400, detail="Could not transcribe audio.")

    update_job(
        job_id,
        voice_detected_language=vr.detected_language,
        voice_transcript_original=vr.transcript_original,
        voice_text_english=vr.text_english,
        voice_prompt_used=prompt_used,
        message="Voice transcribed. Starting generation...",
        stage="refining",
        percent=2,
    )

    _start_background_job(
        run_text_job,
        job_id,
        prompt_used,
        preset,
    )

    return JobStartResponse(job_id=job_id)


# --------------------------------------------------
# JOB STATUS
# --------------------------------------------------
@app.get("/api/jobs/{job_id}", response_model=JobStatusResponse, tags=["Jobs"])
def job_status(job_id: str):
    job = get_job(job_id)

    if not job:
        raise HTTPException(status_code=404, detail="Job not found.")

    return job


@app.get("/api/jobs", tags=["Jobs"])
def list_all_jobs():
    return list_jobs()


# --------------------------------------------------
# MAINTENANCE
# --------------------------------------------------
@app.delete("/api/jobs/cleanup", tags=["Jobs"])
def cleanup_jobs(max_age_seconds: float = 3600.0):
    removed = cleanup_old_jobs(max_age_seconds=max_age_seconds)
    return {"removed": removed}


# --------------------------------------------------
# LOCAL RUN
# --------------------------------------------------
if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        "main:app",
        host="127.0.0.1",
        port=8000,
        reload=False,
    )