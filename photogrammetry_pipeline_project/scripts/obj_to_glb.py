import argparse
import sys

import trimesh


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, help="Input mesh file, e.g. OBJ or PLY")
    parser.add_argument("--output", required=True, help="Output .glb path")
    args = parser.parse_args()

    try:
        mesh_or_scene = trimesh.load(args.input, force="scene")
        glb = mesh_or_scene.export(file_type="glb")
        with open(args.output, "wb") as f:
            f.write(glb)
        return 0
    except Exception as exc:
        print(f"GLB conversion failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())