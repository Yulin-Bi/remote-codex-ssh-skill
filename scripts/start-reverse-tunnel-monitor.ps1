[CmdletBinding()]
param(
    [string]$MonitorScript,
    [Parameter(Mandatory = $true)]
    [string]$SshHost,
    [ValidateSet('Official', 'Relay', 'Both')]
    [string]$Mode = 'Official',
    [int]$LocalRelayPort = 55446
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($MonitorScript)) {
    $MonitorScript = Join-Path $PSScriptRoot 'monitor-reverse-tunnels.ps1'
}

if (-not (Test-Path -LiteralPath $MonitorScript -PathType Leaf)) {
    throw "Monitor script not found: $MonitorScript"
}

$existing = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -and $_.CommandLine.Contains('monitor-reverse-tunnels.ps1') }

if ($existing) {
    $existing | ForEach-Object { "Monitor already running (pid=$($_.ProcessId)); stop it before changing mode" }
    exit 0
}

$windir = if ([string]::IsNullOrWhiteSpace($env:WINDIR)) { 'C:\WINDOWS' } else { $env:WINDIR }
$ssh = Join-Path $windir 'System32\OpenSSH\ssh.exe'
$probe = & $ssh -n -o BatchMode=yes -o ConnectTimeout=5 -o LogLevel=ERROR $SshHost 'true' 2>$null
if ($LASTEXITCODE -ne 0) {
    $detail = ($probe | Select-Object -First 1)
    Write-Error "Remote server is not available; monitor was not started. $detail"
    exit 2
}

$powershell = Join-Path $windir 'System32\WindowsPowerShell\v1.0\powershell.exe'
$process = Start-Process -FilePath $powershell -ArgumentList @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
    '-File', $MonitorScript, '-SshHost', $SshHost, '-Mode', $Mode,
    '-LocalRelayPort', $LocalRelayPort
) -WindowStyle Hidden -PassThru

"Started reverse-tunnel monitor mode=$Mode (pid=$($process.Id))"
