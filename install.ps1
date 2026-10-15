# Install a verified native Henosis release for the current Windows platform.

[CmdletBinding()]
param(
    [string]$Version = $(if ($env:SYNTHEOS_VERSION) { $env:SYNTHEOS_VERSION } else { 'v0.1.0-beta.1' }),
    [string]$InstallDirectory = $(if ($env:SYNTHEOS_INSTALL_DIR) { $env:SYNTHEOS_INSTALL_DIR } else { Join-Path $HOME '.local\\bin' }),
    [string]$Experience = 'cli',
    [switch]$Headless
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Write either a human error or a machine-readable headless error and stop.
function Stop-Install {
    param([Parameter(Mandatory = $true)][string]$Message)

    if ($Headless) {
        [pscustomobject]@{ ok = $false; error = $Message } | ConvertTo-Json -Compress
    }
    else {
        Write-Error "henosis-installer: $Message"
    }
    exit 1
}

# Resolve one rename-boundary override: SYNTHEOS_<Name> is canonical and
# HENOSIS_<Name> is a read-only compatibility alias. Both set with different
# values fails closed instead of silently choosing one.
function Resolve-EnvironmentOverride {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [string]$Current
    )
    $canonical = [Environment]::GetEnvironmentVariable("SYNTHEOS_$Name")
    $legacy = [Environment]::GetEnvironmentVariable("HENOSIS_$Name")
    $canonicalIsSet = $null -ne $canonical
    $legacyIsSet = $null -ne $legacy
    if ($canonicalIsSet -and $legacyIsSet -and $canonical -ne $legacy) {
        Stop-Install "SYNTHEOS_$Name and HENOSIS_$Name are both set with different values; unset one (SYNTHEOS_$Name is canonical)"
    }
    if ($canonicalIsSet) { return $canonical }
    if ($legacyIsSet) { return $legacy }
    return $Current
}

# Explicit parameters outrank environment overrides; environment resolution
# only fills values the caller did not supply on the command line.
if (-not $PSBoundParameters.ContainsKey('Version')) {
    $Version = Resolve-EnvironmentOverride -Name 'VERSION' -Current $Version
}
if (-not $PSBoundParameters.ContainsKey('InstallDirectory')) {
    $InstallDirectory = Resolve-EnvironmentOverride -Name 'INSTALL_DIR' -Current $InstallDirectory
}
if (-not $PSBoundParameters.ContainsKey('Experience')) {
    $Experience = Resolve-EnvironmentOverride -Name 'EXPERIENCE' -Current $Experience
}
if (@('cli', 'chat', 'desktop', 'spatial') -notcontains $Experience) {
    Stop-Install "unknown experience: $Experience (choose cli, chat, desktop, or spatial)"
}
$Experience = $Experience.ToLowerInvariant()

# Return an absolute HTTPS release base without credentials, query, or fragment.
function Get-ReleaseBase {
    $candidate = (Resolve-EnvironmentOverride -Name 'RELEASE_BASE' -Current 'https://github.com/Null-Logix/henosis-releases/releases/download').TrimEnd('/')
    $uri = $null
    if (-not [Uri]::TryCreate($candidate, [UriKind]::Absolute, [ref]$uri) -or
        $uri.Scheme -ne [Uri]::UriSchemeHttps -or
        -not [string]::IsNullOrEmpty($uri.UserInfo) -or
        -not [string]::IsNullOrEmpty($uri.Query) -or
        -not [string]::IsNullOrEmpty($uri.Fragment)) {
        Stop-Install 'SYNTHEOS_RELEASE_BASE must be an absolute HTTPS URL without credentials, query, or fragment'
    }
    return $uri.AbsoluteUri.TrimEnd('/')
}

