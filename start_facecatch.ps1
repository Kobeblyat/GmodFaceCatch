$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$listener = Get-NetTCPConnection -LocalPort 8667 -State Listen -ErrorAction SilentlyContinue
if ($listener) {
    Write-Host "FaceCatch is already listening at ws://127.0.0.1:8667"
    exit 0
}

if (-not (Test-Path ".\.venv\Scripts\python.exe")) {
    throw "Missing .venv. Run: uv venv --python 3.12 .venv"
}

if (-not (Test-Path ".\face_landmarker.task")) {
    throw "Missing face_landmarker.task"
}

if (-not $env:FACETRACKER_CAMERA_INDEX) {
    $env:FACETRACKER_CAMERA_INDEX = "0"
}

& ".\.venv\Scripts\python.exe" -u ".\gmod_facetracker.py"
