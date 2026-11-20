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
    $sessionPath = $env:Path
    $securityProtocol = [Net.ServicePointManager]::SecurityProtocol
    $savedProgressPreference = $ProgressPreference
    $ErrorActionPreference = 'Continue'
    $ProgressPreference = 'Continue'
    foreach ($definition in $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
        . ([scriptblock]::Create($definition.Extent.Text))
    }
    if ($env:Path -cne $sessionPath -or [Net.ServicePointManager]::SecurityProtocol -ne $securityProtocol -or $ErrorActionPreference -ne 'Continue' -or $ProgressPreference -ne 'Continue') {
        throw 'Loading helpers changed caller preferences, PATH or TLS settings'
    }
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = $savedProgressPreference

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
