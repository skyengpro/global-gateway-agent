$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

$NetBirdOwner = "netbirdio"
$NetBirdRepo = "netbird"
$InstallDir = Join-Path $env:ProgramFiles "NetBird"
$UserAgent = "global-gateway-agent-installer"

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message"
}

function Write-Ok {
    param([string]$Message)
    Write-Host "[OK]   $Message"
}

function Assert-Windows {
    if ($env:OS -ne "Windows_NT") {
        throw "This installer supports Windows only."
    }
}

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Run this script from an elevated PowerShell session."
    }
}

function Get-NetBirdArch {
    switch ($env:PROCESSOR_ARCHITECTURE) {
        "AMD64" { return "amd64" }
        "ARM64" { return "arm64" }
        default { throw "Unsupported Windows architecture: $env:PROCESSOR_ARCHITECTURE" }
    }
}

function Get-EnvBool {
    param([string]$Name)

    $item = Get-Item -Path "Env:$Name" -ErrorAction SilentlyContinue
    if ($null -eq $item -or [string]::IsNullOrWhiteSpace($item.Value)) {
        return $null
    }

    switch -Regex ($item.Value.Trim().ToLowerInvariant()) {
        "^(1|true|yes|y)$" { return $true }
        "^(0|false|no|n)$" { return $false }
        default { throw "$Name must be true or false, got '$($item.Value)'." }
    }
}

function Test-WindowsServer {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    if ($null -ne $os.ProductType) {
        return ([int]$os.ProductType -ne 1)
    }

    return ($os.Caption -match "Server")
}

function Resolve-SkipUiApp {
    $override = Get-EnvBool -Name "SKIP_UI_APP"
    if ($null -ne $override) {
        Write-Info "SKIP_UI_APP is set to $override."
        return $override
    }

    if (Test-WindowsServer) {
        Write-Info "Detected Windows Server. NetBird UI installation will be omitted."
        return $true
    }

    Write-Info "Detected Windows Desktop. NetBird UI will be installed."
    return $false
}

function Get-NetBirdRelease {
    $release = $env:NETBIRD_RELEASE
    if ([string]::IsNullOrWhiteSpace($release)) {
        $release = "latest"
    }

    if ($release -eq "latest") {
        $url = "https://api.github.com/repos/$NetBirdOwner/$NetBirdRepo/releases/latest"
    } else {
        if (-not $release.StartsWith("v")) {
            $release = "v$release"
        }
        $url = "https://api.github.com/repos/$NetBirdOwner/$NetBirdRepo/releases/tags/$release"
    }

    Write-Info "Resolving NetBird release from $url"
    return Invoke-RestMethod -Uri $url -Headers @{ "User-Agent" = $UserAgent; "Accept" = "application/vnd.github+json" }
}

function Find-ReleaseAsset {
    param(
        [Parameter(Mandatory = $true)]$Release,
        [Parameter(Mandatory = $true)][string]$Pattern,
        [Parameter(Mandatory = $true)][string]$Description
    )

    $assets = @($Release.assets | Where-Object { $_.name -match $Pattern })
    if ($assets.Count -eq 0) {
        throw "Could not find $Description asset matching '$Pattern' in release $($Release.tag_name)."
    }

    return $assets | Sort-Object -Property name | Select-Object -First 1
}

function Save-Download {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$Path
    )

    Write-Info "Downloading $Url"
    Invoke-WebRequest -Uri $Url -OutFile $Path -UseBasicParsing -Headers @{ "User-Agent" = $UserAgent }
}

