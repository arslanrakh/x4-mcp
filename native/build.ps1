<#
.SYNOPSIS
    Build x4mcp_64.dll on Windows.

.DESCRIPTION
    Most people do not need this: a prebuilt dist\x4mcp_64.dll is included and
    works with any X4 install, because it imports lua51_64.dll by name rather
    than binding to one copy of it.

    Building needs a MinGW-w64 GCC. The easiest source is MSYS2:
        winget install MSYS2.MSYS2
        C:\msys64\usr\bin\pacman -S mingw-w64-x86_64-gcc
    then re-run this script; it finds the compiler automatically.

.PARAMETER GameDir
    X4 folder. Defaults to $env:X4_DIR, then autodetection.
#>
[CmdletBinding()]
param([string]$GameDir = $env:X4_DIR)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here

function Find-Gcc {
    foreach ($name in @('x86_64-w64-mingw32-gcc', 'gcc')) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
    }
    foreach ($p in @('C:\msys64\mingw64\bin\gcc.exe',
                     'C:\ProgramData\chocolatey\bin\x86_64-w64-mingw32-gcc.exe')) {
        if (Test-Path $p) { return $p }
    }
    throw "No MinGW-w64 gcc found. See the notes at the top of this script, or just use the prebuilt dist\x4mcp_64.dll."
}

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

$luaDll = Join-Path $GameDir 'lua51_64.dll'
if (-not (Test-Path $luaDll)) { throw "not found: $luaDll" }

$cc  = Find-Gcc
$out = Join-Path $root 'dist\x4mcp_64.dll'
New-Item -ItemType Directory -Force -Path (Split-Path $out) | Out-Null

& $cc -shared -O2 -Wall -Wextra `
    -o $out `
    (Join-Path $here 'x4mcp.c') `
    $luaDll `
    -lws2_32 -static-libgcc -Wl,--enable-stdcall-fixup
if ($LASTEXITCODE -ne 0) { throw "compilation failed" }

Write-Host "built: $out"
Write-Host "game:  $GameDir"
