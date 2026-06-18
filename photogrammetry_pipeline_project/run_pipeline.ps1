param(
    [Parameter(Mandatory = $true)]
    [string]$ZipPath,

    [string]$RunName = "run_photos",
    [string]$TextureMode = "vertexcolor",
    [string]$PythonExe = "python",
    [string]$ToolsRoot = "",
    [switch]$NoStrictMask
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$scriptPath = Join-Path $projectRoot "scripts\run_photogrammetry.py"

$args = @(
    $scriptPath,
    "--zip", (Resolve-Path $ZipPath).Path,
    "--run-name", $RunName,
    "--root", $projectRoot,
    "--openmvs-resolution-level", "2",
    "--openmvs-number-views", "3",
    "--mapper-max-reproj-error", "1.6",
    "--mapper-min-matches", "20",
    "--mapper-min-inliers", "20",
    "--mesh-remove-spurious", "55",
    "--mesh-smooth-iters", "3",
    "--mesh-close-holes", "10"
)

if ($ToolsRoot -ne "") {
    $args += @("--tools-root", (Resolve-Path $ToolsRoot).Path)
}

if ($NoStrictMask) {
    $args += "--no-strict-mask"
}

switch ($TextureMode.ToLowerInvariant()) {
    "vertexcolor" {
        $args += "--skip-openmvs-texture"
        $args += "--generate-vertex-colors"
    }
    "openmvs" {
    }
    default {
        throw "Unsupported -TextureMode '$TextureMode'. Use 'openmvs' or 'vertexcolor'."
    }
}

& $PythonExe @args
