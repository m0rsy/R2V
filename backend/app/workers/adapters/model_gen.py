"""Modal AI integration (prompt / image -> 3D GLB).

Implements the *async job* contract exposed by the deployed R2V Modal app
(r2v-ai.ipynb / r2v_modal_app.py):

    1. POST /generate (or /image-to-3d)        -> {"job_id", "status", "poll_url"}
       (the blocking variant may instead return the full success payload directly)
    2. GET  /jobs/{job_id}                      -> {"status": "succeeded"|"failed"|..., ...}
    3. On "succeeded": download the final GLB from glb_url / model_url /
       download_url (or /download/{job_id}/{files.final_glb}).
    4. On "failed": raise with the Modal error message.

Each generation function writes the final GLB to ``out_glb`` and returns a
``GenerationResult`` describing the *actual* output (texture honesty):

    final_kind      -> "textured" | "untextured" | None  (from Modal)
    textured        -> True only when the final GLB is really textured
    fallback_used   -> True when texture was requested but Modal returned a
                       raw/fallback mesh instead
    selected_glb    -> the final GLB filename/URL that was downloaded
    texture_files   -> sidecar texture file names, if any
"""

from __future__ import annotations

import mimetypes
import time
from collections.abc import Callable
from dataclasses import dataclass, field
from pathlib import Path
from urllib.parse import urljoin

import httpx

from app.core.config import settings

# Called on every Modal poll with the raw status payload so the caller can
# persist live progress (progress/stage/message) to the local job row.
ProgressCallback = Callable[[dict], None]


@dataclass
class GenerationResult:
    final_kind: str | None = None
    textured: bool = False
    fallback_used: bool = False
    selected_glb: str | None = None
    texture_files: list[str] = field(default_factory=list)
    # Sidecar artifact URLs reported by Modal (absolute), surfaced to the app.
    raw_glb_url: str | None = None
    condition_image_url: str | None = None
    texture_png_url: str | None = None
    texture_debug_url: str | None = None
    artifacts: dict = field(default_factory=dict)
    raw: dict = field(default_factory=dict)


def _endpoint() -> str:
    base = settings.modal_endpoint_url
    if not base:
        raise ValueError(
            "Modal AI endpoint is not configured. Set MODAL_R2V_ENDPOINT_URL "
            "(or MODAL_API_URL) to the deployed Modal app URL."
        )
    return base.rstrip("/") + "/"


def _auth_headers() -> dict:
    token = settings.r2v_api_token.strip()
    return {"Authorization": f"Bearer {token}"} if token else {}


def _join(path: str) -> str:
    return urljoin(_endpoint(), path.lstrip("/"))


def _download_glb(url: str, out_glb: Path) -> None:
    """Download a GLB, retrying while Modal reports 404 (object not committed yet)."""
    attempts = max(1, settings.modal_download_max_attempts)
    last: Exception | None = None
    with httpx.Client(timeout=settings.modal_api_timeout_s, follow_redirects=True) as client:
        for _ in range(attempts):
            resp = client.get(url, headers=_auth_headers())
            if resp.status_code == 404:
                last = httpx.HTTPStatusError("not ready", request=resp.request, response=resp)
                time.sleep(settings.modal_download_retry_s)
                continue
            resp.raise_for_status()
            out_glb.write_bytes(resp.content)
            return
    raise RuntimeError(f"Modal GLB download did not become ready: {url}") from last


def _absolute(url: str) -> str:
    if url.startswith("http://") or url.startswith("https://"):
        return url
    return _join(url)


def _emit_progress(on_progress: ProgressCallback | None, payload: dict) -> None:
    """Forward a Modal status payload to the caller's progress sink, never
    letting a reporting error abort the generation."""
    if on_progress is None:
        return
    try:
        on_progress(payload)
    except Exception:
        # Progress reporting is best-effort; it must not fail the job.
        pass


def _poll_job(
    client: httpx.Client,
    job_id: str,
    on_progress: ProgressCallback | None = None,
) -> dict:
    """Poll GET /jobs/{job_id} until the job reaches a terminal state.

    ``on_progress`` (if given) is invoked with every intermediate status
    payload so the caller can mirror Modal's progress/stage/message live.
    """
    deadline = time.monotonic() + settings.modal_poll_timeout_s
    status_url = _join(f"jobs/{job_id}")
    last_payload: dict = {}
    while time.monotonic() < deadline:
        resp = client.get(status_url, headers=_auth_headers())
        resp.raise_for_status()
        payload = resp.json()
        if isinstance(payload, dict):
            last_payload = payload
            _emit_progress(on_progress, payload)
            status = str(payload.get("status", "")).lower()
            if status == "succeeded":
                return payload
            if status == "failed":
                err = payload.get("error") or "Modal generation failed"
                raise RuntimeError(f"Modal job {job_id} failed: {err}")
        time.sleep(settings.modal_poll_interval_s)
    raise TimeoutError(
        f"Modal job {job_id} did not finish within {settings.modal_poll_timeout_s}s "
        f"(last status: {last_payload.get('status')})"
    )


