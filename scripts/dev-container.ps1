$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
Push-Location $Root
try {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw 'Docker is not installed or is not available in PATH.'
    }
    & docker compose version
    if ($LASTEXITCODE -ne 0) {
        throw 'Docker Compose plugin is unavailable.'
    }

    & docker compose -f compose.dev.yaml run --build --rm flutter-dev
    if ($LASTEXITCODE -ne 0) {
        throw "Docker development container exited with code $LASTEXITCODE."
    }
}
finally {
    Pop-Location
}
