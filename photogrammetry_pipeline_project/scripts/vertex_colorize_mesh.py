import argparse
import json
import struct
from pathlib import Path

import numpy as np
import trimesh


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


def body_band_trim(mesh: trimesh.Trimesh) -> tuple[trimesh.Trimesh, dict]:
    verts = mesh.vertices
    y = verts[:, 1]
    y_lo = float(np.percentile(y, 1.5))
    y_hi = float(np.percentile(y, 97.0))

    x_center = float(np.median(verts[:, 0]))
    z_center = float(np.median(verts[:, 2]))
    radius = np.sqrt((verts[:, 0] - x_center) ** 2 + (verts[:, 2] - z_center) ** 2)
    r_hi = float(np.percentile(radius, 97.5))

    vmask = (y >= y_lo) & (y <= y_hi) & (radius <= r_hi)
    valid = set(np.where(vmask)[0].tolist())
    face_mask = np.array([all(v in valid for v in face) for face in mesh.faces], dtype=bool)
    trimmed = build_submesh(mesh, np.where(face_mask)[0])
    return trimmed, {"y_lo": y_lo, "y_hi": y_hi, "r_hi": r_hi}


def load_cloud(path: Path) -> tuple[np.ndarray, np.ndarray]:
    try:
        cloud = trimesh.load(path, process=False)
        points = np.asarray(cloud.vertices, dtype=np.float64)
        colors = None

        if hasattr(cloud, "colors") and cloud.colors is not None:
            colors = np.asarray(cloud.colors, dtype=np.uint8)
        elif hasattr(cloud, "visual") and getattr(cloud.visual, "vertex_colors", None) is not None:
            colors = np.asarray(cloud.visual.vertex_colors, dtype=np.uint8)

        if colors is not None and len(colors) == len(points):
            if colors.shape[1] >= 4:
                colors = colors[:, :3]
            return points, colors
    except Exception:
        pass

    return load_binary_vertex_cloud_ply(path)


def load_binary_vertex_cloud_ply(path: Path) -> tuple[np.ndarray, np.ndarray]:
    type_map = {
        "char": "i1",
        "uchar": "u1",
        "int8": "i1",
        "uint8": "u1",
        "short": "i2",
        "ushort": "u2",
        "int16": "i2",
        "uint16": "u2",
        "int": "i4",
        "uint": "u4",
        "int32": "i4",
        "uint32": "u4",
        "float": "f4",
        "float32": "f4",
        "double": "f8",
        "float64": "f8",
    }
    type_sizes = {
        "char": 1,
        "uchar": 1,
        "int8": 1,
        "uint8": 1,
        "short": 2,
        "ushort": 2,
        "int16": 2,
        "uint16": 2,
        "int": 4,
        "uint": 4,
        "int32": 4,
        "uint32": 4,
        "float": 4,
        "float32": 4,
        "double": 8,
        "float64": 8,
    }
    struct_map = {
        "char": "b",
        "uchar": "B",
        "int8": "b",
        "uint8": "B",
        "short": "h",
        "ushort": "H",
        "int16": "h",
        "uint16": "H",
        "int": "i",
        "uint": "I",
        "int32": "i",
        "uint32": "I",
        "float": "f",
        "float32": "f",
        "double": "d",
        "float64": "d",
    }

    with path.open("rb") as fh:
        header_lines: list[str] = []
        while True:
            line = fh.readline()
            if not line:
                raise RuntimeError(f"Invalid PLY header in {path}")
            header_lines.append(line.decode("ascii", errors="replace").strip())
            if header_lines[-1] == "end_header":
                break
        data_offset = fh.tell()

    vertex_count = 0
    in_vertex = False
    property_specs: list[tuple[str, ...]] = []
    for line in header_lines:
        parts = line.split()
        if not parts:
            continue
        if parts[:2] == ["format", "binary_little_endian"]:
            continue
        if parts[0] == "element":
            in_vertex = parts[1] == "vertex"
            if in_vertex:
                vertex_count = int(parts[2])
            continue
        if in_vertex and parts[0] == "property":
            if parts[1] == "list":
                property_specs.append(("list", parts[2], parts[3], parts[4]))
            else:
                property_specs.append(("scalar", parts[2], parts[1]))

    if vertex_count <= 0 or not property_specs:
        raise RuntimeError(f"Could not parse binary vertex cloud header for {path}")

    if all(spec[0] == "scalar" for spec in property_specs):
        dtype = np.dtype([(spec[1], "<" + type_map[spec[2]]) for spec in property_specs])
        with path.open("rb") as fh:
            fh.seek(data_offset)
            data = np.fromfile(fh, dtype=dtype, count=vertex_count)
        points = np.column_stack([data["x"], data["y"], data["z"]]).astype(np.float64)
        colors = np.column_stack([data["red"], data["green"], data["blue"]]).astype(np.uint8)
        return points, colors

    fixed_scalars = []
    list_specs = []
    saw_list = False
    for spec in property_specs:
        if spec[0] == "scalar" and not saw_list:
            fixed_scalars.append(spec)
        elif spec[0] == "list":
            saw_list = True
            list_specs.append(spec)
        else:
            raise RuntimeError(f"Unsupported vertex property order in {path}")

    fmt = "<" + "".join(struct_map[spec[2]] for spec in fixed_scalars)
    fixed_struct = struct.Struct(fmt)
    fixed_names = [spec[1] for spec in fixed_scalars]
    points = np.zeros((vertex_count, 3), dtype=np.float64)
    colors = np.zeros((vertex_count, 3), dtype=np.uint8)

    with path.open("rb") as fh:
        fh.seek(data_offset)
        for idx in range(vertex_count):
            values = fixed_struct.unpack(fh.read(fixed_struct.size))
            record = dict(zip(fixed_names, values))
            points[idx] = (record["x"], record["y"], record["z"])
            colors[idx] = (record["red"], record["green"], record["blue"])
            for _, count_type, value_type, _ in list_specs:
                count_raw = fh.read(type_sizes[count_type])
                if len(count_raw) != type_sizes[count_type]:
                    raise RuntimeError(f"Unexpected EOF while reading list count in {path}")
                count = int.from_bytes(count_raw, byteorder="little", signed=count_type.startswith("int"))
                fh.seek(count * type_sizes[value_type], 1)

    return points, colors


