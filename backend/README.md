# R2V Studio Backend (FastAPI + Postgres + Redis + MinIO + Celery + Stripe)

Self-hostable, zero/low-budget backend for the R2V Studio graduation project.

## Local run
```bash
cp .env.example .env
docker compose up --build
```
API: http://localhost:${API_PORT:-18001}/docs  
MinIO: internal-only (not published to host to avoid port conflicts).

## Local photogrammetry on Windows
For the photogrammetry pipeline, the fastest dev setup is:
- keep Postgres / Redis / MinIO in Docker
- run the FastAPI backend locally on Windows
- use Windows COLMAP / OpenMVS binaries from `photogrammetry_pipeline_project/tools`

Expected tool layout:
```text
photogrammetry_pipeline_project/
  tools/
    colmap/
      bin/
        colmap.exe
    openmvs/
      vc17/
        x64/
          Release/
            InterfaceCOLMAP.exe
            DensifyPointCloud.exe
            ReconstructMesh.exe
            TextureMesh.exe
```

Start the backend in this mode:
```powershell
cd D:\grad\R2V_GRAD_2-main\backend
.\start-local-api.ps1
```

That script:
- starts `db`, `redis`, `minio`, and `minio-init` in Docker
- points the backend to `127.0.0.1` service endpoints
- validates the Windows photogrammetry binaries before startup
- launches `uvicorn` on `http://127.0.0.1:18001`

If you only want to restart the API and leave Docker services alone:
```powershell
.\start-local-api.ps1 -SkipSupportServices
```

You can also copy `.env.local.example` to `.env.local` for reference, but the script already sets the critical local photogrammetry variables explicitly.

## Notes
- AI/Photogrammetry integrations are implemented as adapter interfaces with safe placeholders.
  Replace the adapters in `app/workers/adapters/` with your real Stable Diffusion / Hunyuan3D-2 / repair / photogrammetry code.

### Modal AI integration
The image-to-3D adapter now calls a Modal-hosted FastAPI app. Configure these in `backend/.env` if your endpoints differ:
- `MODAL_API_URL` (base URL, defaults to the provided Modal app)
- `MODAL_IMAGE_TO_3D_PATH` (default `/image-to-3d`)
- `MODAL_PROMPT_TO_3D_PATH` (default `/text-to-3d`)
- `MODAL_API_TIMEOUT_S` (long-running GPU jobs; default 900 seconds)

AI jobs support optional image uploads by sending `settings.image_base64`, `settings.image_filename`,
and (optionally) `settings.image_mime`. When an image is provided, the backend posts it to the Modal
image-to-3D endpoint; otherwise it uses the prompt-to-3D endpoint for text-only jobs.


### Expose MinIO (optional)
If you really want to open the MinIO Console in your browser, edit `docker-compose.yml` and add a `ports:` section under `minio:` like:
```yaml
ports:
  - "9000:9000"   # API
  - "9001:9001"   # Console
```
Then re-run `docker compose up --build`.
