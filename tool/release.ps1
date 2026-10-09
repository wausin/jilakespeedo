# Builds the PWA for release with APP_VERSION taken from pubspec.yaml's
# `version:` field, so the running build and the generated version.json
# always agree. Bump `version: X.Y.Z+N` in pubspec.yaml before each release.
#
# Usage:  tool\release.ps1
# Output: build\web\  (deploy that folder to your HTTPS host)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$pubspec = Get-Content (Join-Path $repoRoot 'pubspec.yaml')
$line = $pubspec | Where-Object { $_ -match '^version:\s*(\S+)' } | Select-Object -First 1
if (-not $line) { throw 'no version: line found in pubspec.yaml' }
$version = $Matches[1]

Write-Output "Building release with APP_VERSION=$version ..."
Push-Location $repoRoot
try {
  # Flutter prints informational messages to stderr; that is not a failure.
  $ErrorActionPreference = 'Continue'
  flutter build web --release "--dart-define=APP_VERSION=$version"
  if ($LASTEXITCODE -ne 0) { throw "flutter build web failed (exit $LASTEXITCODE)" }
} finally {
  $ErrorActionPreference = 'Stop'
  Pop-Location
}
Write-Output "Done. Deploy build\web to your host."
