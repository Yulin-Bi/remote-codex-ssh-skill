[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SshHost,
    [ValidateSet('Official', 'Relay', 'Both')]
    [string]$Mode = 'Official',
    [int]$LocalProxyPort = 7897,
    [int]$RemoteProxyPort = 17897,
    [string]$LocalRelayPort = 'auto',
    [int]$RemoteRelayPort = 15446,
    [int]$IntervalSeconds = 20,
    [int]$MaxRemoteFailures = 3
)

$ErrorActionPreference = 'Continue'
$windir = if ([string]::IsNullOrWhiteSpace($env:WINDIR)) { 'C:\WINDOWS' } else { $env:WINDIR }
$ssh = Join-Path $windir 'System32\OpenSSH\ssh.exe'
$stateDir = Join-Path $env:LOCALAPPDATA 'Codex\reverse-tunnels'
$log = Join-Path $stateDir 'monitor.log'

New-Item -ItemType Directory -Path $stateDir -Force | Out-Null

function Write-Log([string]$Message) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Message"
    Add-Content -LiteralPath $log -Value $line -Encoding UTF8
}

function Test-LocalListener([int]$Port) {
    try {
        return [bool](Get-NetTCPConnection -LocalAddress '127.0.0.1' -LocalPort $Port -State Listen -ErrorAction Stop)
    } catch {
        return $false
    }
}

function Test-TunnelProcess([int]$RemotePort, [int]$LocalPort) {
    $needle = "-R $RemotePort`:127.0.0.1`:$LocalPort"
    try {
        return [bool](Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" -ErrorAction Stop |
            Where-Object { $_.CommandLine -and $_.CommandLine.Contains($needle) })
    } catch {
        Write-Log "Could not inspect ssh.exe processes: $($_.Exception.Message)"
        return $false
    }
}

function Resolve-RelayPort {
    if ($LocalRelayPort -ne 'auto') {
        $port = 0
        if ([int]::TryParse($LocalRelayPort, [ref]$port) -and $port -ge 1 -and $port -le 65535) {
            return $port
        }
        Write-Log "Invalid LocalRelayPort '$LocalRelayPort'; expected auto or a TCP port"
        return $null
    }

    try {
        $relayPids = @(Get-CimInstance Win32_Process -ErrorAction Stop |
            Where-Object { $_.Name -match '^cockpit-cliproxy(\.exe)?$' } |
            Select-Object -ExpandProperty ProcessId)
        if ($relayPids.Count -eq 0) {
            return $null
        }
        $ports = @(Get-NetTCPConnection -State Listen -ErrorAction Stop |
            Where-Object { $relayPids -contains $_.OwningProcess } |
            Select-Object -ExpandProperty LocalPort -Unique)
        if ($ports.Count -eq 1) {
            return [int]$ports[0]
        }
        if ($ports.Count -gt 1) {
            Write-Log "Multiple cockpit-cliproxy listeners found ($($ports -join ', ')); pass -LocalRelayPort explicitly"
        }
    } catch {
        Write-Log "Could not auto-detect cockpit-cliproxy port: $($_.Exception.Message)"
    }
    return $null
}

function Stop-StaleRelayTunnels([int]$CurrentLocalPort) {
    $prefix = "-R ${RemoteRelayPort}:127.0.0.1:"
    try {
        Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" -ErrorAction Stop |
            Where-Object {
                $_.CommandLine -and
                $_.CommandLine.Contains($prefix) -and
                (-not $_.CommandLine.Contains($prefix + $CurrentLocalPort))
            } |
            ForEach-Object {
                Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
                Write-Log "Stopped stale relay tunnel pid=$($_.ProcessId) local=$CurrentLocalPort"
            }
    } catch {
        Write-Log "Could not inspect stale relay tunnels: $($_.Exception.Message)"
    }
}

function Test-RemoteServer {
    try {
        $probe = & $ssh -n -o BatchMode=yes -o ConnectTimeout=5 -o LogLevel=ERROR $SshHost 'true' 2>$null
        if ($LASTEXITCODE -eq 0) {
            return $true
        }
        $detail = ($probe | Select-Object -First 1)
        Write-Log "Remote server probe failed: $detail"
        return $false
    } catch {
        Write-Log "Remote server probe failed: $($_.Exception.Message)"
        return $false
    }
}

function Start-Tunnel([int]$RemotePort, [int]$LocalPort) {
    if (-not (Test-LocalListener $LocalPort)) {
        Write-Log "Local service 127.0.0.1:$LocalPort is unavailable; waiting"
        return
    }
    if (Test-TunnelProcess $RemotePort $LocalPort) {
        return
    }

    $args = @(
        '-N', '-T', '-o', 'BatchMode=yes', '-o', 'LogLevel=ERROR',
        '-o', 'ExitOnForwardFailure=yes',
        '-o', 'ServerAliveInterval=20',
        '-o', 'ServerAliveCountMax=3',
        '-o', 'TCPKeepAlive=yes',
        '-R', "${RemotePort}:127.0.0.1:${LocalPort}",
        $SshHost
    )

    try {
        $process = Start-Process -FilePath $ssh -ArgumentList $args -WindowStyle Hidden -PassThru
        Write-Log "Started tunnel remote=$RemotePort local=$LocalPort pid=$($process.Id)"
    } catch {
        Write-Log "Failed to start tunnel remote=$RemotePort local=${LocalPort}: $($_.Exception.Message)"
    }
}

if (-not (Test-Path -LiteralPath $ssh -PathType Leaf)) {
    Write-Log "OpenSSH not found at $ssh"
    exit 1
}

Write-Log "Monitor started for $SshHost mode=$Mode"
$monitorOfficial = $Mode -in @('Official', 'Both')
$monitorRelay = $Mode -in @('Relay', 'Both')
$remoteFailures = 0
while ($true) {
    $relayPort = if ($monitorRelay) { Resolve-RelayPort } else { $null }
    if ($monitorRelay -and $null -eq $relayPort) {
        Write-Log 'Relay service port not detected; waiting'
    }
    $needsOfficial = $monitorOfficial -and (Test-LocalListener $LocalProxyPort) -and (-not (Test-TunnelProcess $RemoteProxyPort $LocalProxyPort))
    $needsRelay = $monitorRelay -and $null -ne $relayPort -and (-not (Test-TunnelProcess $RemoteRelayPort $relayPort))

    if (($needsOfficial -or $needsRelay) -and (-not (Test-RemoteServer))) {
        $remoteFailures++
        if ($remoteFailures -ge $MaxRemoteFailures) {
            Write-Log "Remote server unavailable for $remoteFailures consecutive probes; monitor exiting"
            break
        }
        Start-Sleep -Seconds $IntervalSeconds
        continue
    }

    $remoteFailures = 0
    if ($monitorOfficial) {
        Start-Tunnel $RemoteProxyPort $LocalProxyPort
    }
    if ($monitorRelay) {
        if ($null -ne $relayPort) {
            Stop-StaleRelayTunnels $relayPort
            Start-Tunnel $RemoteRelayPort $relayPort
        }
    }
    Start-Sleep -Seconds $IntervalSeconds
}