# Return an absolute HTTPS release metadata API without credentials, query, or fragment.
function Get-ReleaseApi {
    $candidate = (Resolve-EnvironmentOverride -Name 'RELEASE_API' -Current 'https://api.github.com/repos/Null-Logix/henosis-releases/releases/tags').TrimEnd('/')
    $uri = $null
    if (-not [Uri]::TryCreate($candidate, [UriKind]::Absolute, [ref]$uri) -or
        $uri.Scheme -ne [Uri]::UriSchemeHttps -or
        -not [string]::IsNullOrEmpty($uri.UserInfo) -or
        -not [string]::IsNullOrEmpty($uri.Query) -or
        -not [string]::IsNullOrEmpty($uri.Fragment)) {
        Stop-Install 'SYNTHEOS_RELEASE_API must be an absolute HTTPS URL without credentials, query, or fragment'
    }
    return $uri.AbsoluteUri.TrimEnd('/')
}

# Return the release target supported by this Windows host.
function Get-ReleaseTarget {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        Stop-Install 'this installer supports Windows only'
    }
    if ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture -ne [System.Runtime.InteropServices.Architecture]::X64) {
        Stop-Install "unsupported Windows architecture: $([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture)"
    }
    return 'x86_64-pc-windows-msvc'
}

# Return the SHA-256 digest for one file in lowercase hexadecimal form.
function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string]$Path)

    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

# Extract the mandatory checksum for one archive and verify its contents.
function Assert-ArchiveChecksum {
    param(
        [Parameter(Mandatory = $true)][string]$ManifestPath,
        [Parameter(Mandatory = $true)][string]$ArchivePath,
        [Parameter(Mandatory = $true)][string]$ArchiveName
    )

    $entries = @(Get-Content -LiteralPath $ManifestPath | Where-Object { $_ -match "^([0-9a-fA-F]{64})\s+\*?$([regex]::Escape($ArchiveName))$" })
    if ($entries.Count -ne 1) { Stop-Install "checksum manifest has no unique entry for $ArchiveName" }
    $expected = ([regex]::Match($entries[0], '^[0-9a-fA-F]{64}')).Value.ToLowerInvariant()
    if ((Get-Sha256 -Path $ArchivePath) -ne $expected) { Stop-Install "checksum verification failed for $ArchiveName" }
}

# Download a release file with PowerShell's native HTTPS client.
function Get-ReleaseFile {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][string]$OutFile
    )

    Invoke-WebRequest -UseBasicParsing -Uri $Uri -OutFile $OutFile
}

# Require the release API document to identify a published immutable release.
function Assert-ImmutableRelease {
    param([Parameter(Mandatory = $true)][string]$Path)

    if ((Get-Item -LiteralPath $Path).Length -gt 1MB) { Stop-Install 'release metadata exceeds the 1 MiB safety limit' }
    try { $metadata = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json }
    catch { Stop-Install 'release metadata is not valid JSON' }
    if ($metadata.tag_name -ne $Version) { Stop-Install 'release metadata does not match the selected version' }
    if ($metadata.draft -ne $false) { Stop-Install 'selected release is not published' }
    if ($metadata.immutable -ne $true) { Stop-Install 'selected release is not immutable' }
}

# Resolve adjacent Henosis and Crucible binaries from a verified release archive.
function Get-ArchiveBinaries {
    param([Parameter(Mandatory = $true)][string]$Target)

    $marker = Join-Path $PSScriptRoot 'HENOSIS_ARCHIVE'
    if (-not (Test-Path -LiteralPath $marker -PathType Leaf)) { return $null }
    $parts = @((Get-Content -LiteralPath $marker -Raw).Trim() -split '\s+')
    if ($parts.Count -ne 2 -or $parts[0] -ne $Version -or $parts[1] -ne $Target) {
        Stop-Install 'release archive marker does not match this installer'
    }
    $henosisCandidate = Join-Path $PSScriptRoot 'henosis.exe'
    $crucibleCandidate = Join-Path $PSScriptRoot 'crucible.exe'
    if (-not (Test-Path -LiteralPath $henosisCandidate -PathType Leaf)) {
        Stop-Install 'release archive does not contain an adjacent henosis.exe'
    }
    if (-not (Test-Path -LiteralPath $crucibleCandidate -PathType Leaf)) {
        Stop-Install 'release archive does not contain an adjacent crucible.exe'
    }
    return [pscustomobject]@{ Henosis = $henosisCandidate; Crucible = $crucibleCandidate }
}

