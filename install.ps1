# Installs the Reiterate CLI from the latest public release.
#   irm https://raw.githubusercontent.com/iter8-ai/cli/main/install.ps1 | iex
# Settings: REITERATE_INSTALL_DIR (default $env:LOCALAPPDATA\Programs\reiterate), REITERATE_VERSION (default latest)
$ErrorActionPreference = 'Stop'

function Get-ReiterateArchitecture {
    $architecture = $env:PROCESSOR_ARCHITECTURE
    if ($env:PROCESSOR_ARCHITEW6432) {
        $architecture = $env:PROCESSOR_ARCHITEW6432
    }
    switch ($architecture) {
        'AMD64' { return 'amd64' }
        'ARM64' { return 'arm64' }
        default { throw "reiterate: unsupported architecture '$architecture'; Windows AMD64 and ARM64 only" }
    }
}

function Assert-ReiterateChecksum {
    param([string]$BinaryPath, [string]$ChecksumsPath)

    $file = Split-Path -Leaf $BinaryPath
    $entries = @(Get-Content -LiteralPath $ChecksumsPath | Where-Object { ($_.Trim() -split '\s+')[-1] -ceq $file })
    if ($entries.Count -ne 1 -or $entries[0] -cnotmatch ('^([a-fA-F0-9]{64})  ' + [regex]::Escape($file) + '$')) {
        throw "reiterate: missing or invalid checksum for $file; nothing installed"
    }
    $expected = $Matches[1]
    $actual = (Get-FileHash -LiteralPath $BinaryPath -Algorithm SHA256).Hash
    if ($expected -ne $actual) {
        throw "reiterate: checksum mismatch for $file; nothing installed"
    }
}

if ($env:REITERATE_INSTALL_DRYRUN -eq '1') {
    return
}

$architecture = Get-ReiterateArchitecture
$file = "reiterate-windows-$architecture.exe"
$dir = $env:REITERATE_INSTALL_DIR
if (-not $dir) {
    $dir = Join-Path $env:LOCALAPPDATA 'Programs\reiterate'
}
$dir = [IO.Path]::GetFullPath($dir)
$version = $env:REITERATE_VERSION
if (-not $version -or $version -eq 'latest') {
    $base = 'https://github.com/iter8-ai/cli/releases/latest/download'
} else {
    $base = 'https://github.com/iter8-ai/cli/releases/download/v' + $version.TrimStart('v')
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$downloadOptions = @{ UseBasicParsing = $true }
if ($PSVersionTable.PSVersion.Major -ge 6) {
    $downloadOptions.SslProtocol = 'Tls12'
}
$tmp = Join-Path ([IO.Path]::GetTempPath()) ([IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
    $binary = Join-Path $tmp $file
    $checksums = Join-Path $tmp 'checksums.txt'
    Invoke-WebRequest -Uri "$base/$file" -OutFile $binary @downloadOptions
    Invoke-WebRequest -Uri "$base/checksums.txt" -OutFile $checksums @downloadOptions
    Assert-ReiterateChecksum -BinaryPath $binary -ChecksumsPath $checksums

    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $target = Join-Path $dir 'reiterate.exe'
    $old = "$target.old"
    if (Test-Path -LiteralPath $target) {
        if (Test-Path -LiteralPath $old) {
            Remove-Item -LiteralPath $old -Force
        }
        # Windows can rename a running executable even when it cannot overwrite it.
        Rename-Item -LiteralPath $target -NewName 'reiterate.exe.old'
    }
    try {
        Move-Item -LiteralPath $binary -Destination $target
    } catch {
        if ((Test-Path -LiteralPath $old) -and -not (Test-Path -LiteralPath $target)) {
            Rename-Item -LiteralPath $old -NewName 'reiterate.exe'
        }
        throw
    }

    [string]$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (@($userPath -split ';' | ForEach-Object { $_.Trim().TrimEnd('\') }) -notcontains $dir.TrimEnd('\')) {
        [Environment]::SetEnvironmentVariable('Path', ($userPath.TrimEnd(';') + ';' + $dir).TrimStart(';'), 'User')
    }
    [string]$sessionPath = $env:Path
    if (@($sessionPath -split ';' | ForEach-Object { $_.Trim().TrimEnd('\') }) -notcontains $dir.TrimEnd('\')) {
        $env:Path = ($sessionPath.TrimEnd(';') + ';' + $dir).TrimStart(';')
    }

    $installedVersion = & $target version
    if ($LASTEXITCODE -ne 0) {
        throw "reiterate: installed executable could not report its version (exit $LASTEXITCODE)"
    }
    Write-Output "Installed $installedVersion to $target"
    Write-Output 'Next:  reiterate login'
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force
}
