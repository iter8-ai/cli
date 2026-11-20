# Run with: pwsh -NoProfile -File tests/install.Tests.ps1
$ErrorActionPreference = 'Stop'
$installer = Join-Path (Split-Path -Parent $PSScriptRoot) 'install.ps1'
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($installer, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) {
    throw ($parseErrors | Out-String)
}

& (Get-Process -Id $PID).Path -NoProfile -File (Join-Path $PSScriptRoot 'install-scope.Tests.ps1') $installer
if ($LASTEXITCODE -ne 0) { throw 'Installer caller-scope regression failed' }

$savedVersion = $env:REITERATE_VERSION
$savedInstallDir = $env:REITERATE_INSTALL_DIR
$savedArchitecture = $env:PROCESSOR_ARCHITECTURE
$savedWowArchitecture = $env:PROCESSOR_ARCHITEW6432
$tmp = Join-Path ([IO.Path]::GetTempPath()) ([IO.Path]::GetRandomFileName())
try {
    foreach ($definition in $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
        . ([scriptblock]::Create($definition.Extent.Text))
    }

    $env:PROCESSOR_ARCHITEW6432 = ''
    foreach ($architecture in @('AMD64', 'ARM64')) {
        $env:PROCESSOR_ARCHITECTURE = $architecture
        if ((Get-ReiterateArchitecture) -cne $architecture.ToLowerInvariant()) {
            throw "Wrong architecture for $architecture"
        }
    }
    $env:PROCESSOR_ARCHITECTURE = 'x86'
    foreach ($architecture in @('AMD64', 'ARM64')) {
        $env:PROCESSOR_ARCHITEW6432 = $architecture
        if ((Get-ReiterateArchitecture) -cne $architecture.ToLowerInvariant()) {
            throw "Wrong native architecture for $architecture"
        }
    }
    $env:PROCESSOR_ARCHITEW6432 = ''
    $rejected = $false
    try { Get-ReiterateArchitecture } catch { $rejected = $_.Exception.Message -like '*unsupported architecture*' }
    if (-not $rejected) { throw 'Unsupported architecture was accepted' }

    New-Item -ItemType Directory -Path $tmp | Out-Null
    $file = 'reiterate-windows-amd64.exe'
    $binary = Join-Path $tmp $file
    $checksums = Join-Path $tmp 'checksums.txt'
    [IO.File]::WriteAllText($binary, 'abc')
    $hash = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
    [IO.File]::WriteAllText($checksums, "$hash  $file`n")
    Assert-ReiterateChecksum -BinaryPath $binary -ChecksumsPath $checksums

    foreach ($invalid in @('', "$hash  another.exe", "$hash  $file`n$hash  $file", "$hash  $file`n$hash  $file ", "invalid  $file", "$hash $file", "$hash  $file ", ('0' * 64 + "  $file"))) {
        [IO.File]::WriteAllText($checksums, $invalid)
        $rejected = $false
        try { Assert-ReiterateChecksum -BinaryPath $binary -ChecksumsPath $checksums } catch { $rejected = $_.Exception.Message -like '*nothing installed*' }
        if (-not $rejected) { throw "Invalid checksum was accepted: $invalid" }
    }
    & {
        $env:PROCESSOR_ARCHITECTURE = 'AMD64'
        $env:REITERATE_INSTALL_DIR = Join-Path $tmp 'directory-failure'
        $directories = [Collections.Generic.List[string]]::new()
        function New-Item {
            param($ItemType, $Path, [switch]$Force)
            $directories.Add($Path)
            if ($failedDirectory -eq 'temporary' -or $Path -eq $env:REITERATE_INSTALL_DIR) {
                throw "Cannot create $failedDirectory directory"
            }
            Microsoft.PowerShell.Management\New-Item @PSBoundParameters
        }
        foreach ($failedDirectory in @('temporary', 'install')) {
            $directories.Clear()
            $failure = ''
            try { & $installer } catch { $failure = $_.Exception.Message }
            if ($failure -cne "Cannot create $failedDirectory directory") {
                throw "Directory-creation error was replaced: $failure"
            }
            if ($directories.Count -eq 0 -or (Test-Path -LiteralPath $directories[0])) {
                throw 'Directory-creation failure left temporary staging behind'
            }
        }
        Write-Output 'PASS: directory-creation failures preserve errors and clean temporary staging'
    }
    & {
        $env:PROCESSOR_ARCHITECTURE = 'AMD64'
        $env:REITERATE_VERSION = '1.2.3'
        $env:REITERATE_INSTALL_DIR = Join-Path $tmp 'install'
        $downloads = [Collections.Generic.List[string]]::new()
        $pathBefore = $env:Path
        function Invoke-WebRequest {
            param($Uri, $OutFile, [switch]$UseBasicParsing, $SslProtocol)
            $downloads.Add($OutFile)
            if ($Uri -like '*/checksums.txt') {
                [IO.File]::WriteAllText($OutFile, ('0' * 64 + "  reiterate-windows-amd64.exe`n"))
            } else {
                [IO.File]::WriteAllText($OutFile, 'abc')
            }
        }
        $failure = ''
        try { & $installer } catch { $failure = $_.Exception.Message }
        if ($downloads.Count -ne 2 -or (Split-Path -Parent $downloads[0]) -cne $env:REITERATE_INSTALL_DIR) {
            throw 'Binary staging must be inside REITERATE_INSTALL_DIR'
        }
        if ((Split-Path -Leaf $downloads[0]) -notlike '.reiterate-install-*.exe') {
            throw 'Binary staging must use a unique installer filename'
        }
        if ($failure -notlike '*checksum mismatch*' -or $env:Path -cne $pathBefore) {
            throw "Bad checksum must stop before PATH or registry access: $failure"
        }
        if (Test-Path -LiteralPath $downloads[0]) { throw 'Failed installation left binary staging behind' }
        Write-Output 'PASS: same-directory binary staging and checksum-failure cleanup'
    }
    & {
        $env:PROCESSOR_ARCHITECTURE = 'AMD64'
        $env:REITERATE_INSTALL_DIR = Join-Path $tmp 'release-tests'
        $uris = [Collections.Generic.List[string]]::new()
        $manifestVersion = '9.8.7'
        function Invoke-RestMethod {
            param($Uri, [switch]$UseBasicParsing, $SslProtocol)
            $uris.Add($Uri)
            return @{ version = $manifestVersion }
        }
        function Invoke-WebRequest {
            param($Uri, $OutFile, [switch]$UseBasicParsing, $SslProtocol)
            $uris.Add($Uri)
            if ($Uri -like '*/checksums.txt') {
                [IO.File]::WriteAllText($OutFile, ('0' * 64 + "  reiterate-windows-amd64.exe`n"))
            } else {
                [IO.File]::WriteAllText($OutFile, 'abc')
            }
        }
        $pinned = @('https://github.com/iter8-ai/cli/releases/download/v9.8.7/reiterate-windows-amd64.exe', 'https://github.com/iter8-ai/cli/releases/download/v9.8.7/checksums.txt')
        foreach ($requested in @('', 'latest', '9.8.7', 'v9.8.7')) {
            $env:REITERATE_VERSION = $requested
            $uris.Clear()
            $failure = ''
            try { & $installer } catch { $failure = $_.Exception.Message }
            $expected = $pinned
            if (-not $requested -or $requested -eq 'latest') {
                $expected = @('https://github.com/iter8-ai/cli/releases/latest/download/manifest.json') + $pinned
            }
            if (($uris -join "`n") -cne ($expected -join "`n")) {
                throw "Latest must resolve one manifest and pin both assets to v9.8.7: $($uris -join ', ')"
            }
            if ($failure -notlike '*checksum mismatch*') { throw "Unexpected pinned-download failure: $failure" }
        }
        foreach ($invalid in @('', 'v9.8.7', 'invalid', "9.8.7`n")) {
            $env:REITERATE_VERSION = 'latest'
            $manifestVersion = $invalid
            $uris.Clear()
            $failure = ''
            try { & $installer } catch { $failure = $_.Exception.Message }
            if ($failure -notlike '*reiterate: could not resolve the latest release version*' -or $uris.Count -ne 1) {
                throw "Invalid latest version was accepted: '$invalid' ($failure)"
            }
        }
        foreach ($invalid in @('invalid', 'vv9.8.7', "9.8.7`n")) {
            $env:REITERATE_VERSION = $invalid
            $uris.Clear()
            $failure = ''
            try { & $installer } catch { $failure = $_.Exception.Message }
            if ($failure -notlike '*invalid release version*' -or $uris.Count -ne 0) {
                throw "Invalid explicit version was accepted: '$invalid' ($failure)"
            }
        }
        if (Test-Path -LiteralPath (Join-Path $env:REITERATE_INSTALL_DIR 'reiterate.exe')) { throw 'Version-resolution tests installed a binary' }
        if (Get-ChildItem -LiteralPath $env:REITERATE_INSTALL_DIR -Filter '.reiterate-install-*') { throw 'Version-resolution tests left staging files' }
        Write-Output 'PASS: PowerShell latest resolution pins both assets and validates manifest/explicit versions'
    }
    Write-Output 'PASS: parser, caller preferences, AMD64/ARM64/WOW64 architecture, unsupported architecture, checksum match and rejection cases'
} finally {
    $env:REITERATE_VERSION = $savedVersion
    $env:REITERATE_INSTALL_DIR = $savedInstallDir
    $env:PROCESSOR_ARCHITECTURE = $savedArchitecture
    $env:PROCESSOR_ARCHITEW6432 = $savedWowArchitecture
    if (Test-Path -LiteralPath $tmp) {
        Remove-Item -LiteralPath $tmp -Recurse -Force
    }
}
