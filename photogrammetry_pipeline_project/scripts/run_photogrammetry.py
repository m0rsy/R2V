import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path


def run_cmd(name: str, args: list[str], logs_dir: Path) -> Path:
    log_path = logs_dir / f"{name}.log"
    with log_path.open("w", encoding="utf-8", errors="replace") as f:
        proc = subprocess.run(args, stdout=f, stderr=subprocess.STDOUT, text=True)
    if proc.returncode != 0:
        raise RuntimeError(f"{name} failed with exit code {proc.returncode}. See {log_path}")
    return log_path


def parse_model_text(text: str) -> dict:
    def grab(pattern: str):
        m = re.search(pattern, text)
        return m.group(1) if m else None

    return {
        "registered_images": int(grab(r"Registered images:\s*(\d+)")) if grab(r"Registered images:\s*(\d+)") else 0,
        "points": int(grab(r"Points:\s*(\d+)")) if grab(r"Points:\s*(\d+)") else 0,
        "mean_track_length": float(grab(r"Mean track length:\s*([0-9.]+)")) if grab(r"Mean track length:\s*([0-9.]+)") else None,
        "mean_reprojection_error_px": float(grab(r"Mean reprojection error:\s*([0-9.]+)")) if grab(r"Mean reprojection error:\s*([0-9.]+)") else None,
    }


def parse_map_kd(mtl_text: str) -> str | None:
    for line in mtl_text.splitlines():
        s = line.strip()
        if s.lower().startswith("map_kd "):
            return s.split(maxsplit=1)[1].strip()
    return None


def resolve_tool(tools_root: Path, relative_candidates: list[str], label: str) -> Path:
    for candidate in relative_candidates:
        path = tools_root / Path(candidate)
        if path.exists():
            return path
    tried = ", ".join(relative_candidates)
    raise RuntimeError(f"Missing required tool '{label}'. Looked for: {tried} under {tools_root}")


def write_viewer(out_dir: Path, image_names: list[str]) -> None:
    files_js = json.dumps(image_names)
    html = f"""<!doctype html>
<html lang=\"en\"><head>
<meta charset=\"utf-8\" /><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\" />
<title>Photogrammetry Side-by-Side Viewer</title>
<style>
body{{margin:0;background:#0b1220;color:#e5e7eb;font-family:Segoe UI,Arial,sans-serif}}
.grid{{display:grid;grid-template-columns:42% 58%;gap:10px;padding:10px;box-sizing:border-box;height:100vh}}
.panel{{background:#111827;border:1px solid #334155;border-radius:10px;overflow:hidden;display:flex;flex-direction:column}}
.title{{padding:8px 10px;border-bottom:1px solid #334155;font-weight:600}}
#photo{{width:100%;height:calc(100% - 92px);object-fit:contain;background:#000}}
.controls{{padding:8px;border-top:1px solid #334155}}
button{{background:#1e293b;color:#e5e7eb;border:1px solid #334155;border-radius:6px;padding:5px 9px}}
#view{{width:100%;height:100%;background:#0f1624}} #err{{padding:6px 8px;color:#fca5a5;font-size:12px;min-height:22px}}
</style>
<script type=\"module\" src=\"https://ajax.googleapis.com/ajax/libs/model-viewer/4.0.0/model-viewer.min.js\"></script>
</head><body>
<div class=\"grid\">
<section class=\"panel\"><div class=\"title\">Input Photos</div><img id=\"photo\" alt=\"photo\" /><div class=\"controls\"><button id=\"prev\">Prev</button> <button id=\"next\">Next</button> <span id=\"meta\"></span></div></section>
<section class=\"panel\"><div class=\"title\">Reconstructed 3D Model (Textured GLB)</div><div id=\"view\"></div><div id=\"err\"></div></section>
</div>
<script>
(function(){{
  const files = {files_js};
  let idx = 0;
  const img = document.getElementById('photo');
  const meta = document.getElementById('meta');
  function draw() {{
    if (!files.length) return;
    img.src = 'images_preprocessed/' + files[idx];
    meta.textContent = (idx + 1) + '/' + files.length + ' ' + files[idx];
  }}
  document.getElementById('prev').onclick = () => {{ idx=(idx-1+files.length)%files.length; draw(); }};
  document.getElementById('next').onclick = () => {{ idx=(idx+1)%files.length; draw(); }};
  draw();

  const view = document.getElementById('view');
  const err = document.getElementById('err');
  const mv = document.createElement('model-viewer');
  mv.style.width = '100%';
  mv.style.height = '100%';
  mv.setAttribute('src', 'final/object_reconstruction.glb');
  mv.setAttribute('camera-controls', '');
  mv.setAttribute('shadow-intensity', '0.9');
  mv.setAttribute('exposure', '1.2');
  mv.setAttribute('environment-image', 'neutral');
  mv.setAttribute('tone-mapping', 'neutral');
  mv.setAttribute('camera-orbit', '0deg 75deg auto');
  mv.addEventListener('error', () => {{ err.textContent = 'Failed to load GLB. Check final/object_reconstruction.glb'; }});
  view.appendChild(mv);
}})();
</script>
</body></html>
"""
    (out_dir / "viewer_side_by_side.html").write_text(html, encoding="utf-8")


