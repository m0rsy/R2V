import argparse
import json
from pathlib import Path

import numpy as np
import trimesh
from scipy.spatial import cKDTree
from trimesh.voxel import ops as voxel_ops


def build_submesh(mesh: trimesh.Trimesh, face_idx: np.ndarray) -> trimesh.Trimesh:
    faces = mesh.faces[face_idx]
    used = np.unique(faces.reshape(-1))
    remap = -np.ones(len(mesh.vertices), dtype=np.int64)
    remap[used] = np.arange(len(used), dtype=np.int64)
    new_faces = remap[faces]
    new_vertices = mesh.vertices[used].copy()
    submesh = trimesh.Trimesh(vertices=new_vertices, faces=new_faces, process=False)
    submesh.remove_unreferenced_vertices()
    submesh.remove_infinite_values()
    return submesh


def keep_largest_component(mesh: trimesh.Trimesh) -> trimesh.Trimesh:
    face_nodes = np.arange(len(mesh.faces), dtype=np.int64)
    comps = trimesh.graph.connected_components(mesh.face_adjacency, nodes=face_nodes, min_len=1)
    if not comps:
        return mesh
    largest = max((np.array(comp, dtype=np.int64) for comp in comps), key=len)
    return build_submesh(mesh, largest)


def load_cloud(path: Path) -> np.ndarray:
    cloud = trimesh.load(path, process=False)
    points = np.asarray(cloud.vertices, dtype=np.float64)
    if points.ndim != 2 or points.shape[1] != 3:
        raise RuntimeError(f"Unexpected point cloud shape in {path}: {points.shape}")
    return points


def filter_points(points: np.ndarray, radius: float, min_neighbors: int) -> np.ndarray:
    if len(points) == 0:
        return points
    tree = cKDTree(points)
    neighborhoods = tree.query_ball_point(points, r=radius)
    keep = np.array([len(ids) >= min_neighbors for ids in neighborhoods], dtype=bool)
    filtered = points[keep]
    return filtered if len(filtered) >= 32 else points


def choose_pitch(points: np.ndarray, explicit: float) -> tuple[float, float]:
    if explicit > 0:
        bbox_diag = float(np.linalg.norm(points.max(axis=0) - points.min(axis=0)))
        return explicit, bbox_diag

    bbox_diag = float(np.linalg.norm(points.max(axis=0) - points.min(axis=0)))
    tree = cKDTree(points)
    dists, _ = tree.query(points, k=2)
    nn = dists[:, 1]
    median_nn = float(np.median(nn))
    pitch = max(bbox_diag / 85.0, median_nn * 2.8, 1e-4)
    return float(pitch), bbox_diag


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--cloud", required=True)
    parser.add_argument("--out-mesh", required=True)
    parser.add_argument("--pitch", type=float, default=0.0)
    parser.add_argument("--min-neighbors", type=int, default=3)
    parser.add_argument("--smooth-iters", type=int, default=10)
    args = parser.parse_args()

    cloud_path = Path(args.cloud).resolve()
    out_mesh = Path(args.out_mesh).resolve()
    out_mesh.parent.mkdir(parents=True, exist_ok=True)

    points = load_cloud(cloud_path)
    pitch, bbox_diag = choose_pitch(points, args.pitch)
    radius = pitch * 1.65
    filtered = filter_points(points, radius=radius, min_neighbors=args.min_neighbors)

    mesh = voxel_ops.points_to_marching_cubes(filtered, pitch=pitch)
    mesh = keep_largest_component(mesh)
    mesh.remove_unreferenced_vertices()
    trimesh.smoothing.filter_taubin(mesh, lamb=0.45, nu=-0.5, iterations=args.smooth_iters)
    mesh.remove_unreferenced_vertices()
    mesh = keep_largest_component(mesh)

    mesh.export(out_mesh)

    report = {
        "cloud": str(cloud_path),
        "out_mesh": str(out_mesh),
        "input_points": int(len(points)),
        "filtered_points": int(len(filtered)),
        "pitch": pitch,
        "neighbor_radius": radius,
        "bbox_diag": bbox_diag,
        "vertices": int(len(mesh.vertices)),
        "faces": int(len(mesh.faces)),
    }
    (out_mesh.with_suffix(".json")).write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(f"Sparse fallback mesh written to {out_mesh}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
