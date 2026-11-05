<#
.SYNOPSIS
    Build x4mcp_64.dll on Windows.

.DESCRIPTION
    Most people do not need this: a prebuilt dist\x4mcp_64.dll is included and
    works with any X4 install, because it imports lua51_64.dll by name rather
    than binding to one copy of it. X4 does not need to be installed to build
    it either: the import library comes from lua51_64.def.

    The committed dist\x4mcp_64.dll is built with the pinned toolchain in
    native\Dockerfile (reproduce.sh), and CI checks it against the source. A
    build here uses your own MinGW-w64 and gives a working DLL, not
    necessarily the same bytes.

    Building needs a MinGW-w64 GCC. The easiest source is MSYS2:
        winget install MSYS2.MSYS2
        C:\msys64\usr\bin\pacman -S mingw-w64-x86_64-gcc
    then re-run this script; it finds the compiler automatically.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here

function Find-Tool([string[]]$names, [string[]]$paths) {
    foreach ($name in $names) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
    }
    foreach ($p in $paths) {
        if (Test-Path $p) { return $p }
    }
    return $null
}

$cc = Find-Tool @('x86_64-w64-mingw32-gcc', 'gcc') `
    @('C:\msys64\mingw64\bin\gcc.exe',
      'C:\ProgramData\chocolatey\bin\x86_64-w64-mingw32-gcc.exe')
if (-not $cc) {
    throw "No MinGW-w64 gcc found. See the notes at the top of this script, or just use the prebuilt dist\x4mcp_64.dll."
}
# dlltool ships with the same binutils as the compiler, next to it.
$dlltool = Find-Tool @('x86_64-w64-mingw32-dlltool', 'dlltool') `
    @((Join-Path (Split-Path $cc) 'dlltool.exe'))
if (-not $dlltool) { throw "dlltool not found next to $cc" }

$out = Join-Path $root 'dist\x4mcp_64.dll'
New-Item -ItemType Directory -Force -Path (Split-Path $out) | Out-Null
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("x4mcp-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $tmp | Out-Null

try {
    # dlltool names symbols after the -l path: run it inside $tmp with a bare
    # file name, so the temp directory does not end up in the DLL.
    $lib = Join-Path $tmp 'liblua51_64.a'
    Push-Location $tmp
    try {
        & $dlltool -d (Join-Path $here 'lua51_64.def') -D lua51_64.dll -l liblua51_64.a
        if ($LASTEXITCODE -ne 0) { throw "dlltool failed" }
    } finally {
        Pop-Location
    }

    Push-Location $here
    try {
        & $cc -shared -O2 -Wall -Wextra `
            -o $out `
            x4mcp.c `
            $lib `
            -lws2_32 -static-libgcc -Wl,--enable-stdcall-fixup `
            -Wl,--no-insert-timestamp
        if ($LASTEXITCODE -ne 0) { throw "compilation failed" }
    } finally {
        Pop-Location
    }
} finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

Write-Host "built: $out"
