param(
    [switch]$Force,
    [switch]$UseCudaColmap
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$toolsRoot = Join-Path $root "tools"
$downloadsRoot = Join-Path $toolsRoot "_downloads"
$workRoot = Join-Path $toolsRoot "_extract"
$colmapBin = Join-Path $toolsRoot "colmap\bin"
$openMvsRelease = Join-Path $toolsRoot "openmvs\vc17\x64\Release"

function Get-LatestReleaseAsset {
    param(
        [string]$Repo,
        [string]$AssetPattern
    )

    $release = Invoke-RestMethod "https://api.github.com/repos/$Repo/releases/latest"
    $asset = $release.assets | Where-Object { $_.name -like $AssetPattern } | Select-Object -First 1
    if (-not $asset) {
        throw "Could not find asset '$AssetPattern' in latest release for $Repo."
    }
    return [pscustomobject]@{
        Tag = $release.tag_name
        Name = $asset.name
        Url = $asset.browser_download_url
    }
}

function Download-Asset {
    param(
        [pscustomobject]$Asset
    )

    New-Item -ItemType Directory -Force -Path $downloadsRoot | Out-Null
    $target = Join-Path $downloadsRoot $Asset.Name
    if ((Test-Path $target) -and -not $Force) {
        Write-Host "Using cached $($Asset.Name)"
        return $target
    }

    Write-Host "Downloading $($Asset.Name) from $($Asset.Tag)..."
    Invoke-WebRequest -Uri $Asset.Url -OutFile $target
    return $target
}

function Expand-ZipClean {
    param(
        [string]$ArchivePath,
        [string]$Destination
    )

    if (Test-Path $Destination) {
        Remove-Item -Recurse -Force $Destination
    }
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    Expand-Archive -LiteralPath $ArchivePath -DestinationPath $Destination -Force
}

function Copy-ExecutableFolder {
    param(
        [string]$SearchRoot,
        [string]$ExecutableName,
        [string]$Destination
    )

    $exe = Get-ChildItem -Path $SearchRoot -Recurse -Filter $ExecutableName | Select-Object -First 1
    if (-not $exe) {
        throw "Could not find $ExecutableName under $SearchRoot."
    }

    if (Test-Path $Destination) {
        Remove-Item -Recurse -Force $Destination
    }
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null

    Write-Host "Copying runtime files from $($exe.Directory.FullName)"
    Copy-Item -Path (Join-Path $exe.Directory.FullName "*") -Destination $Destination -Recurse -Force
}

$colmapPattern = if ($UseCudaColmap) { "colmap-x64-windows-cuda.zip" } else { "colmap-x64-windows-nocuda.zip" }
$colmapAsset = Get-LatestReleaseAsset -Repo "colmap/colmap" -AssetPattern $colmapPattern
$openMvsAsset = Get-LatestReleaseAsset -Repo "cdcseacave/openMVS" -AssetPattern "OpenMVS_Windows_x64.zip"

$colmapArchive = Download-Asset -Asset $colmapAsset
$openMvsArchive = Download-Asset -Asset $openMvsAsset

$colmapExtract = Join-Path $workRoot "colmap"
$openMvsExtract = Join-Path $workRoot "openmvs"
Expand-ZipClean -ArchivePath $colmapArchive -Destination $colmapExtract
Expand-ZipClean -ArchivePath $openMvsArchive -Destination $openMvsExtract

Copy-ExecutableFolder -SearchRoot $colmapExtract -ExecutableName "colmap.exe" -Destination $colmapBin
Copy-ExecutableFolder -SearchRoot $openMvsExtract -ExecutableName "InterfaceCOLMAP.exe" -Destination $openMvsRelease

$required = @(
    (Join-Path $colmapBin "colmap.exe"),
    (Join-Path $openMvsRelease "InterfaceCOLMAP.exe"),
    (Join-Path $openMvsRelease "DensifyPointCloud.exe"),
    (Join-Path $openMvsRelease "ReconstructMesh.exe"),
    (Join-Path $openMvsRelease "TextureMesh.exe")
)

foreach ($path in $required) {
    if (-not (Test-Path $path)) {
        throw "Tool install incomplete. Missing: $path"
    }
}

Write-Host "Photogrammetry tools installed successfully under $toolsRoot"
