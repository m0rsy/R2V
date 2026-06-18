from __future__ import annotations
from pydantic import BaseModel, Field, field_validator
from typing import Any

# Allowed generation inputs: text prompt, uploaded voice clip, or uploaded image.
VALID_INPUT_TYPES = {"prompt", "voice", "image"}

class AIJobCreateIn(BaseModel):
    # prompt is optional because voice/image jobs may have no text.
    prompt: str = Field(default="", max_length=2000)
    input_type: str = Field(default="prompt")
    # True  -> run SD -> Hunyuan shape -> Hunyuan texture (textured GLB)
    # False -> stop after Hunyuan shape (mesh-only GLB)
    with_texture: bool = True
    settings: dict[str, Any] = Field(default_factory=dict)

    @field_validator("input_type")
    @classmethod
    def _validate_input_type(cls, value: str) -> str:
        normalized = (value or "prompt").strip().lower()
        if normalized not in VALID_INPUT_TYPES:
            raise ValueError(
                f"input_type must be one of {sorted(VALID_INPUT_TYPES)}"
            )
        return normalized

class ScanJobCreateIn(BaseModel):
    kind: str = Field(default="photos", description="photos|zip")

class ExportIn(BaseModel):
    formats: list[str] = Field(default_factory=lambda: ["glb", "stl"])

class JobOut(BaseModel):
    id: str
    status: str
    progress: int
    # Live AI generation progress (mirrored from Modal while running).
    stage: str | None = None
    message: str | None = None
    created_at: str
    updated_at: str | None = None
    prompt: str | None = None
    input_type: str | None = None
    # Requested texture preference for this job.
    with_texture: bool | None = None
    # Whether the returned model is actually textured (set once it succeeds).
    textured: bool | None = None
    metadata: dict[str, Any] = Field(default_factory=dict)
    output_glb_key: str | None = None
    output_stl_key: str | None = None
    output_image_key: str | None = None
    preview_keys: list[str] = Field(default_factory=list)
    # Resolved model download URLs (presigned) once the job has succeeded.
    model_url: str | None = None
    glb_url: str | None = None
    download_url: str | None = None
    # Freshly presigned URL for the job's stored input/preview image
    # (output_image_key). Lets the AI chat re-show an uploaded image after the
    # original presigned URL has expired. Owner-scoped via the route's auth.
    output_image_url: str | None = None
    # Optional sidecar artifacts reported by the Modal pipeline.
    raw_glb_url: str | None = None
    condition_image_url: str | None = None
    texture_png_url: str | None = None
    texture_debug_url: str | None = None
    artifacts: dict[str, Any] = Field(default_factory=dict)
    error: str | None = None

class DownloadOut(BaseModel):
    url: str
    expires_in: int

class AIJobAssetCreateIn(BaseModel):
    """Publish a succeeded AI job's GLB to the marketplace. Mirrors the
    photogrammetry asset-create input. The model/thumbnail object keys are
    resolved server-side from the owned AIJob row — never accepted from the
    client."""
    title: str = Field(default="AI Generated Model", min_length=1, max_length=200)
    description: str | None = Field(default=None, max_length=4000)
    tags: list[str] = Field(default_factory=list)
    category: str = Field(default="Objects", min_length=1, max_length=64)
    style: str = Field(default="AI Generated", min_length=1, max_length=64)
    is_paid: bool = False
    price: int = Field(default=0, ge=0)
    currency: str = Field(default="usd", min_length=1, max_length=8)
    publish: bool = True
    include_thumbnail: bool = True
    # Optional captured thumbnail already uploaded by the client via the
    # marketplace presign flow (kind="thumb"). When set it overrides the
    # generated-preview copy. Validated server-side to live under the caller's
    # own key namespace so it can never reference another user's object.
    thumb_object_key: str | None = None
    # When False (default) re-posting the same job returns the existing asset
    # instead of creating a duplicate listing.
    repost: bool = False
