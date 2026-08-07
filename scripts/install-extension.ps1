<#
.SYNOPSIS
    Install the game extension into X4's extensions folder.

.DESCRIPTION
    The repository is the source of truth; the game folder is a build output.
    After changing anything under extension\, run this and then load a savegame
    in game -- that recreates the Lua environment and picks up the new code
    without restarting X4.

.PARAMETER GameDir
    X4 folder. Defaults to $env:X4_DIR, then autodetection.
#>
[CmdletBinding()]
param([string]$GameDir = $env:X4_DIR)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here

if (-not $GameDir) {
    $GameDir = & python -c @"
import sys
sys.path.insert(0, r'$root\server')
from gamefiles import find_game_dir
print(find_game_dir())
"@
    if ($LASTEXITCODE -ne 0) {
        throw "Could not locate X4. Set X4_DIR to the folder containing 01.cat."
    }
}

$dest = Join-Path $GameDir 'extensions\x4mcp'
New-Item -ItemType Directory -Force -Path (Join-Path $dest 'ui') | Out-Null

Copy-Item (Join-Path $root 'extension\x4mcp\content.xml') $dest -Force
Copy-Item (Join-Path $root 'extension\x4mcp\ui.xml')      $dest -Force
Copy-Item (Join-Path $root 'extension\x4mcp\ui\*.lua')    (Join-Path $dest 'ui') -Force

$dll = Join-Path $root 'dist\x4mcp_64.dll'
if (Test-Path $dll) {
    Copy-Item $dll $dest -Force
} else {
    Write-Warning "dist\x4mcp_64.dll is missing -- run native\build.ps1"
}

Write-Host "installed into: $dest"
Write-Host ""
Write-Host "Next: make sure Protected UI Mode is off (see README), then start X4."
