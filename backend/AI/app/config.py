from pathlib import Path
import os


# -------------------------------
# HELPERS
# -------------------------------

def env_bool(name: str, default: bool) -> bool:
    value = os.getenv(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def env_int(name: str, default: int) -> int:
    try:
        return int(os.getenv(name, str(default)))
    except ValueError:
        return default


def env_float(name: str, default: float) -> float:
    try:
        return float(os.getenv(name, str(default)))
    except ValueError:
        return default


# -------------------------------
# PATHS
# -------------------------------

BASE_DIR = Path(__file__).resolve().parent.parent
OUTPUT_DIR = BASE_DIR / "outputs"
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

R2V_MODEL_CACHE = os.getenv("R2V_MODEL_CACHE", r"D:\Grademodels\model_cache")


# -------------------------------
# MODELS
# -------------------------------

SD_MODEL_ID = os.getenv(
    "SD_MODEL_ID",
    r"D:\Grademodels\model_cache\hub\models--runwayml--stable-diffusion-v1-5\snapshots\451f4fe16113bff5a5d2269ed5ad43b0592e9a14",
)

HUNYUAN_MODEL_ID = os.getenv(
    "HUNYUAN_MODEL_ID",
    "tencent/Hunyuan3D-2",
)


# -------------------------------
# GPU / MEMORY POLICY
# -------------------------------

LOAD_PIPELINES_TO_GPU_ON_STARTUP = env_bool("LOAD_PIPELINES_TO_GPU_ON_STARTUP", False)

SERIALIZE_GPU_JOBS = env_bool("SERIALIZE_GPU_JOBS", True)

KEEP_HUNYUAN_ON_GPU = env_bool("KEEP_HUNYUAN_ON_GPU", True)

MOVE_SD_BACK_TO_CPU_AFTER_USE = env_bool("MOVE_SD_BACK_TO_CPU_AFTER_USE", True)


# -------------------------------
# SD SETTINGS
# -------------------------------

SD_WIDTH = env_int("SD_WIDTH", 512)
SD_HEIGHT = env_int("SD_HEIGHT", 512)

SD_STEPS_FAST = env_int("SD_STEPS_FAST", 12)
SD_GUIDANCE_FAST = env_float("SD_GUIDANCE_FAST", 6.0)

SDXL_TURBO_STEPS_FAST = env_int("SDXL_TURBO_STEPS_FAST", 3)
SDXL_TURBO_GUIDANCE_FAST = env_float("SDXL_TURBO_GUIDANCE_FAST", 0.0)


# -------------------------------
# HUNYUAN QUALITY PROFILES
# -------------------------------
# fast:
#   fastest useful mode, may lose thin details
#
# balanced:
#   recommended first target for your graduation/product demo
#
# quality:
#   closer to old quality, slower
#
# legacy:
#   maximum quality safety mode, slowest

HUNYUAN_PROFILE = os.getenv("HUNYUAN_PROFILE", "balanced").strip().lower()

_HUNYUAN_PROFILES = {
    "fast": {
        "steps": 6,
        "guidance": 3.0,
        "octree": 128,
        "chunks": 120,
        "smooth": True,
        "smooth_iterations": 2,
    },
    "balanced": {
        "steps": 8,
        "guidance": 3.2,
        "octree": 160,
        "chunks": 160,
        "smooth": True,
        "smooth_iterations": 2,
    },
    "quality": {
        "steps": 20,
        "guidance": 3.8,
        "octree": 256,
        "chunks": 240,
        "smooth": True,
        "smooth_iterations": 1,
    },
    "legacy": {
        "steps": 22,
        "guidance": 3.85,
        "octree": 256,
        "chunks": 260,
        "smooth": True,
        "smooth_iterations": 1,
    },
}

_selected_profile = _HUNYUAN_PROFILES.get(HUNYUAN_PROFILE, _HUNYUAN_PROFILES["balanced"])

HY_STEPS = env_int("HY_STEPS", _selected_profile["steps"])
HY_GUIDANCE = env_float("HY_GUIDANCE", _selected_profile["guidance"])
HY_OCTREE_RES = env_int("HY_OCTREE_RES", _selected_profile["octree"])
HY_NUM_CHUNKS = env_int("HY_NUM_CHUNKS", _selected_profile["chunks"])
HY_ENABLE_PBAR = env_bool("HY_ENABLE_PBAR", False)

ENABLE_MESH_SMOOTHING = env_bool("ENABLE_MESH_SMOOTHING", _selected_profile["smooth"])
MESH_SMOOTH_ITERATIONS = env_int(
    "MESH_SMOOTH_ITERATIONS",
    _selected_profile["smooth_iterations"],
)


# -------------------------------
# BACKGROUND REMOVAL
# -------------------------------

ENABLE_BG_REMOVE = env_bool("ENABLE_BG_REMOVE", True)
BG_REMOVE_MODEL = os.getenv("BG_REMOVE_MODEL", "u2netp")
BG_ALPHA_MATTING = env_bool("BG_ALPHA_MATTING", False)
BG_FAST_WHITE_BACKGROUND = env_bool("BG_FAST_WHITE_BACKGROUND", True)


# -------------------------------
# WHISPER
# -------------------------------

WHISPER_MODEL_SIZE = os.getenv("WHISPER_MODEL_SIZE", "medium")
WHISPER_DEVICE = os.getenv("WHISPER_DEVICE", "cpu")
WHISPER_COMPUTE_TYPE = os.getenv("WHISPER_COMPUTE_TYPE", "int8")


# -------------------------------
# BACKEND
# -------------------------------

BACKEND_BASE_URL = os.getenv("BACKEND_BASE_URL", "http://127.0.0.1:8000")


# -------------------------------
# FEATURE FLAGS
# -------------------------------

ENABLE_SD = env_bool("ENABLE_SD", True)