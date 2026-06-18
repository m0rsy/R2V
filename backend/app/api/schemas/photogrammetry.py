from __future__ import annotations

from pydantic import BaseModel
from pydantic import Field


class PhotogrammetryJobCreatedOut(BaseModel):
    job_id: str
    status: str
    progress: int


class PhotogrammetryJobStatusOut(BaseModel):
    job_id: str
    status: str
    progress: int
    created_at: str
    updated_at: str
    error: str | None = None


class PhotogrammetryOutputFileOut(BaseModel):
    filename: str
    file_size: int
    file_type: str
    content_type: str
    download_url: str


class PhotogrammetryJobOutputOut(BaseModel):
    job_id: str
    status: str
    files: list[PhotogrammetryOutputFileOut]


class PhotogrammetryAssetCreateIn(BaseModel):
    title: str = Field(default="Photogrammetry Scan", min_length=1, max_length=200)
    description: str | None = None
    tags: list[str] = Field(default_factory=lambda: ["photogrammetry", "scan"])
    category: str = "Scans"
    style: str = "Photogrammetry"
    is_paid: bool = False
    price: int = 0
    currency: str = "usd"
    publish: bool = False
    thumb_object_key: str | None = None
