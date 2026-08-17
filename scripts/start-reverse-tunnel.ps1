[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SshHost,
    [ValidateRange(1, 65535)]
    [int]$LocalProxyPort = 7897,
    [ValidateRange(1, 65535)]
    [int]$RemoteProxyPort = 17897,
    [string]$SshExe = "$env:WINDIR\System32\OpenSSH\ssh.exe"
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $SshExe -PathType Leaf)) {
    throw "OpenSSH client not found: $SshExe"
}

$proxyProbe = Test-NetConnection -ComputerName 127.0.0.1 -Port $LocalProxyPort -WarningAction SilentlyContinue
if (-not $proxyProbe.TcpTestSucceeded) {
    throw "No local proxy is listening on 127.0.0.1:$LocalProxyPort"
}

$forward = "${RemoteProxyPort}:127.0.0.1:${LocalProxyPort}"
$sshArgs = @(
    '-N', '-T',
    '-o', 'ExitOnForwardFailure=yes',
    '-o', 'ServerAliveInterval=20',
    '-o', 'ServerAliveCountMax=3',
    '-o', 'TCPKeepAlive=yes',
    '-R', $forward,
    $SshHost
)

$process = Start-Process -FilePath $SshExe -ArgumentList $sshArgs -WindowStyle Hidden -PassThru
Start-Sleep -Seconds 2

if ($process.HasExited) {
    throw "SSH tunnel exited immediately with code $($process.ExitCode). Check the SSH host and remote port."
}

[pscustomobject]@{
    ProcessId = $process.Id
    SshHost = $SshHost
    LocalProxy = "127.0.0.1:$LocalProxyPort"
    RemoteProxy = "127.0.0.1:$RemoteProxyPort"
}