def _result_from_success(payload: dict, job_id: str | None) -> tuple[str, GenerationResult]:
    """From a succeeded /jobs payload, return (final_glb_url, GenerationResult)."""
    files = payload.get("files") if isinstance(payload.get("files"), dict) else {}
    final_kind = payload.get("final_kind")
    # Prefer Modal's explicit `textured`, else derive from final_kind honestly.
    textured = payload.get("textured")
    if textured is None:
        textured = (str(final_kind).lower() == "textured")
    requested = bool(payload.get("with_texture", payload.get("requested_texture", False)))
    fallback_used = bool(payload.get("fallback_used", False))
    # If texture was requested but the final output is not textured, that is a
    # fallback to the raw mesh — record it honestly.
    if requested and not textured:
        fallback_used = True

    texture_files = payload.get("texture_files") or files.get("texture_files") or []
    if not isinstance(texture_files, list):
        texture_files = []

    # Choose the final GLB URL.
    url = (
        payload.get("glb_url")
        or payload.get("model_url")
        or payload.get("download_url")
    )
    selected_glb = payload.get("selected_glb") or files.get("final_glb") or files.get("model_glb")
    if not url and job_id and selected_glb:
        url = _join(f"download/{job_id}/{selected_glb}")
    if not url:
        raise ValueError("Modal success response did not include a downloadable GLB URL")

    def _abs_opt(value) -> str | None:
        if not value or not isinstance(value, str):
            return None
        return _absolute(value)

    artifacts_raw = payload.get("artifacts")
    artifacts = artifacts_raw if isinstance(artifacts_raw, dict) else {}

    result = GenerationResult(
        final_kind=final_kind,
        textured=bool(textured),
        fallback_used=fallback_used,
        selected_glb=selected_glb or url,
        texture_files=[str(x) for x in texture_files],
        raw_glb_url=_abs_opt(
            payload.get("raw_glb_url") or files.get("raw_glb") or artifacts.get("raw_glb_url")
        ),
        condition_image_url=_abs_opt(
            payload.get("condition_image_url")
            or files.get("condition_image")
            or artifacts.get("condition_image_url")
        ),
        texture_png_url=_abs_opt(
            payload.get("texture_png_url")
            or files.get("texture_png")
            or artifacts.get("texture_png_url")
        ),
        texture_debug_url=_abs_opt(
            payload.get("texture_debug_url")
            or files.get("texture_debug")
            or artifacts.get("texture_debug_url")
        ),
        artifacts=artifacts,
        raw=payload,
    )
    return _absolute(url), result


def _submit_and_collect(
    submit_path: str,
    out_glb: Path,
    *,
    json_body: dict | None = None,
    file_field: tuple[str, str, str] | None = None,
    form: dict | None = None,
    on_progress: ProgressCallback | None = None,
) -> GenerationResult:
    """POST to a submit endpoint, follow the async job to completion, download
    the final GLB to out_glb, and return texture metadata."""
    endpoint = _join(submit_path)
    with httpx.Client(timeout=settings.modal_api_timeout_s, follow_redirects=True) as client:
        if file_field is not None:
            field_name, file_path, mime = file_field
            with open(file_path, "rb") as handle:
                resp = client.post(
                    endpoint,
                    headers=_auth_headers(),
                    files={field_name: (Path(file_path).name, handle, mime)},
                    data=form or {},
                )
        else:
            resp = client.post(endpoint, headers=_auth_headers(), json=json_body or {})
        resp.raise_for_status()
        payload = resp.json()
        if not isinstance(payload, dict):
            raise ValueError("Modal response JSON must be an object")

        status = str(payload.get("status", "")).lower()
        # Surface the initial submit payload too (it may already carry a
        # queued/running progress snapshot).
        _emit_progress(on_progress, payload)
        # Blocking variant: success payload returned directly.
        if status == "succeeded":
            success = payload
        elif status == "failed":
            raise RuntimeError(f"Modal generation failed: {payload.get('error') or 'unknown error'}")
        else:
            job_id = payload.get("job_id") or payload.get("id")
            if not job_id:
                raise ValueError("Modal async response missing job_id")
            success = _poll_job(client, str(job_id), on_progress=on_progress)

        job_id = success.get("job_id") or payload.get("job_id") or payload.get("id")
        glb_url, result = _result_from_success(success, str(job_id) if job_id else None)
        _download_glb(glb_url, out_glb)
        return result


def image_to_3d(
    image_path: Path,
    out_glb: Path,
    with_texture: bool = True,
    on_progress: ProgressCallback | None = None,
) -> GenerationResult:
    mime, _ = mimetypes.guess_type(image_path.name)
    return _submit_and_collect(
        settings.modal_image_to_3d_path,
        out_glb,
        file_field=("file", str(image_path), mime or "image/png"),
        form={"with_texture": str(with_texture).lower()},
        on_progress=on_progress,
    )


def prompt_to_3d(
    prompt: str,
    out_glb: Path,
    with_texture: bool = True,
    on_progress: ProgressCallback | None = None,
) -> GenerationResult:
    return _submit_and_collect(
        settings.modal_prompt_to_3d_path,
        out_glb,
        json_body={"prompt": prompt, "with_texture": with_texture},
        on_progress=on_progress,
    )


def voice_to_3d(
    voice_text: str,
    out_glb: Path,
    with_texture: bool = True,
    on_progress: ProgressCallback | None = None,
) -> GenerationResult:
    """The deployed Modal app accepts a `voice_text` transcript (not raw audio).
    Callers must transcribe first; raw-audio voice-to-3D is not supported by the
    configured endpoint."""
    text = (voice_text or "").strip()
    if not text:
        raise ValueError(
            "Voice-to-3D requires a transcript (voice_text). The configured Modal "
            "endpoint does not accept raw audio uploads."
        )
    return _submit_and_collect(
        settings.modal_prompt_to_3d_path,
        out_glb,
        json_body={"prompt": text, "voice_text": text, "with_texture": with_texture},
        on_progress=on_progress,
    )