function Add-MachinePath {
    param([Parameter(Mandatory = $true)][string]$PathToAdd)

    $current = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $parts = @($current -split ";" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($parts -notcontains $PathToAdd) {
        [Environment]::SetEnvironmentVariable("Path", ($parts + $PathToAdd -join ";"), "Machine")
        $env:Path = "$env:Path;$PathToAdd"
        Write-Ok "Added $PathToAdd to the machine PATH."
    }
}

function Test-NetBirdInstalled {
    $command = Get-Command "netbird.exe" -ErrorAction SilentlyContinue
    $service = Get-Service -Name "netbird" -ErrorAction SilentlyContinue
    return ($null -ne $command -or $null -ne $service)
}

function Start-NetBirdServiceIfNeeded {
    $service = Get-Service -Name "netbird" -ErrorAction SilentlyContinue
    if ($null -ne $service -and $service.Status -ne "Running") {
        Start-Service -Name "netbird"
    }
}

function Install-NetBirdMsi {
    param(
        [Parameter(Mandatory = $true)]$Release,
        [Parameter(Mandatory = $true)][string]$Arch
    )

    $asset = Find-ReleaseAsset `
        -Release $Release `
        -Pattern "^netbird_installer_.*_windows_$Arch\.msi$" `
        -Description "Windows MSI installer"

    $msiPath = Join-Path $env:TEMP $asset.name
    Save-Download -Url $asset.browser_download_url -Path $msiPath

    Write-Info "Installing NetBird desktop client and service with MSI."
    $arguments = "/i `"$msiPath`" AUTOSTART=1 /quiet /norestart"
    $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $arguments -Wait -PassThru
    if ($process.ExitCode -notin @(0, 3010)) {
        throw "MSI installation failed with exit code $($process.ExitCode)."
    }

    Start-NetBirdServiceIfNeeded
    Write-Ok "NetBird desktop installation complete."
}

function Install-NetBirdCliOnly {
    param(
        [Parameter(Mandatory = $true)]$Release,
        [Parameter(Mandatory = $true)][string]$Arch
    )

    $asset = Find-ReleaseAsset `
        -Release $Release `
        -Pattern "^netbird_[0-9].*_windows_$Arch\.(zip|tar\.gz)$" `
        -Description "Windows CLI binary"

    $workDir = Join-Path $env:TEMP ("netbird-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $workDir -Force | Out-Null

    try {
        $archivePath = Join-Path $workDir $asset.name
        Save-Download -Url $asset.browser_download_url -Path $archivePath

        if ($asset.name.EndsWith(".zip")) {
            Expand-Archive -Path $archivePath -DestinationPath $workDir -Force
        } else {
            tar.exe -xzf $archivePath -C $workDir
        }

        $binary = Get-ChildItem -Path $workDir -Filter "netbird.exe" -Recurse | Select-Object -First 1
        if ($null -eq $binary) {
            throw "Downloaded archive did not contain netbird.exe."
        }

        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
        $target = Join-Path $InstallDir "netbird.exe"
        Copy-Item -Path $binary.FullName -Destination $target -Force
        Add-MachinePath -PathToAdd $InstallDir

        $service = Get-Service -Name "netbird" -ErrorAction SilentlyContinue
        if ($null -eq $service) {
            Write-Info "Installing NetBird Windows service."
            & $target service install
            if ($LASTEXITCODE -ne 0) {
                throw "netbird service install failed with exit code $LASTEXITCODE."
            }
        }

        Write-Info "Starting NetBird Windows service."
        & $target service start
        if ($LASTEXITCODE -ne 0) {
            throw "netbird service start failed with exit code $LASTEXITCODE."
        }

        Write-Ok "NetBird CLI-only installation complete."
    } finally {
        Remove-Item -Path $workDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Install-NetBirdWindows {
    Assert-Windows
    Assert-Administrator

    if (Test-NetBirdInstalled) {
        throw "NetBird appears to be installed already. Remove it before running this installer."
    }

    $arch = Get-NetBirdArch
    $skipUiApp = Resolve-SkipUiApp
    $release = Get-NetBirdRelease

    if ($skipUiApp) {
        Install-NetBirdCliOnly -Release $release -Arch $arch
    } else {
        Install-NetBirdMsi -Release $release -Arch $arch
    }

    Write-Host ""
    Write-Host "Installation has finished. To connect, run:"
    Write-Host "netbird up"
}

Install-NetBirdWindows