def quantize(points: np.ndarray, origin: np.ndarray, voxel_size: float) -> np.ndarray:
    return np.floor((points - origin) / voxel_size).astype(np.int32)


def build_voxel_aggregates(
    points: np.ndarray,
    colors: np.ndarray,
    origin: np.ndarray,
    voxel_size: float,
) -> tuple[dict[tuple[int, int, int], int], np.ndarray, np.ndarray]:
    keys = quantize(points, origin, voxel_size)
    buckets: dict[tuple[int, int, int], list[np.ndarray | int]] = {}
    for i, key in enumerate(keys):
        key_t = (int(key[0]), int(key[1]), int(key[2]))
        if key_t not in buckets:
            buckets[key_t] = [points[i].astype(np.float64), colors[i].astype(np.float64), 1]
        else:
            buckets[key_t][0] += points[i]
            buckets[key_t][1] += colors[i]
            buckets[key_t][2] += 1

    lookup: dict[tuple[int, int, int], int] = {}
    mean_points = np.zeros((len(buckets), 3), dtype=np.float64)
    mean_colors = np.zeros((len(buckets), 3), dtype=np.float64)
    for idx, (key_t, (sum_p, sum_c, count)) in enumerate(buckets.items()):
        lookup[key_t] = idx
        mean_points[idx] = sum_p / count
        mean_colors[idx] = sum_c / count
    return lookup, mean_points, mean_colors


def offsets_for_radius(radius: int) -> list[tuple[int, int, int]]:
    offsets: list[tuple[int, int, int]] = []
    for dx in range(-radius, radius + 1):
        for dy in range(-radius, radius + 1):
            for dz in range(-radius, radius + 1):
                if max(abs(dx), abs(dy), abs(dz)) == radius:
                    offsets.append((dx, dy, dz))
    return offsets


