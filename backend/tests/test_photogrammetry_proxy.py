from __future__ import annotations

"""Unit tests for the photogrammetry Modal proxy helpers.

These cover the pure logic that does not require the database: the signed
download-token round-trip, safe ZIP extraction (path-traversal hardening), and
primary-model selection. The HTTP routes themselves are exercised by the
integration suite (which needs the DB).
"""

import io
import time
import zipfile

import pytest

from app.services import photogrammetry_modal as modal_pg
from app.services.photogrammetry_jobs import photogrammetry_jobs


def _zip_with(names_to_bytes: dict[str, bytes]) -> bytes:
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
        for name, data in names_to_bytes.items():
            zf.writestr(name, data)
    return buf.getvalue()


def test_download_token_roundtrip():
    token = photogrammetry_jobs.make_download_token("job123", "user-abc")
    assert photogrammetry_jobs.verify_download_token("job123", token) == "user-abc"


def test_download_token_rejects_other_job():
    token = photogrammetry_jobs.make_download_token("job123", "user-abc")
    assert photogrammetry_jobs.verify_download_token("otherjob", token) is None


def test_download_token_rejects_tamper():
    token = photogrammetry_jobs.make_download_token("job123", "user-abc")
    tampered = token[:-1] + ("0" if token[-1] != "0" else "1")
    assert photogrammetry_jobs.verify_download_token("job123", tampered) is None


def test_download_token_rejects_expired(monkeypatch):
    token = photogrammetry_jobs.make_download_token("job123", "user-abc")
    # Jump past the token lifetime.
    real_time = time.time
    monkeypatch.setattr(time, "time", lambda: real_time() + 10**9)
    assert photogrammetry_jobs.verify_download_token("job123", token) is None


def test_extract_zip_writes_files(tmp_path):
    data = _zip_with({"model.glb": b"GLB", "report.json": b"{}"})
    saved = modal_pg.extract_zip(data, tmp_path)
    assert set(saved) == {"model.glb", "report.json"}
    assert (tmp_path / "model.glb").read_bytes() == b"GLB"


def test_extract_zip_blocks_traversal(tmp_path):
    data = _zip_with({"../escape.txt": b"x", "ok/model.glb": b"GLB"})
    saved = modal_pg.extract_zip(data, tmp_path)
    # The traversal entry is dropped; the safe one survives.
    assert "ok/model.glb" in saved
    assert not (tmp_path.parent / "escape.txt").exists()


def test_extract_zip_rejects_non_zip(tmp_path):
    with pytest.raises(modal_pg.PhotogrammetryModalError):
        modal_pg.extract_zip(b"not a zip", tmp_path)


def test_find_primary_model_prefers_glb(tmp_path):
    (tmp_path / "mesh.obj").write_bytes(b"o")
    (tmp_path / "mesh.ply").write_bytes(b"p")
    (tmp_path / "mesh.glb").write_bytes(b"g")
    chosen = modal_pg.find_primary_model(tmp_path)
    assert chosen is not None and chosen.suffix == ".glb"


def test_find_primary_model_none_when_absent(tmp_path):
    (tmp_path / "report.json").write_bytes(b"{}")
    assert modal_pg.find_primary_model(tmp_path) is None
