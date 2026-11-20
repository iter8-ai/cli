# Run with: pwsh -NoProfile -File tests/install.Tests.ps1
$ErrorActionPreference = 'Stop'
$installer = Join-Path (Split-Path -Parent $PSScriptRoot) 'install.ps1'
$tokens = $null
$parseErrors = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile($installer, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) {
    throw ($parseErrors | Out-String)
}

$savedDryRun = $env:REITERATE_INSTALL_DRYRUN
$savedArchitecture = $env:PROCESSOR_ARCHITECTURE
$savedWowArchitecture = $env:PROCESSOR_ARCHITEW6432
$tmp = Join-Path ([IO.Path]::GetTempPath()) ([IO.Path]::GetRandomFileName())
try {
    $env:REITERATE_INSTALL_DRYRUN = '1'
    $sessionPath = $env:Path
    $securityProtocol = [Net.ServicePointManager]::SecurityProtocol
    $savedProgressPreference = $ProgressPreference
    $ErrorActionPreference = 'Continue'
    $ProgressPreference = 'Continue'
    . $installer
    if ($env:Path -cne $sessionPath -or [Net.ServicePointManager]::SecurityProtocol -ne $securityProtocol -or $ErrorActionPreference -ne 'Continue' -or $ProgressPreference -ne 'Continue') {
        throw 'Dry run changed caller preferences, PATH or TLS settings'
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
    Write-Output 'PASS: parser, dry-run caller preferences, AMD64/ARM64/WOW64 architecture, unsupported architecture, checksum match and rejection cases'
} finally {
    $env:REITERATE_INSTALL_DRYRUN = $savedDryRun
    $env:PROCESSOR_ARCHITECTURE = $savedArchitecture
    $env:PROCESSOR_ARCHITEW6432 = $savedWowArchitecture
    if (Test-Path -LiteralPath $tmp) {
        Remove-Item -LiteralPath $tmp -Recurse -Force
    }
}