def select_best_sparse_model(colmap: Path, sparse_root: Path, logs: Path) -> tuple[Path, dict, Path]:
    best_model = None
    best_stats = None
    best_log = None
    for model_dir in sorted([p for p in sparse_root.iterdir() if p.is_dir()]):
        log = run_cmd(f"06_sparse_analysis_model_{model_dir.name}", [str(colmap), "model_analyzer", "--path", str(model_dir)], logs)
        stats = parse_model_text(log.read_text(encoding="utf-8", errors="replace"))
        if best_stats is None or stats["registered_images"] > best_stats["registered_images"]:
            best_model, best_stats, best_log = model_dir, stats, log
    if best_model is None:
        raise RuntimeError("No sparse model directories were produced")
    return best_model, best_stats, best_log


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--zip", required=True)
    parser.add_argument("--run-name", default="run_photos")
    parser.add_argument("--root", default=str(Path(__file__).resolve().parents[1]))
    parser.add_argument("--python-exe", default=sys.executable)
    parser.add_argument("--tools-root", default="")
    parser.add_argument("--openmvs-resolution-level", type=int, default=3)
    parser.add_argument("--openmvs-number-views", type=int, default=2)
    parser.add_argument("--mapper-max-reproj-error", type=float, default=1.5)
    parser.add_argument("--mapper-min-matches", type=int, default=28)
    parser.add_argument("--mapper-min-inliers", type=int, default=28)
    parser.add_argument("--mesh-remove-spurious", type=int, default=40)
    parser.add_argument("--mesh-smooth-iters", type=int, default=4)
    parser.add_argument("--mesh-close-holes", type=int, default=12)
    parser.add_argument("--texture-empty-color", type=int, default=0)
    parser.add_argument("--texture-resolution-level", type=int, default=1)
    parser.add_argument("--no-strict-mask", action="store_true")
    parser.add_argument("--generate-vertex-colors", action="store_true")
    parser.add_argument("--skip-openmvs-texture", action="store_true")
    args = parser.parse_args()

    root = Path(args.root).resolve()
    zip_path = Path(args.zip).resolve()
    tools_root = Path(args.tools_root).resolve() if args.tools_root else (root / "tools")

    colmap = resolve_tool(
        tools_root,
        [
            "colmap/bin/colmap.exe",
            "colmap/bin/colmap",
            "colmap/colmap.exe",
            "colmap/colmap",
        ],
        "colmap",
    )
    interface_colmap = resolve_tool(
        tools_root,
        [
            "openmvs/vc17/x64/Release/InterfaceCOLMAP.exe",
            "openmvs/bin/InterfaceCOLMAP",
            "openmvs/bin/InterfaceCOLMAP.exe",
            "openmvs/InterfaceCOLMAP",
        ],
        "InterfaceCOLMAP",
    )
    densify = resolve_tool(
        tools_root,
        [
            "openmvs/vc17/x64/Release/DensifyPointCloud.exe",
            "openmvs/bin/DensifyPointCloud",
            "openmvs/bin/DensifyPointCloud.exe",
            "openmvs/DensifyPointCloud",
        ],
        "DensifyPointCloud",
    )
    reconstruct = resolve_tool(
        tools_root,
        [
            "openmvs/vc17/x64/Release/ReconstructMesh.exe",
            "openmvs/bin/ReconstructMesh",
            "openmvs/bin/ReconstructMesh.exe",
            "openmvs/ReconstructMesh",
        ],
        "ReconstructMesh",
    )
    texture = resolve_tool(
        tools_root,
        [
            "openmvs/vc17/x64/Release/TextureMesh.exe",
            "openmvs/bin/TextureMesh",
            "openmvs/bin/TextureMesh.exe",
            "openmvs/TextureMesh",
        ],
        "TextureMesh",
    )
    py = Path(args.python_exe)

    if os.name != "nt":
        for tool in [colmap, interface_colmap, densify, reconstruct, texture]:
            tool.chmod(tool.stat().st_mode | 0o111)

    out = root / "outputs" / args.run_name
    img_extract = out / "images_extracted"
    img_pre = out / "images_preprocessed"
    mask_dir = out / "masks"
    intermediate = out / "intermediate"
    final = out / "final"
    logs = out / "logs"
    colmap_ws = out / "colmap_workspace"
    openmvs_ws = out / "openmvs_workspace"

    if out.exists():
        shutil.rmtree(out)
    for p in [img_extract, img_pre, mask_dir, intermediate, final, logs, colmap_ws, openmvs_ws]:
        p.mkdir(parents=True, exist_ok=True)

    shutil.unpack_archive(str(zip_path), str(img_extract))

    image_stats_json = intermediate / "image_stats.json"
    preprocess_cmd = [
        str(py),
        str(root / "scripts" / "preprocess_with_masks.py"),
        "--input-dir", str(img_extract),
        "--output-dir", str(img_pre),
        "--mask-dir", str(mask_dir),
        "--stats-json", str(image_stats_json),
    ]
    if not args.no_strict_mask:
        preprocess_cmd.append("--strict")
    run_cmd("02_preprocess_images", preprocess_cmd, logs)

    image_stats = json.loads(image_stats_json.read_text(encoding="utf-8"))
    input_images = int(image_stats.get("accepted_count", 0))
    if input_images < 3:
        raise RuntimeError("Not enough valid images after preprocessing")

    db = colmap_ws / "database.db"
    sparse = colmap_ws / "sparse"
    dense = colmap_ws / "dense"
    sparse.mkdir(parents=True, exist_ok=True)
    dense.mkdir(parents=True, exist_ok=True)

    run_cmd(
        "03_feature_extraction",
        [
            str(colmap), "feature_extractor",
            "--database_path", str(db),
            "--image_path", str(img_pre),
            "--ImageReader.single_camera", "0",
            "--ImageReader.mask_path", str(mask_dir),
            "--FeatureExtraction.use_gpu", "0",
            "--FeatureExtraction.num_threads", "1",
            "--FeatureExtraction.max_image_size", "1800",
            "--SiftExtraction.max_num_features", "4096",
        ],
        logs,
    )

    run_cmd("04_matching", [str(colmap), "exhaustive_matcher", "--database_path", str(db), "--FeatureMatching.use_gpu", "0"], logs)

    run_cmd(
        "05_mapper",
        [
            str(colmap), "mapper",
            "--database_path", str(db),
            "--image_path", str(img_pre),
            "--output_path", str(sparse),
            "--Mapper.filter_max_reproj_error", str(args.mapper_max_reproj_error),
            "--Mapper.tri_min_angle", "4",
            "--Mapper.min_num_matches", str(args.mapper_min_matches),
            "--Mapper.abs_pose_min_num_inliers", str(args.mapper_min_inliers),
        ],
        logs,
    )

    best_sparse, sparse_stats, best_log = select_best_sparse_model(colmap, sparse, logs)
    shutil.copy2(best_log, intermediate / "model_analyzer.txt")

    run_cmd("07_export_sparse_cloud", [str(colmap), "model_converter", "--input_path", str(best_sparse), "--output_path", str(intermediate / "sparse_cloud.ply"), "--output_type", "PLY"], logs)
    run_cmd("08_undistort", [str(colmap), "image_undistorter", "--image_path", str(img_pre), "--input_path", str(best_sparse), "--output_path", str(dense), "--output_type", "COLMAP"], logs)

    scene = openmvs_ws / "scene.mvs"
    scene_dense = openmvs_ws / "scene_dense.mvs"
    run_cmd("09_openmvs_interface", [str(interface_colmap), "-i", str(dense), "-o", str(scene), "--working-folder", str(openmvs_ws)], logs)
    run_cmd("10_openmvs_dense", [str(densify), str(scene), "-o", str(scene_dense), "--working-folder", str(openmvs_ws), "--resolution-level", str(args.openmvs_resolution_level), "--number-views", str(args.openmvs_number_views)], logs)
    run_cmd(
        "11_openmvs_reconstruct",
        [
            str(reconstruct),
            str(scene_dense),
            "-o", str(openmvs_ws / "scene_dense_mesh.mvs"),
            "--working-folder", str(openmvs_ws),
            "--remove-spurious", str(args.mesh_remove_spurious),
            "--smooth", str(args.mesh_smooth_iters),
            "--close-holes", str(args.mesh_close_holes),
        ],
        logs,
    )

    shutil.copy2(openmvs_ws / "scene_dense.ply", intermediate / "dense_cloud.ply")
    shutil.copy2(openmvs_ws / "scene_dense_mesh.ply", intermediate / "raw_mesh.ply")
    shutil.copy2(openmvs_ws / "scene_dense_mesh.ply", intermediate / "cleaned_mesh.ply")

    final_obj = final / "object_reconstruction.obj"
    final_mtl = final / "object_reconstruction.mtl"
    final_tex = final / "object_reconstruction_albedo.jpg"
    final_ply = final / "object_reconstruction.ply"
    final_glb = final / "object_reconstruction.glb"

    if not args.skip_openmvs_texture:
        run_cmd(
            "12_openmvs_texture",
            [
                str(texture),
                str(scene_dense),
                "--mesh-file", str(openmvs_ws / "scene_dense_mesh.ply"),
                "--working-folder", str(openmvs_ws),
                "-o", str(openmvs_ws / "scene_textured_obj.mvs"),
                "--export-type", "obj",
                "--resolution-level", str(args.texture_resolution_level),
                "--outlier-threshold", "0.08",
                "--empty-color", str(args.texture_empty_color),
            ],
            logs,
        )

        source_obj = openmvs_ws / "scene_textured_obj.obj"
        source_mtl = openmvs_ws / "scene_textured_obj.mtl"
        if not source_obj.exists() or not source_mtl.exists():
            raise RuntimeError("Textured OBJ/MTL not generated by OpenMVS")
        shutil.copy2(source_obj, final_obj)
        shutil.copy2(source_mtl, final_mtl)

        mtl_src = source_mtl.read_text(encoding="utf-8", errors="replace")
        tex_name = parse_map_kd(mtl_src)
        if not tex_name:
            raise RuntimeError("Could not find map_Kd in scene_textured_obj.mtl")
        source_tex = (openmvs_ws / tex_name).resolve()
        if not source_tex.exists():
            raise RuntimeError(f"Texture file missing: {source_tex}")
        shutil.copy2(source_tex, final_tex)

        mtl = mtl_src.replace(tex_name, "object_reconstruction_albedo.jpg")
        mtl = re.sub(r"(?m)^Tr\s+.*$", "Tr 0.000000", mtl)
        if not re.search(r"(?m)^d\s+", mtl):
            mtl += "\nd 1.000000\n"
        else:
            mtl = re.sub(r"(?m)^d\s+.*$", "d 1.000000", mtl)
        mtl = re.sub(r"(?m)^illum\s+.*$", "illum 2", mtl)
        final_mtl.write_text(mtl, encoding="utf-8")

        final_obj.write_text(final_obj.read_text(encoding="utf-8", errors="replace").replace("scene_textured_obj.mtl", "object_reconstruction.mtl"), encoding="utf-8")

        run_cmd("13_export_glb", [str(py), str(root / "scripts" / "obj_to_glb.py"), "--input", str(final_obj), "--output", str(final_glb)], logs)

        textured_ply = openmvs_ws / "scene_textured.ply"
        if textured_ply.exists():
            shutil.copy2(textured_ply, intermediate / "textured_mesh.ply")
            shutil.copy2(textured_ply, final_ply)
        else:
            run_cmd("14_obj_to_ply", [str(py), "-c", f"import trimesh; m=trimesh.load(r'{final_obj}', force='mesh'); m.export(r'{(intermediate / 'textured_mesh.ply')}'); m.export(r'{final_ply}')"], logs)
    else:
        run_cmd(
            "12_export_plain_mesh",
            [
                str(py),
                "-c",
                (
                    "import trimesh; "
                    f"m=trimesh.load(r'{openmvs_ws / 'scene_dense_mesh.ply'}', force='mesh'); "
                    f"m.export(r'{final_obj}'); "
                    f"m.export(r'{intermediate / 'textured_mesh.ply'}'); "
                    f"m.export(r'{final_ply}')"
                ),
            ],
            logs,
        )

    if args.generate_vertex_colors:
        run_cmd(
            "15_vertex_colorize",
            [
                str(py),
                str(root / "scripts" / "vertex_colorize_mesh.py"),
                "--mesh", str(openmvs_ws / "scene_dense_mesh.ply"),
                "--cloud", str(intermediate / "dense_cloud.ply"),
                "--out-dir", str(final / "vertexcolor"),
                "--body-band-trim",
                "--flip-output",
                "--geometry-smooth-iters", "3",
                "--geometry-smooth-lambda", "0.12",
                "--geometry-smooth-mu", "-0.13",
                "--color-smooth-iters", "2",
                "--color-smooth-strength", "0.22",
            ],
            logs,
        )
        vertex_dir = final / "vertexcolor"
        vertex_glb = vertex_dir / "object_reconstruction_vertexcolor.glb"
        vertex_ply = vertex_dir / "object_reconstruction_vertexcolor.ply"
        if vertex_glb.exists():
            shutil.copy2(vertex_glb, final_glb)
        if vertex_ply.exists():
            shutil.copy2(vertex_ply, final_ply)

    report = {
        "input_images": input_images,
        "registered_cameras": sparse_stats["registered_images"],
        "sparse_points": sparse_stats["points"],
        "mean_track_length": sparse_stats["mean_track_length"],
        "mean_reprojection_error_px": sparse_stats["mean_reprojection_error_px"],
        "output_formats": ["OBJ", "GLB", "PLY"],
        "texture_method": "vertex-color" if args.generate_vertex_colors else "openmvs",
        "quality_assessment": "good" if sparse_stats["registered_images"] >= max(3, int(input_images * 0.7)) else "limited",
    }
    (out / "report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")

    (out / "report.md").write_text(
        "\n".join([
            "# Photogrammetry Reconstruction Report",
            f"- Number of input images: {input_images}",
            f"- Registered cameras: {sparse_stats['registered_images']} / {input_images}",
            f"- Sparse points: {sparse_stats['points']}",
            f"- Mean track length: {sparse_stats['mean_track_length']}",
            "- Output formats: OBJ, GLB, PLY",
            "",
            "## Final Outputs",
            f"- OBJ: {final_obj}",
            f"- GLB: {final_glb}",
            f"- PLY: {final_ply}",
        ]) + "\n",
        encoding="utf-8",
    )

    preprocessed_images = sorted(p.name for p in img_pre.iterdir() if p.is_file() and p.suffix.lower() in {".jpg", ".jpeg", ".png"})
    write_viewer(out, preprocessed_images)

    print(f"Pipeline complete: {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