def colorize_vertices(
    vertices: np.ndarray,
    origin: np.ndarray,
    voxel_size: float,
    fine_lookup: dict[tuple[int, int, int], int],
    fine_points: np.ndarray,
    fine_colors: np.ndarray,
    coarse_lookup: dict[tuple[int, int, int], int],
    coarse_points: np.ndarray,
    coarse_colors: np.ndarray,
) -> tuple[np.ndarray, dict]:
    mesh_keys = quantize(vertices, origin, voxel_size)
    unique_keys, inverse = np.unique(mesh_keys, axis=0, return_inverse=True)
    counts = np.bincount(inverse)
    order = np.argsort(inverse, kind="stable")
    group_starts = np.concatenate(([0], np.cumsum(counts[:-1])))

    fine_shells = {radius: offsets_for_radius(radius) for radius in range(4)}
    coarse_shells = {radius: offsets_for_radius(radius) for radius in range(3)}
    vertex_colors = np.zeros((len(vertices), 3), dtype=np.uint8)

    fine_hits = 0
    coarse_hits = 0
    fallback_hits = 0

    for idx, key in enumerate(unique_keys):
        key_t = (int(key[0]), int(key[1]), int(key[2]))
        start = int(group_starts[idx])
        stop = start + int(counts[idx])
        group_idx = order[start:stop]
        centers = vertices[group_idx]

        candidates: list[int] = []
        for radius in range(4):
            for dx, dy, dz in fine_shells[radius]:
                match = fine_lookup.get((key_t[0] + dx, key_t[1] + dy, key_t[2] + dz))
                if match is not None:
                    candidates.append(match)
            if len(candidates) >= 4:
                break

        if candidates:
            pts = fine_points[candidates]
            cols = fine_colors[candidates].astype(np.float64)
            d2 = np.sum((centers[:, None, :] - pts[None, :, :]) ** 2, axis=2)
            choose = min(6, len(candidates))
            nearest = np.argsort(d2, axis=1)[:, :choose]
            nearest_d2 = np.take_along_axis(d2, nearest, axis=1)
            nearest_cols = cols[nearest]
            weights = 1.0 / (nearest_d2 + 1e-8)
            color = np.sum(nearest_cols * weights[:, :, None], axis=1) / np.sum(weights, axis=1)[:, None]
            vertex_colors[group_idx] = np.clip(np.round(color), 0, 255).astype(np.uint8)
            fine_hits += len(group_idx)
            continue

        coarse_keys = np.floor((centers - origin) / (voxel_size * 2.0)).astype(np.int32)
        coarse_key = tuple(int(v) for v in np.rint(np.median(coarse_keys, axis=0)).astype(np.int32))
        coarse_candidates: list[int] = []
        for radius in range(3):
            for dx, dy, dz in coarse_shells[radius]:
                match = coarse_lookup.get((coarse_key[0] + dx, coarse_key[1] + dy, coarse_key[2] + dz))
                if match is not None:
                    coarse_candidates.append(match)
            if coarse_candidates:
                break

        if coarse_candidates:
            pts = coarse_points[coarse_candidates]
            cols = coarse_colors[coarse_candidates].astype(np.float64)
            d2 = np.sum((centers[:, None, :] - pts[None, :, :]) ** 2, axis=2)
            choose = min(6, len(coarse_candidates))
            nearest = np.argsort(d2, axis=1)[:, :choose]
            nearest_d2 = np.take_along_axis(d2, nearest, axis=1)
            nearest_cols = cols[nearest]
            weights = 1.0 / (nearest_d2 + 1e-8)
            color = np.sum(nearest_cols * weights[:, :, None], axis=1) / np.sum(weights, axis=1)[:, None]
            vertex_colors[group_idx] = np.clip(np.round(color), 0, 255).astype(np.uint8)
            coarse_hits += len(group_idx)
        else:
            vertex_colors[group_idx] = np.array([196, 186, 166], dtype=np.uint8)
            fallback_hits += len(group_idx)

    return vertex_colors, {
        "unique_mesh_voxels": int(len(unique_keys)),
        "fine_hits": int(fine_hits),
        "coarse_hits": int(coarse_hits),
        "fallback_hits": int(fallback_hits),
    }


def smooth_vertex_colors(
    colors: np.ndarray,
    faces: np.ndarray,
    iterations: int,
    strength: float,
) -> np.ndarray:
    if iterations <= 0 or strength <= 0.0 or len(colors) == 0 or len(faces) == 0:
        return colors

    strength = float(np.clip(strength, 0.0, 1.0))
    src = np.concatenate(
        [
            faces[:, 0],
            faces[:, 1],
            faces[:, 2],
            faces[:, 1],
            faces[:, 2],
            faces[:, 0],
        ]
    )
    dst = np.concatenate(
        [
            faces[:, 1],
            faces[:, 2],
            faces[:, 0],
            faces[:, 0],
            faces[:, 1],
            faces[:, 2],
        ]
    )
    counts = np.bincount(src, minlength=len(colors)).astype(np.float64)
    counts[counts == 0] = 1.0

    smoothed = colors.astype(np.float64)
    for _ in range(iterations):
        neighbor_sum = np.zeros_like(smoothed)
        for channel in range(3):
            np.add.at(neighbor_sum[:, channel], src, smoothed[dst, channel])
        neighbor_mean = neighbor_sum / counts[:, None]
        smoothed = smoothed * (1.0 - strength) + neighbor_mean * strength

    return np.clip(np.round(smoothed), 0, 255).astype(np.uint8)


