# Run in a fresh process to model `irm ... | iex` without test helpers in scope.
param([string]$Installer)
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'Continue'
$env:PROCESSOR_ARCHITECTURE = 'AMD64'
$env:PROCESSOR_ARCHITEW6432 = ''
$env:REITERATE_VERSION = '1.2.3'
$env:REITERATE_INSTALL_DIR = Join-Path ([IO.Path]::GetTempPath()) ([IO.Path]::GetRandomFileName())
$sessionPath = $env:Path
$securityProtocol = [Net.ServicePointManager]::SecurityProtocol
$file = 'sentinel file'
$dir = 'sentinel dir'
$version = 'sentinel version'
$base = 'sentinel base'
$tmp = 'sentinel tmp'
$binary = 'sentinel binary'
function Invoke-WebRequest { throw 'offline scope test' }
try {
    $failure = ''
    try { Invoke-Expression (Get-Content -Raw -LiteralPath $Installer) } catch { $failure = $_.Exception.Message }
    if ($failure -ne 'offline scope test') { throw "Unexpected installer failure: $failure" }
    if (Get-Command Get-ReiterateArchitecture, Assert-ReiterateChecksum -ErrorAction SilentlyContinue) {
        throw 'Invoke-Expression leaked installer functions into caller scope'
    }
    foreach ($name in @('file', 'dir', 'version', 'base', 'tmp', 'binary')) {
        if ((Get-Variable -Name $name -ValueOnly) -cne "sentinel $name") {
            throw "Invoke-Expression changed caller variable $name"
        }
    }
    if ($env:Path -cne $sessionPath -or [Net.ServicePointManager]::SecurityProtocol -ne $securityProtocol -or $ErrorActionPreference -ne 'Continue' -or $ProgressPreference -ne 'Continue') {
        throw 'Invoke-Expression changed caller preferences, PATH or TLS settings'
    }
    Write-Output 'PASS: Invoke-Expression keeps installer functions, variables and preferences private'
} finally {
    Remove-Item -LiteralPath $env:REITERATE_INSTALL_DIR -Recurse -Force -ErrorAction SilentlyContinue
}