# Reject reparse points in a path or its ancestors and require the expected slot type.
function Assert-InstallPath {
    param([string]$Path, [switch]$Directory, [switch]$AllowMissing)

    $absolute = [System.IO.Path]::GetFullPath($Path)
    $attributes = $null
    try { $attributes = [System.IO.File]::GetAttributes($absolute) }
    catch [System.IO.FileNotFoundException] { }
    catch [System.IO.DirectoryNotFoundException] { }
    if ($null -eq $attributes) {
        if (-not $AllowMissing) { Stop-Install "required installation path is missing: $absolute" }
    }
    else {
        if (($attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { Stop-Install "installation path is a reparse point: $absolute" }
        $isDirectory = ($attributes -band [System.IO.FileAttributes]::Directory) -ne 0
        if ($isDirectory -ne [bool]$Directory) {
            $expected = if ($Directory) { 'directory' } else { 'regular file' }
            Stop-Install "installation path must be a $expected`: $absolute"
        }
    }
    $parent = [System.IO.DirectoryInfo]::new($absolute).Parent
    while ($null -ne $parent) {
        try {
            $parentAttributes = [System.IO.File]::GetAttributes($parent.FullName)
            if (($parentAttributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { Stop-Install "installation ancestor is a reparse point: $($parent.FullName)" }
        }
        catch [System.IO.FileNotFoundException] { }
        catch [System.IO.DirectoryNotFoundException] { }
        $parent = $parent.Parent
    }
}

# Move one exact owned file without overwriting a concurrent destination.
function Move-InstalledFile {
    param([string]$Source, [string]$Destination)
    Assert-InstallPath -Path $Source
    Assert-InstallPath -Path $Destination -AllowMissing
    [System.IO.File]::Move($Source, $Destination)
}

# Run initialization against the newly activated binary and require success.
function Invoke-CliInitialization {
    param([string]$Path)
    & $Path init --quick
    if ($LASTEXITCODE -ne 0) { throw 'henosis init --quick failed; the installer is restoring the previous CLI installation' }
}

# Stage both binaries and the ownership marker, retaining originals for recovery.
function Install-Release {
    param([System.IO.FileStream]$OwnedLock = $null)

    if ($Version -notmatch '^v[0-9][0-9A-Za-z._-]*$') { Stop-Install 'release version must be a valid v-prefixed tag' }
    $target = Get-ReleaseTarget
    $archiveName = "henosis-$($Version.TrimStart('v'))-$target.zip"
    $workDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("henosis-install-" + [guid]::NewGuid().ToString('N'))
    $installPath = [System.IO.Path]::GetFullPath($InstallDirectory)
    $destination = Join-Path $installPath 'henosis.exe'
    $crucibleDestination = Join-Path $installPath 'crucible.exe'
    $markerDestination = Join-Path $installPath '.henosis-installation'
    $transactionDirectory = Join-Path $installPath ('.henosis-install-' + [guid]::NewGuid().ToString('N'))
    $lockPath = Join-Path $installPath '.henosis-install.lock'
    $lock = $null
    $entries = @()
    $committed = $false
    try {
        New-Item -ItemType Directory -Path $workDirectory | Out-Null
        $candidates = Get-ArchiveBinaries -Target $target
        if ($null -eq $candidates) {
            $releaseBase = Get-ReleaseBase
            $releaseApi = Get-ReleaseApi
            $metadataPath = Join-Path $workDirectory 'release.json'
            Get-ReleaseFile -Uri "$releaseApi/$Version" -OutFile $metadataPath
            Assert-ImmutableRelease -Path $metadataPath
            Get-ReleaseFile -Uri "$releaseBase/$Version/SHA256SUMS" -OutFile (Join-Path $workDirectory 'SHA256SUMS')
            $archivePath = Join-Path $workDirectory $archiveName
            Get-ReleaseFile -Uri "$releaseBase/$Version/$archiveName" -OutFile $archivePath
            Assert-ArchiveChecksum -ManifestPath (Join-Path $workDirectory 'SHA256SUMS') -ArchivePath $archivePath -ArchiveName $archiveName
            Expand-Archive -LiteralPath $archivePath -DestinationPath $workDirectory -Force
            $contentDirectory = Join-Path $workDirectory "henosis-$($Version.TrimStart('v'))-$target"
            $candidate = Join-Path $contentDirectory 'henosis.exe'
            $crucibleCandidate = Join-Path $contentDirectory 'crucible.exe'
            if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { Stop-Install 'verified archive does not contain henosis.exe' }
            if (-not (Test-Path -LiteralPath $crucibleCandidate -PathType Leaf)) { Stop-Install 'verified archive does not contain crucible.exe' }
            $candidates = [pscustomobject]@{ Henosis = $candidate; Crucible = $crucibleCandidate }
        }
        Assert-InstallPath -Path $installPath -Directory -AllowMissing
        foreach ($path in @($destination, $crucibleDestination, $markerDestination, $lockPath)) { Assert-InstallPath -Path $path -AllowMissing }
        Assert-InstallPath -Path $candidates.Henosis
        Assert-InstallPath -Path $candidates.Crucible
        New-Item -ItemType Directory -Force -Path $installPath | Out-Null
        Assert-InstallPath -Path $installPath -Directory
        if ($null -ne $OwnedLock) {
            if (-not $OwnedLock.CanWrite -or $OwnedLock.Name -ne $lockPath) { throw 'the lifecycle helper supplied an invalid installation lock' }
        }
        else {
            try { $lock = [System.IO.File]::Open($lockPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None) }
            catch { throw "installation lock could not be acquired at $lockPath; check for an active installer before relocating a stale lock: $_" }
        }
        $stageDirectory = Join-Path $transactionDirectory 'staged'
        $previousDirectory = Join-Path $transactionDirectory 'previous'
        New-Item -ItemType Directory -Path $stageDirectory, $previousDirectory | Out-Null
        Copy-Item -LiteralPath $candidates.Henosis -Destination (Join-Path $stageDirectory 'henosis.exe')
        Copy-Item -LiteralPath $candidates.Crucible -Destination (Join-Path $stageDirectory 'crucible.exe')
        [System.IO.File]::WriteAllText((Join-Path $stageDirectory '.henosis-installation'), "format=1`nexperience=cli`nversion=$Version`n", [System.Text.UTF8Encoding]::new($false))
        foreach ($path in @($destination, $crucibleDestination, $markerDestination)) {
            $name = [System.IO.Path]::GetFileName($path)
            $entry = [pscustomobject]@{ Destination = $path; Stage = (Join-Path $stageDirectory $name); Backup = (Join-Path $previousDirectory $name); PreviousMoved = $false; Activated = $false }
            $entries += $entry
            Assert-InstallPath -Path $path -AllowMissing
            if ([System.IO.File]::Exists($path)) {
                Move-InstalledFile -Source $path -Destination $entry.Backup
                $entry.PreviousMoved = $true
            }
            Move-InstalledFile -Source $entry.Stage -Destination $path
            $entry.Activated = $true
        }
        Invoke-CliInitialization -Path $destination
        $committed = $true
        if ($Headless) {
            [pscustomobject]@{ ok = $true; experience = 'cli'; binary = $destination; crucible = $crucibleDestination; version = $Version; target = $target; recoveryDirectory = $transactionDirectory } | ConvertTo-Json -Compress
        }
        else { Write-Host "henosis-installer: installed $destination; previous files retained for recovery at $transactionDirectory" }
    }
    catch {
        $failure = $_
        if ($committed) { Stop-Install "CLI installation committed, but reporting failed: $failure; recovery files retained at $transactionDirectory" }
        $rollbackFailures = @()
        if (-not $committed) {
            for ($index = $entries.Count - 1; $index -ge 0; $index--) {
                $entry = $entries[$index]
                try {
                    if ($entry.Activated) { Move-InstalledFile -Source $entry.Destination -Destination $entry.Stage }
                    if ($entry.PreviousMoved) { Move-InstalledFile -Source $entry.Backup -Destination $entry.Destination }
                }
                catch { $rollbackFailures += $_.ToString() }
            }
        }
        if ($rollbackFailures.Count -gt 0) { Stop-Install "installation failed: $failure; rollback incomplete: $($rollbackFailures -join '; '); recovery files retained at $transactionDirectory" }
        if (Test-Path -LiteralPath $transactionDirectory -PathType Container) { Stop-Install "installation failed: $failure; previous CLI files restored; failed candidate retained for recovery at $transactionDirectory" }
        Stop-Install "installation failed before activation: $failure"
    }
    finally {
        if ($null -ne $lock) { $lock.Dispose(); [System.IO.File]::Delete($lockPath) }
        Remove-Item -LiteralPath $workDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Resolve the platform application-data directory for the graphical renderer.
function Get-DesktopPreferenceDirectory {
    return Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::ApplicationData)) 'systems.syntheos.henosis'
}

# Resolve retained verified package bundles under per-user local application data.
function Get-DesktopRecoveryRoot {
    return Join-Path (Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)) 'systems.syntheos.henosis') 'installers'
}

# Atomically persist one non-secret graphical renderer in Tauri application data.
function Write-ExperiencePreference {
    $preferenceDirectory = Get-DesktopPreferenceDirectory
    $preferencePath = Join-Path $preferenceDirectory 'experience.json'
    $temporaryPath = Join-Path $preferenceDirectory ('.experience.json.new.' + [guid]::NewGuid().ToString('N'))
    Assert-InstallPath -Path $preferenceDirectory -Directory -AllowMissing
    Assert-InstallPath -Path $preferencePath -AllowMissing
    New-Item -ItemType Directory -Force -Path $preferenceDirectory | Out-Null
    try {
        [System.IO.File]::WriteAllText($temporaryPath, ('"' + $Experience + '"' + [Environment]::NewLine), [System.Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporaryPath -Destination $preferencePath -Force
    }
    finally {
        Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
    }
}

# Download, verify, and run the shared desktop installer for one graphical profile.
function Install-DesktopExperience {
    if ($Version -notmatch '^v[0-9][0-9A-Za-z._-]*$') { Stop-Install 'release version must be a valid v-prefixed tag' }
    $target = Get-ReleaseTarget
    $assetName = "henosis-desktop-$($Version.TrimStart('v'))-windows-x86_64.exe"
    $workDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("henosis-desktop-install-" + [guid]::NewGuid().ToString('N'))
    $recoveryDirectory = $null
    $lock = $null
    $lockPath = $null
    $processStarted = $false
    $packageInstalled = $false
    $preferenceCommitted = $false
    try {
        New-Item -ItemType Directory -Force -Path $workDirectory | Out-Null
        $releaseBase = Get-ReleaseBase
        $releaseApi = Get-ReleaseApi
        $metadataPath = Join-Path $workDirectory 'release.json'
        $manifestPath = Join-Path $workDirectory 'SHA256SUMS'
        $installerPath = Join-Path $workDirectory $assetName
        Get-ReleaseFile -Uri "$releaseApi/$Version" -OutFile $metadataPath
        Assert-ImmutableRelease -Path $metadataPath
        Get-ReleaseFile -Uri "$releaseBase/$Version/SHA256SUMS" -OutFile $manifestPath
        Get-ReleaseFile -Uri "$releaseBase/$Version/$assetName" -OutFile $installerPath
        Assert-ArchiveChecksum -ManifestPath $manifestPath -ArchivePath $installerPath -ArchiveName $assetName
        $recoveryRoot = Get-DesktopRecoveryRoot
        Assert-InstallPath -Path $recoveryRoot -Directory -AllowMissing
        [System.IO.Directory]::CreateDirectory($recoveryRoot) | Out-Null
        Assert-InstallPath -Path $recoveryRoot -Directory
        $lockPath = Join-Path $recoveryRoot '.henosis-desktop-install.lock'
        Assert-InstallPath -Path $lockPath -AllowMissing
        try { $lock = [System.IO.File]::Open($lockPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None) }
        catch { throw "graphical installation lock could not be acquired: $lockPath" }
        $preferenceDirectory = Get-DesktopPreferenceDirectory
        $preferencePath = Join-Path $preferenceDirectory 'experience.json'
        Assert-InstallPath -Path $preferenceDirectory -Directory -AllowMissing
        Assert-InstallPath -Path $preferencePath -AllowMissing
        $recoveryDirectory = Join-Path $recoveryRoot ($Version + '-' + [guid]::NewGuid().ToString('N'))
        [System.IO.Directory]::CreateDirectory($recoveryDirectory) | Out-Null
        Assert-InstallPath -Path $recoveryDirectory -Directory
        $retainedInstaller = Join-Path $recoveryDirectory $assetName
        Move-InstalledFile -Source $metadataPath -Destination (Join-Path $recoveryDirectory 'release.json')
        Move-InstalledFile -Source $manifestPath -Destination (Join-Path $recoveryDirectory 'SHA256SUMS')
        Move-InstalledFile -Source $installerPath -Destination $retainedInstaller
        if (Test-Path -LiteralPath $preferencePath -PathType Leaf) {
            [System.IO.File]::Copy($preferencePath, (Join-Path $recoveryDirectory 'experience.previous.json'), $false)
        }
        Assert-ArchiveChecksum -ManifestPath (Join-Path $recoveryDirectory 'SHA256SUMS') -ArchivePath $retainedInstaller -ArchiveName $assetName
        $processStarted = $true
        if ($Headless) {
            $process = Start-Process -FilePath $retainedInstaller -ArgumentList '/S' -Wait -PassThru
        }
        else {
            $process = Start-Process -FilePath $retainedInstaller -Wait -PassThru
        }
        if ($process.ExitCode -ne 0) { throw "desktop installer exited with code $($process.ExitCode)" }
        $packageInstalled = $true
        Write-ExperiencePreference
        $preferenceCommitted = $true
        $lock.Dispose()
        $lock = $null
        [System.IO.File]::Delete($lockPath)
        if ($Headless) {
            [pscustomobject]@{ ok = $true; experience = $Experience; desktopInstaller = $assetName; version = $Version; target = $target; recoveryDirectory = $recoveryDirectory } | ConvertTo-Json -Compress
        }
        else { Write-Host "henosis-installer: installed the $Experience experience; verified installer retained at $recoveryDirectory" }
    }
    catch {
        $failure = $_
        if ($packageInstalled -and -not $preferenceCommitted) { Stop-Install "desktop package installed, but renderer preference failed: $failure; recovery files retained at $recoveryDirectory" }
        if ($packageInstalled) { Stop-Install "desktop package installed, but finalization failed: $failure; recovery files retained at $recoveryDirectory" }
        if ($processStarted) { Stop-Install "desktop installer failed: $failure; application files may have changed; recovery files retained at $recoveryDirectory" }
        if ($null -ne $recoveryDirectory) { Stop-Install "desktop installation failed before process launch: $failure; recovery files retained at $recoveryDirectory" }
        Stop-Install "desktop installation failed before process launch: $failure"
    }
    finally {
        if ($null -ne $lock) { $lock.Dispose(); [System.IO.File]::Delete($lockPath) }
        Remove-Item -LiteralPath $workDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Dispatch the validated experience to its matching signed distribution.
function Install-SelectedExperience {
    if ($Experience -eq 'cli') {
        Install-Release
    }
    else {
        Install-DesktopExperience
    }
}

Install-SelectedExperience