def smooth_geometry(
    vertices: np.ndarray,
    faces: np.ndarray,
    iterations: int,
    lam: float,
    mu: float,
) -> np.ndarray:
    if iterations <= 0 or len(vertices) == 0 or len(faces) == 0:
        return vertices

    src = np.concatenate(
        [
            faces[:, 0],
            faces[:, 1],
            faces[:, 2],
            faces[:, 1],
            faces[:, 2],
            faces[:, 0],
        ]
    )
    dst = np.concatenate(
        [
            faces[:, 1],
            faces[:, 2],
            faces[:, 0],
            faces[:, 0],
            faces[:, 1],
            faces[:, 2],
        ]
    )
    counts = np.bincount(src, minlength=len(vertices)).astype(np.float64)
    counts[counts == 0] = 1.0

    verts = vertices.astype(np.float64).copy()

    def laplacian_step(points: np.ndarray, strength: float) -> np.ndarray:
        neighbor_sum = np.zeros_like(points)
        for channel in range(3):
            np.add.at(neighbor_sum[:, channel], src, points[dst, channel])
        neighbor_mean = neighbor_sum / counts[:, None]
        return points + strength * (neighbor_mean - points)

    for _ in range(iterations):
        verts = laplacian_step(verts, lam)
        verts = laplacian_step(verts, mu)

    return verts


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mesh", required=True)
    parser.add_argument("--cloud", required=True)
    parser.add_argument("--out-dir", required=True)
    parser.add_argument("--voxel-size", type=float, default=0.0)
    parser.add_argument("--flip-output", action="store_true")
    parser.add_argument("--body-band-trim", action="store_true")
    parser.add_argument("--color-smooth-iters", type=int, default=1)
    parser.add_argument("--color-smooth-strength", type=float, default=0.22)
    parser.add_argument("--geometry-smooth-iters", type=int, default=0)
    parser.add_argument("--geometry-smooth-lambda", type=float, default=0.14)
    parser.add_argument("--geometry-smooth-mu", type=float, default=-0.15)
    args = parser.parse_args()

    mesh_path = Path(args.mesh).resolve()
    cloud_path = Path(args.cloud).resolve()
    out_dir = Path(args.out_dir).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    mesh = trimesh.load(mesh_path, force="mesh", process=False)
    cloud_points, cloud_colors = load_cloud(cloud_path)

    mesh = keep_largest_component(mesh)
    trim_stats: dict[str, float | int] = {}
    if args.body_band_trim:
        mesh, trim_stats = body_band_trim(mesh)
        mesh = keep_largest_component(mesh)

    if args.geometry_smooth_iters > 0:
        mesh.vertices = smooth_geometry(
            mesh.vertices,
            mesh.faces,
            iterations=args.geometry_smooth_iters,
            lam=args.geometry_smooth_lambda,
            mu=args.geometry_smooth_mu,
        )

    origin = np.minimum(mesh.vertices.min(axis=0), cloud_points.min(axis=0))
    bbox_diag = float(np.linalg.norm(cloud_points.max(axis=0) - cloud_points.min(axis=0)))
    voxel_size = args.voxel_size if args.voxel_size > 0 else max(bbox_diag / 320.0, 1e-4)

    fine_lookup, fine_points, fine_colors = build_voxel_aggregates(cloud_points, cloud_colors, origin, voxel_size)
    coarse_lookup, coarse_points, coarse_colors = build_voxel_aggregates(cloud_points, cloud_colors, origin, voxel_size * 2.0)

    vertex_colors, stats = colorize_vertices(
        mesh.vertices,
        origin,
        voxel_size,
        fine_lookup,
        fine_points,
        fine_colors,
        coarse_lookup,
        coarse_points,
        coarse_colors,
    )
    vertex_colors = smooth_vertex_colors(
        vertex_colors,
        mesh.faces,
        iterations=args.color_smooth_iters,
        strength=args.color_smooth_strength,
    )

    if args.flip_output:
        mesh.vertices[:, 1] *= -1.0
        mesh.vertices[:, 2] *= -1.0

    rgba = np.concatenate([vertex_colors, np.full((len(vertex_colors), 1), 255, dtype=np.uint8)], axis=1)
    mesh.visual.vertex_colors = rgba

    out_ply = out_dir / "object_reconstruction_vertexcolor.ply"
    out_glb = out_dir / "object_reconstruction_vertexcolor.glb"
    mesh.export(out_ply)
    mesh.export(out_glb)

    report = {
        "mesh": str(mesh_path),
        "cloud": str(cloud_path),
        "output_ply": str(out_ply),
        "output_glb": str(out_glb),
        "voxel_size": voxel_size,
        "cloud_voxels_fine": int(len(fine_points)),
        "cloud_voxels_coarse": int(len(coarse_points)),
        "vertices": int(len(mesh.vertices)),
        "faces": int(len(mesh.faces)),
        "color_smooth_iters": int(args.color_smooth_iters),
        "color_smooth_strength": float(args.color_smooth_strength),
        "geometry_smooth_iters": int(args.geometry_smooth_iters),
        "geometry_smooth_lambda": float(args.geometry_smooth_lambda),
        "geometry_smooth_mu": float(args.geometry_smooth_mu),
    }
    report.update(stats)
    report.update(trim_stats)
    (out_dir / "vertexcolor_report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(f"Vertex-color mesh written to {out_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
