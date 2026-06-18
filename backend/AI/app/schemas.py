# schemas.py
from pydantic import BaseModel, field_validator
from typing import Optional, Literal
from typing import Optional, Literal, Dict, Any


# -----------------------------
# REQUESTS
# -----------------------------

class Generate3DRequest(BaseModel):
    prompt: str
    preset: str = "product"   # product | studio | photoreal | FAST | QUALITY

    @field_validator("prompt")
    @classmethod
    def prompt_not_empty(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("prompt must not be empty")
        return v

    @field_validator("preset")
    @classmethod
    def preset_valid(cls, v: str) -> str:
        allowed = {"product", "studio", "photoreal", "FAST", "QUALITY"}
        if v not in allowed:
            return "product"
        return v


# -----------------------------
# RESPONSES
# -----------------------------

class JobStartResponse(BaseModel):
    job_id: str


class JobStatusResponse(BaseModel):
    job_id: str

    status: Literal["queued", "running", "done", "error"]
    stage: Literal[
        "queued",
        "refining",
        "sd",
        "bg_remove",
        "hunyuan",
        "exporting",
        "done",
        "error",
    ]

    percent: int
    message: Optional[str] = None
    error: Optional[str] = None

    # Available only when status == "done"
    image_url: Optional[str] = None
    model_glb_url: Optional[str] = None
    texture_url: Optional[str] = None

    # Voice fields
    voice_detected_language: Optional[str] = None
    voice_transcript_original: Optional[str] = None
    voice_text_english: Optional[str] = None
    voice_prompt_used: Optional[str] = None

    # Prompt fields
    refined_prompt_positive: Optional[str] = None
    refined_prompt_negative: Optional[str] = None
    # new added fields
    timings: Optional[Dict[str, float]] = None
    settings: Optional[Dict[str, Any]] = None
    warnings: Optional[list[str]] = None