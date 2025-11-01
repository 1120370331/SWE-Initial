param(
    [switch]$Silent
)

$git = Get-Command git -ErrorAction SilentlyContinue
if (-not $git) {
    Write-Error "install-hooks: git executable not found in PATH"
    exit 1
}

$repoRoot = git rev-parse --show-toplevel 2>$null
if (-not $?) {
    Write-Error "install-hooks: unable to locate git repository"
    exit 1
}

$hooksPath = Join-Path $repoRoot '.githooks'

git config core.hooksPath $hooksPath | Out-Null

if (-not $Silent) {
    Write-Host "install-hooks: git hooks path set to .githooks" -ForegroundColor Green
    Write-Host "install-hooks: future hooks placed in .githooks/ will activate automatically"
}
