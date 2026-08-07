<#
.SYNOPSIS
    Run the MCP server directly, without Docker.

.DESCRIPTION
    Creates a virtualenv on first use. Configuration comes from .env if present;
    see .env.example. Docker is the other option (docker compose up -d) and
    needs no Python on the host, but has to be told where the game lives.
#>
[CmdletBinding()]
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
$venv = Join-Path $root '.venv'
$python = Join-Path $venv 'Scripts\python.exe'

# A .env here is a convenience for the direct run; docker compose reads it too.
$envFile = Join-Path $root '.env'
if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        if ($_ -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)\s*$') {
            $value = $Matches[2].Trim('"').Trim("'")
            [Environment]::SetEnvironmentVariable($Matches[1], $value, 'Process')
        }
    }
}

if (-not (Test-Path $python)) {
    Write-Host "creating virtualenv in $venv"
    & python -m venv $venv
    & $python -m pip install --quiet --upgrade pip
    & $python -m pip install --quiet -r (Join-Path $root 'server\requirements.txt')
}

& $python (Join-Path $root 'server\x4mcp_server.py') @Args
