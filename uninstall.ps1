$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

$InstallDir = if ([string]::IsNullOrWhiteSpace($env:ProgramFiles)) { $null } else { Join-Path $env:ProgramFiles "NetBird" }
$ProgramFilesX86 = [Environment]::GetEnvironmentVariable("ProgramFiles(x86)")
$LegacyInstallDir = if ([string]::IsNullOrWhiteSpace($ProgramFilesX86)) { $null } else { Join-Path $ProgramFilesX86 "NetBird" }

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message"
}

function Write-Ok {
    param([string]$Message)
    Write-Host "[OK]   $Message"
}

function Write-Warn {
    param([string]$Message)
    Write-Host "[WARN] $Message"
}

function Assert-Windows {
    if ($env:OS -ne "Windows_NT") {
        throw "This uninstaller supports Windows only."
    }
}

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Run this script from an elevated PowerShell session."
    }
}

function Stop-NetBirdProcesses {
    Write-Info "Stopping NetBird processes if they are running."
    Get-Process -Name "netbird", "netbird-ui" -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            Stop-Process -Id $_.Id -Force -ErrorAction Stop
            Write-Ok "Stopped process $($_.ProcessName) ($($_.Id))."
        } catch {
            Write-Warn "Could not stop process $($_.ProcessName) ($($_.Id)): $($_.Exception.Message)"
        }
    }
}

function Invoke-NetBirdServiceUninstall {
    $candidates = @(
        $(if ($null -ne $InstallDir) { Join-Path $InstallDir "netbird.exe" }),
        $(if ($null -ne $LegacyInstallDir) { Join-Path $LegacyInstallDir "netbird.exe" })
    )

    $command = Get-Command "netbird.exe" -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        $candidates += $command.Source
    }

    $binary = $candidates | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path $_) } | Select-Object -First 1
    if ($null -ne $binary) {
        Write-Info "Stopping and uninstalling NetBird service with $binary."
        & $binary service stop | Out-Null
        & $binary service uninstall | Out-Null
        return
    }

    $service = Get-Service -Name "netbird" -ErrorAction SilentlyContinue
    if ($null -ne $service) {
        Write-Info "Removing NetBird service registration."
        if ($service.Status -ne "Stopped") {
            Stop-Service -Name "netbird" -Force -ErrorAction SilentlyContinue
        }
        sc.exe delete netbird | Out-Null
    }
}

function Get-NetBirdUninstallEntries {
    $roots = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    foreach ($root in $roots) {
        Get-ItemProperty -Path $root -ErrorAction SilentlyContinue |
            Where-Object {
                $_.DisplayName -match "^NetBird" -or
                $_.Publisher -match "NetBird" -or
                $_.DisplayIcon -match "NetBird"
            }
    }
}

function Invoke-MsiUninstall {
    $entries = @(Get-NetBirdUninstallEntries)
    if ($entries.Count -eq 0) {
        Write-Warn "No NetBird MSI uninstall entry found."
        return
    }

    foreach ($entry in $entries) {
        $productCode = $null
        if ($entry.PSChildName -match "^\{[0-9A-Fa-f-]+\}$") {
            $productCode = $entry.PSChildName
        } elseif ($entry.UninstallString -match "\{[0-9A-Fa-f-]+\}") {
            $productCode = $Matches[0]
        }

        if ($null -eq $productCode) {
            Write-Warn "Could not determine MSI product code for $($entry.DisplayName)."
            continue
        }

        Write-Info "Uninstalling $($entry.DisplayName) with msiexec."
        $process = Start-Process -FilePath "msiexec.exe" -ArgumentList "/x $productCode /quiet /norestart" -Wait -PassThru
        if ($process.ExitCode -notin @(0, 1605, 3010)) {
            throw "MSI uninstall failed with exit code $($process.ExitCode)."
        }
        Write-Ok "Removed $($entry.DisplayName)."
    }
}

function Remove-MachinePath {
    param([Parameter(Mandatory = $true)][string]$PathToRemove)

    $current = [Environment]::GetEnvironmentVariable("Path", "Machine")
    if ([string]::IsNullOrWhiteSpace($current)) {
        return
    }

    $normalizedTarget = $PathToRemove.TrimEnd("\")
    $parts = @($current -split ";" | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_) -and
        $_.TrimEnd("\") -ne $normalizedTarget
    })

    [Environment]::SetEnvironmentVariable("Path", ($parts -join ";"), "Machine")
    Write-Ok "Removed $PathToRemove from the machine PATH if present."
}

function Remove-NetBirdFiles {
    Write-Info "Removing NetBird files and data."

    $paths = @(
        $InstallDir,
        $LegacyInstallDir,
        $(if (-not [string]::IsNullOrWhiteSpace($env:ProgramData)) { Join-Path $env:ProgramData "NetBird" }),
        $(if (-not [string]::IsNullOrWhiteSpace($env:ProgramData)) { Join-Path $env:ProgramData "netbird" }),
        $(if (-not [string]::IsNullOrWhiteSpace($env:LocalAppData)) { Join-Path $env:LocalAppData "NetBird" }),
        $(if (-not [string]::IsNullOrWhiteSpace($env:AppData)) { Join-Path $env:AppData "NetBird" }),
        $(if (-not [string]::IsNullOrWhiteSpace($env:AppData)) { Join-Path $env:AppData "netbird" })
    )

    foreach ($path in $paths) {
        if (-not [string]::IsNullOrWhiteSpace($path) -and (Test-Path $path)) {
            Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
            Write-Ok "Removed $path."
        }
    }
}

function Remove-NetBirdScheduledTasks {
    $tasks = Get-ScheduledTask -ErrorAction SilentlyContinue |
        Where-Object { $_.TaskName -match "NetBird" -or $_.TaskPath -match "NetBird" }

    foreach ($task in $tasks) {
        Write-Info "Removing scheduled task $($task.TaskPath)$($task.TaskName)."
        Unregister-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -Confirm:$false -ErrorAction SilentlyContinue
    }
}

function Uninstall-NetBirdWindows {
    Assert-Windows
    Assert-Administrator

    Stop-NetBirdProcesses
    Invoke-NetBirdServiceUninstall
    Invoke-MsiUninstall
    Remove-NetBirdScheduledTasks
    Remove-NetBirdFiles
    if ($null -ne $InstallDir) {
        Remove-MachinePath -PathToRemove $InstallDir
    }
    if ($null -ne $LegacyInstallDir) {
        Remove-MachinePath -PathToRemove $LegacyInstallDir
    }

    Write-Ok "Windows cleanup complete. NetBird has been removed."
}

Uninstall-NetBirdWindows
