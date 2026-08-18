@echo off
echo Use PowerShell and provide your SSH host alias:
echo powershell -ExecutionPolicy Bypass -File "%~dp0start-reverse-tunnel-monitor.ps1" -SshHost "your-ssh-host-alias" -Mode Official
echo powershell -ExecutionPolicy Bypass -File "%~dp0start-reverse-tunnel-monitor.ps1" -SshHost "your-ssh-host-alias" -Mode Relay
