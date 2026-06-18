Put your downloaded photogrammetry binaries here.

Expected structure:

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

If your app keeps tools in another location, do not move them; pass that location with:

- `run_pipeline.ps1 -ToolsRoot <path>`
- or `scripts/run_photogrammetry.py --tools-root <path>`
