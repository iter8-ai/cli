# Installs the Reiterate CLI from the latest public release.
#   irm https://raw.githubusercontent.com/iter8-ai/cli/main/install.ps1 | iex
# Settings: REITERATE_INSTALL_DIR (default $env:LOCALAPPDATA\Programs\reiterate), REITERATE_VERSION (default latest)
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
    param([string]$BinaryPath, [string]$ChecksumsPath, [string]$FileName = (Split-Path -Leaf $BinaryPath))

    $file = $FileName
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

& {
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'
    $architecture = Get-ReiterateArchitecture
    $file = "reiterate-windows-$architecture.exe"
    $dir = $env:REITERATE_INSTALL_DIR
    if (-not $dir) {
        $dir = Join-Path $env:LOCALAPPDATA 'Programs\reiterate'
    }
    $dir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($dir)
    $version = $env:REITERATE_VERSION
    if (-not $version -or $version -eq 'latest') {
        $base = 'https://github.com/iter8-ai/cli/releases/latest/download'
    } else {
        $base = 'https://github.com/iter8-ai/cli/releases/download/v' + $version.TrimStart('v')
    }

    $downloadOptions = @{ UseBasicParsing = $true }
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        $downloadOptions.SslProtocol = 'Tls12'
    }
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ([IO.Path]::GetRandomFileName())
    New-Item -ItemType Directory -Path $tmp | Out-Null
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $binary = Join-Path $dir ('.reiterate-install-' + [Guid]::NewGuid().ToString('N') + '.exe')
    $securityProtocol = [Net.ServicePointManager]::SecurityProtocol
    try {
        [Net.ServicePointManager]::SecurityProtocol = $securityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $checksums = Join-Path $tmp 'checksums.txt'
        Invoke-WebRequest -Uri "$base/$file" -OutFile $binary @downloadOptions
        Invoke-WebRequest -Uri "$base/checksums.txt" -OutFile $checksums @downloadOptions
        Assert-ReiterateChecksum -BinaryPath $binary -ChecksumsPath $checksums -FileName $file

        $target = Join-Path $dir 'reiterate.exe'
        $old = $null
        if (Test-Path -LiteralPath $target) {
            $old = "$target.old"
            if (Test-Path -LiteralPath $old) {
                try {
                    Remove-Item -LiteralPath $old -Force
                } catch {
                    $old = "$target.$([Guid]::NewGuid().ToString('N')).old"
                }
            }
            # Windows can rename a running executable even when it cannot overwrite it.
            Rename-Item -LiteralPath $target -NewName (Split-Path -Leaf $old)
        }
        try {
            Move-Item -LiteralPath $binary -Destination $target
        } catch {
            if ($old -and (Test-Path -LiteralPath $old) -and -not (Test-Path -LiteralPath $target)) {
                Rename-Item -LiteralPath $old -NewName 'reiterate.exe'
            }
            throw
        }

        $environmentKey = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Environment')
        try {
            [string]$userPath = $environmentKey.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            if (@($userPath -split ';' | ForEach-Object { [Environment]::ExpandEnvironmentVariables($_).Trim().TrimEnd('\') }) -notcontains $dir.TrimEnd('\')) {
                $environmentKey.SetValue('Path', ($userPath.TrimEnd(';') + ';' + $dir).TrimStart(';'), [Microsoft.Win32.RegistryValueKind]::ExpandString)
                if (-not ('Reiterate.InstallerEnvironment' -as [type])) {
                    Add-Type -Namespace Reiterate -Name InstallerEnvironment -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
public static extern System.IntPtr SendMessageTimeout(System.IntPtr hWnd, uint msg, System.UIntPtr wParam, string lParam, uint flags, uint timeout, out System.UIntPtr result);
'@
                }
                $broadcastResult = [UIntPtr]::Zero
                [void][Reiterate.InstallerEnvironment]::SendMessageTimeout([IntPtr]0xffff, 0x1a, [UIntPtr]::Zero, 'Environment', 2, 5000, [ref]$broadcastResult)
            }
        } finally {
            $environmentKey.Dispose()
        }
        [string]$sessionPath = $env:Path
        if (@($sessionPath -split ';' | ForEach-Object { [Environment]::ExpandEnvironmentVariables($_).Trim().TrimEnd('\') }) -notcontains $dir.TrimEnd('\')) {
            $env:Path = ($sessionPath.TrimEnd(';') + ';' + $dir).TrimStart(';')
        }

        $installedVersion = & $target version
        if ($LASTEXITCODE -ne 0) {
            throw "reiterate: installed executable could not report its version (exit $LASTEXITCODE)"
        }
        Write-Output "Installed $installedVersion to $target"
        Write-Output 'Next:  reiterate login'
    } finally {
        [Net.ServicePointManager]::SecurityProtocol = $securityProtocol
        if (Test-Path -LiteralPath $binary) {
            Remove-Item -LiteralPath $binary -Force
        }
        Remove-Item -LiteralPath $tmp -Recurse -Force
    }
}
