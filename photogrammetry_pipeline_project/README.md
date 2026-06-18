# Photogrammetry Pipeline Project

This folder is a clean package of the photogrammetry pipeline we built in this workspace.

It takes a ZIP of object photos and produces:

- extracted / preprocessed images
- masks
- sparse cloud
- dense cloud
- mesh
- final `OBJ`, `PLY`, and `GLB`
- optional `vertex-color` textured mesh, which is the newer fallback texture method added later in this project

## Folder Layout

- `scripts/`
- `inputs/`
- `outputs/`
- `tools/`
- `requirements.txt`
- `run_pipeline.ps1`

## External Tools Expected

Place these binaries under `tools/`:

- `tools/colmap/bin/colmap.exe`
- `tools/colmap/bin/colmap`
- `tools/openmvs/vc17/x64/Release/InterfaceCOLMAP.exe`
- `tools/openmvs/vc17/x64/Release/DensifyPointCloud.exe`
- `tools/openmvs/vc17/x64/Release/ReconstructMesh.exe`
- `tools/openmvs/vc17/x64/Release/TextureMesh.exe`
- `tools/openmvs/bin/InterfaceCOLMAP`
- `tools/openmvs/bin/DensifyPointCloud`
- `tools/openmvs/bin/ReconstructMesh`
- `tools/openmvs/bin/TextureMesh`

If your app stores them elsewhere, pass `--tools-root` to `scripts/run_photogrammetry.py`, or use the `-ToolsRoot` parameter in `run_pipeline.ps1`.

Windows and Linux layouts are both supported now. On Linux and in Docker, use the non-`.exe` paths.

## Python Dependencies

Install:

```powershell
pip install -r requirements.txt
```

## Main Entry Point

The main pipeline entry point is:

- [scripts/run_photogrammetry.py](C:\Users\seifh\OneDrive - Nile University\Documents\Playground\photogrammetry_pipeline_project\scripts\run_photogrammetry.py)

## Recommended Run Modes

Standard OpenMVS texture:

```powershell
powershell -ExecutionPolicy Bypass -File .\run_pipeline.ps1 -ZipPath .\inputs\photos.zip -RunName run_openmvs -TextureMode openmvs
```

Newer vertex-color texture fallback:

```powershell
powershell -ExecutionPolicy Bypass -File .\run_pipeline.ps1 -ZipPath .\inputs\photos.zip -RunName run_vertexcolor -TextureMode vertexcolor
```

## App Integration

The simplest integration is to have your app spawn one process:

```text
powershell -ExecutionPolicy Bypass -File run_pipeline.ps1 -ZipPath <zip> -RunName <run_name> -TextureMode vertexcolor
```

When the run completes, read outputs from:

- `outputs/<run_name>/final/`
- `outputs/<run_name>/report.json`
- `outputs/<run_name>/report.md`

## Notes

- `vertexcolor` is the latest texture-related method added in this project. It avoids the unreliable OpenMVS atlas bake by coloring the mesh directly from the dense colored cloud.
- `openmvs` is still available if you want traditional OBJ/MTL/JPG texture output.
