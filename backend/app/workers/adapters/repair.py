from __future__ import annotations

from pathlib import Path


def repair_mesh(in_glb: Path, out_glb: Path) -> None:
    """Clean up a mesh (merge vertices, drop degenerate/duplicate faces, fix
    winding/normals) and re-export as GLB.

    This performs a *real* repair using trimesh. If trimesh is not available it
    raises a clear error instead of silently copying the input through (which
    would pretend a repair happened when it did not).
    """
    try:
        import trimesh
    except Exception as exc:  # pragma: no cover - depends on worker image
        raise RuntimeError(
            "Mesh repair is not available: the 'trimesh' library is not installed "
            "in this worker. Install trimesh or disable the repair step."
        ) from exc

    scene_or_mesh = trimesh.load(str(in_glb), force="scene", process=False)

    if isinstance(scene_or_mesh, trimesh.Scene):
        geometries = [
            g for g in scene_or_mesh.geometry.values()
            if hasattr(g, "vertices") and hasattr(g, "faces")
        ]
        if not geometries:
            raise RuntimeError("Input GLB contains no mesh geometry to repair")
        mesh = trimesh.util.concatenate(tuple(geometries))
    else:
        mesh = scene_or_mesh

    if not hasattr(mesh, "vertices") or len(mesh.vertices) == 0 or len(mesh.faces) == 0:
        raise RuntimeError("Input GLB mesh is empty; nothing to repair")

    # Standard, non-destructive cleanup.
    mesh.merge_vertices()
    mesh.update_faces(mesh.unique_faces())
    mesh.update_faces(mesh.nondegenerate_faces())
    mesh.remove_unreferenced_vertices()
    try:
        mesh.fix_normals()
    except Exception:
        pass

    out_glb.parent.mkdir(parents=True, exist_ok=True)
    mesh.export(str(out_glb), file_type="glb")

    if not out_glb.exists() or out_glb.stat().st_size <= 0:
        raise RuntimeError("Mesh repair produced an empty output file")
