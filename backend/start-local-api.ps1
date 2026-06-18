param(
    [switch]$SkipSupportServices,
    [switch]$StopExistingApi,
    [int]$Port = 18001
)

$ErrorActionPreference = "Stop"

$backendRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $backendRoot
$pipelineRoot = Join-Path $repoRoot "photogrammetry_pipeline_project"
$toolsRoot = Join-Path $pipelineRoot "tools"
$colmapExe = Join-Path $toolsRoot "colmap\\bin\\colmap.exe"
$openMvsReleaseDir = Join-Path $toolsRoot "openmvs\\vc17\\x64\\Release"
$requiredOpenMvs = @(
    "InterfaceCOLMAP.exe",
    "DensifyPointCloud.exe",
    "ReconstructMesh.exe",
    "TextureMesh.exe"
)

function Assert-PathExists {
    param(
        [string]$Path,
        [string]$Message
    )
    if (-not (Test-Path $Path)) {
        throw $Message
    }
}

function Test-PortOpen {
    param(
        [string]$HostName,
        [int]$PortNumber
    )

    try {
        $client = [System.Net.Sockets.TcpClient]::new()
        $connect = $client.BeginConnect($HostName, $PortNumber, $null, $null)
        $ok = $connect.AsyncWaitHandle.WaitOne(2000, $false)
        if ($ok) {
            $client.EndConnect($connect)
        }
        $client.Close()
        return $ok
    }
    catch {
        return $false
    }
}

function Wait-PortOpen {
    param(
        [string]$HostName,
        [int]$PortNumber,
        [string]$ServiceName,
        [int]$TimeoutSeconds = 60
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (Test-PortOpen -HostName $HostName -PortNumber $PortNumber) {
            Write-Host "$ServiceName is reachable on ${HostName}:${PortNumber}"
            return
        }
        Start-Sleep -Seconds 2
    }

    throw "$ServiceName did not become reachable on ${HostName}:${PortNumber}. Start Docker Desktop and run: docker compose up -d db redis minio minio-init"
}

if ($StopExistingApi) {
    Get-CimInstance Win32_Process -Filter "name = 'python.exe'" |
        Where-Object { $_.CommandLine -match "uvicorn app\.main:app" -or $_.CommandLine -match "multiprocessing\.spawn" } |
        ForEach-Object {
            Write-Host "Stopping existing backend Python process $($_.ProcessId)"
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        }
}

Assert-PathExists `
    -Path $pipelineRoot `
    -Message "Photogrammetry pipeline folder was not found at '$pipelineRoot'."
Assert-PathExists `
    -Path $colmapExe `
    -Message "COLMAP executable was not found at '$colmapExe'."
Assert-PathExists `
    -Path $openMvsReleaseDir `
    -Message "OpenMVS Release folder was not found at '$openMvsReleaseDir'."

foreach ($exe in $requiredOpenMvs) {
    $fullPath = Join-Path $openMvsReleaseDir $exe
    Assert-PathExists `
        -Path $fullPath `
        -Message "Required OpenMVS executable was not found at '$fullPath'."
}

if (-not $SkipSupportServices) {
    Write-Host "Starting local support services (Postgres, Redis, MinIO) via Docker..."
    Push-Location $backendRoot
    try {
        docker compose up -d db redis minio minio-init
    }
    finally {
        Pop-Location
    }
}

Wait-PortOpen -HostName "127.0.0.1" -PortNumber 5432 -ServiceName "Postgres"
Wait-PortOpen -HostName "127.0.0.1" -PortNumber 6379 -ServiceName "Redis"

$env:DATABASE_URL = "postgresql+psycopg://r2v:r2v@127.0.0.1:5432/r2v?connect_timeout=5"
$env:REDIS_URL = "redis://127.0.0.1:6379/0"
$env:S3_ENDPOINT_URL = "http://127.0.0.1:9000"
$env:S3_PUBLIC_ENDPOINT_URL = "http://127.0.0.1:9000"
$env:S3_ACCESS_KEY = "minioadmin"
$env:S3_SECRET_KEY = "minioadmin"
$env:ALLOWED_ORIGINS = "http://localhost:55509"
$env:PHOTOGRAMMETRY_PIPELINE_ROOT = $pipelineRoot
$env:PHOTOGRAMMETRY_JOBS_ROOT = (Join-Path $backendRoot "jobs")
$env:PHOTOGRAMMETRY_TOOLS_ROOT = $toolsRoot
$env:PHOTOGRAMMETRY_PYTHON_EXE = "python"

Write-Host "Launching FastAPI locally on http://127.0.0.1:$Port"
Push-Location $backendRoot
try {
    python -m alembic upgrade head
    python -m uvicorn app.main:app --host 127.0.0.1 --port $Port --reload
}
finally {
    Pop-Location
}
