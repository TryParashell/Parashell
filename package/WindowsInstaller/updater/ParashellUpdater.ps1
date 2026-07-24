[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Check", "Download")]
    [string]$Mode,
    [string]$CurrentVersion,
    [string]$FeedUrl,
    [Parameter(Mandatory = $true)]
    [string]$ManifestPath,
    [string]$BootstrapPath,
    [int]$ParentProcessId = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$UpdaterRoot = Join-Path $env:ProgramData "Parashell\Updater"
$UpdateRoot = Join-Path $env:ProgramData "Parashell\Updates"
$StatePath = Join-Path $UpdateRoot "state.json"
$HostControlUrl = "https://hostcontrol.parashell.cloud/a.json"

function Test-HasProperty {
    param(
        [object]$Object,
        [Parameter(Mandatory = $true)][string]$Name
    )
    return ($null -ne $Object) -and ($Object.PSObject.Properties.Name -contains $Name)
}

function Get-SkipCodeSignCheck {
    try {
        $hostControlUri = Assert-HttpsUri -Value $HostControlUrl -AllowedHosts @("hostcontrol.parashell.cloud") -ExpectedName "a.json"
        $document = Invoke-WithRetry -Attempts 2 -Operation {
            Invoke-RestMethod -UseBasicParsing -TimeoutSec 5 -Uri $hostControlUri.AbsoluteUri -Method Get -Headers @{ Accept = "application/json" }
        }
        if (-not (Test-HasProperty $document "schema") -or [int]$document.schema -ne 1) {
            return $false
        }
        if (-not (Test-HasProperty $document "services")) {
            return $false
        }
        $services = $document.services
        if (-not (Test-HasProperty $services "drp")) {
            return $false
        }
        $dropsite = $services.drp
        if (-not (Test-HasProperty $dropsite "extra_data")) {
            return $false
        }
        $extra = $dropsite.extra_data
        if (-not (Test-HasProperty $extra "skip_code_sign_check")) {
            return $false
        }
        $value = $extra.skip_code_sign_check
        return ($value -is [bool]) -and $value
    }
    catch {
        return $false
    }
}

function Invoke-WithRetry {
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$Operation,
        [int]$Attempts = 4
    )

    $lastError = $null
    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        try {
            return & $Operation
        }
        catch {
            $lastError = $_
            if ($attempt -eq $Attempts) {
                break
            }
            Start-Sleep -Seconds ([Math]::Pow(2, $attempt - 1))
        }
    }
    throw $lastError
}

function Assert-HttpsUri {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value,
        [Parameter(Mandatory = $true)]
        [string[]]$AllowedHosts,
        [string]$ExpectedName = ""
    )
    $uri = $null
    if (-not [Uri]::TryCreate($Value, [UriKind]::Absolute, [ref]$uri)) {
        throw "The update URL is invalid."
    }
    if ($uri.Scheme -ne "https" -or $uri.UserInfo -or $uri.Query -or $uri.Fragment -or $AllowedHosts -notcontains $uri.DnsSafeHost) {
        throw "The update URL is not trusted."
    }
    if ($ExpectedName -and [Uri]::UnescapeDataString([IO.Path]::GetFileName($uri.AbsolutePath)) -cne $ExpectedName) {
        throw "The update URL does not match the expected asset."
    }
    return $uri
}

function Assert-ReleaseIdentity {
    param(
        [Parameter(Mandatory = $true)][string]$Version,
        [Parameter(Mandatory = $true)][int]$InstallerBuild,
        [Parameter(Mandatory = $true)][string]$AssetName
    )

    if ($Version -notmatch '^\d+\.\d+\.\d+$' -or $InstallerBuild -le 0) {
        throw "The update version is invalid."
    }
    $match = [Regex]::Match(
        $AssetName,
        '^Parashell_(\d+\.\d+\.\d+)-Windows-(?:x86_64|amd64)-installer(?:-(\d+))?\.exe$',
        [Text.RegularExpressions.RegexOptions]::IgnoreCase
    )
    if (-not $match.Success -or $match.Groups[1].Value -ne $Version) {
        throw "The update filename is invalid."
    }
    $assetBuild = if ($match.Groups[2].Success) { [int]$match.Groups[2].Value } else { 1 }
    if ($assetBuild -ne $InstallerBuild) {
        throw "The update installer build is invalid."
    }
}

function Write-AtomicJson {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [object]$Value
    )

    $directory = Split-Path -Parent $Path
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    $temporaryPath = "$Path.$([Guid]::NewGuid().ToString('N')).tmp"
    [IO.File]::WriteAllText(
        $temporaryPath,
        ($Value | ConvertTo-Json -Depth 6 -Compress),
        $Utf8NoBom
    )
    Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
}

function Read-Manifest {
    $manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-ReleaseIdentity -Version $manifest.version -InstallerBuild ([int]$manifest.installer_build) -AssetName $manifest.asset_name
    $downloadUri = Assert-HttpsUri -Value $manifest.download_url -AllowedHosts @("github.com") -ExpectedName $manifest.asset_name
    if ([int64]$manifest.asset_size -le 0) {
        throw "The update size is invalid."
    }
    if ($manifest.sha256 -notmatch '^[a-fA-F0-9]{64}$') {
        throw "The update checksum is invalid."
    }
    $createdUtc = [DateTime]::Parse(
        $manifest.created_utc,
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::RoundtripKind
    ).ToUniversalTime()
    if ($createdUtc -lt [DateTime]::UtcNow.AddHours(-24) -or $createdUtc -gt [DateTime]::UtcNow.AddMinutes(5)) {
        throw "The update manifest has expired."
    }
    $skipCodeSignCheck = (Test-HasProperty $manifest "skip_code_sign_check") -and ($manifest.skip_code_sign_check -is [bool]) -and $manifest.skip_code_sign_check
    if (-not $skipCodeSignCheck -and [string]::IsNullOrWhiteSpace($manifest.signer_subject)) {
        throw "The update signing identity is invalid."
    }
    return [pscustomobject]@{
        Manifest = $manifest
        DownloadUri = $downloadUri
        SkipCodeSignCheck = $skipCodeSignCheck
    }
}

function Set-PrivateDirectoryAcl {
    param([Parameter(Mandatory = $true)][string]$Path)

    [IO.Directory]::CreateDirectory($Path) | Out-Null
    $security = New-Object Security.AccessControl.DirectorySecurity
    $security.SetAccessRuleProtection($true, $false)
    $identities = @(
        [Security.Principal.WindowsIdentity]::GetCurrent().User,
        (New-Object Security.Principal.SecurityIdentifier("S-1-5-18")),
        (New-Object Security.Principal.SecurityIdentifier("S-1-5-32-544"))
    )
    foreach ($identity in $identities) {
        $rule = New-Object Security.AccessControl.FileSystemAccessRule(
            $identity,
            [Security.AccessControl.FileSystemRights]::FullControl,
            [Security.AccessControl.InheritanceFlags]"ContainerInherit, ObjectInherit",
            [Security.AccessControl.PropagationFlags]::None,
            [Security.AccessControl.AccessControlType]::Allow
        )
        $security.AddAccessRule($rule)
    }
    Set-Acl -LiteralPath $Path -AclObject $security
}

function Write-State {
    param(
        [Parameter(Mandatory = $true)][string]$Status,
        [object]$Manifest,
        [int64]$BytesTransferred = 0,
        [int64]$BytesTotal = 0,
        [string]$ErrorMessage = ""
    )

    Write-AtomicJson -Path $StatePath -Value ([ordered]@{
        status = $Status
        version = if ($null -ne $Manifest) { $Manifest.version } else { "" }
        bytes_transferred = $BytesTransferred
        bytes_total = $BytesTotal
        error = $ErrorMessage
        updated_utc = [DateTime]::UtcNow.ToString("o")
    })
}

function Invoke-Check {
    if ($CurrentVersion -notmatch '^\d+\.\d+\.\d+\.\d+$') {
        throw "The installed version is invalid."
    }
    $feedUri = Assert-HttpsUri -Value $FeedUrl -AllowedHosts @("api8.parashell.cloud")
    if (-not (Test-Path -LiteralPath $BootstrapPath -PathType Leaf)) {
        throw "The bootstrap installer is unavailable."
    }
    $skipCodeSignCheck = Get-SkipCodeSignCheck
    $signerSubject = ""
    if (-not $skipCodeSignCheck) {
        $bootstrapSignature = Get-AuthenticodeSignature -FilePath $BootstrapPath
        if ($bootstrapSignature.Status -ne [Management.Automation.SignatureStatus]::Valid -or $null -eq $bootstrapSignature.SignerCertificate) {
            throw "The bootstrap installer signature is invalid."
        }
        $signerSubject = $bootstrapSignature.SignerCertificate.Subject
    }
    Set-PrivateDirectoryAcl -Path $UpdaterRoot
    $persistentScript = Join-Path $UpdaterRoot "ParashellUpdater.ps1"
    $temporaryScript = "$persistentScript.$([Guid]::NewGuid().ToString('N')).tmp"
    Copy-Item -LiteralPath $PSCommandPath -Destination $temporaryScript -Force
    if ((Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $temporaryScript -Algorithm SHA256).Hash) {
        Remove-Item -LiteralPath $temporaryScript -Force -ErrorAction SilentlyContinue
        throw "The updater controller could not be copied safely."
    }
    Move-Item -LiteralPath $temporaryScript -Destination $persistentScript -Force
    $requestUri = "{0}?current={1}" -f $feedUri.AbsoluteUri.TrimEnd('/'), [Uri]::EscapeDataString($CurrentVersion)
    $response = Invoke-WithRetry -Attempts 2 -Operation {
        Invoke-RestMethod -UseBasicParsing -TimeoutSec 5 -Uri $requestUri -Method Get
    }
    if (-not $response.update_available) {
        Remove-Item -LiteralPath $ManifestPath -Force -ErrorAction SilentlyContinue
        return
    }
    $latest = $response.latest
    Assert-ReleaseIdentity -Version ([string]$latest.version) -InstallerBuild ([int]$latest.installer_build) -AssetName ([string]$latest.asset_name)
    Assert-HttpsUri -Value $latest.download_url -AllowedHosts @("github.com") -ExpectedName $latest.asset_name | Out-Null
    $checksumName = [string]$latest.asset_name + "-SHA256.txt"
    $checksumUri = Assert-HttpsUri -Value $latest.checksum_url -AllowedHosts @("github.com") -ExpectedName $checksumName
    if ([int64]$latest.asset_size -le 0) {
        throw "The update feed returned an invalid size."
    }
    $checksumResponse = Invoke-WithRetry -Attempts 2 -Operation {
        Invoke-WebRequest -UseBasicParsing -TimeoutSec 5 -Uri $checksumUri.AbsoluteUri -Method Get
    }
    $escapedName = [Regex]::Escape([string]$latest.asset_name)
    $checksumMatch = [Regex]::Match(
        [string]$checksumResponse.Content,
        "(?im)^\s*([a-f0-9]{64})\s+\*?$escapedName\s*$"
    )
    if (-not $checksumMatch.Success) {
        throw "The release checksum is malformed or names a different file."
    }
    Write-AtomicJson -Path $ManifestPath -Value ([ordered]@{
        version = [string]$latest.version
        installer_build = [int]$latest.installer_build
        download_url = [string]$latest.download_url
        asset_name = [string]$latest.asset_name
        asset_size = [int64]$latest.asset_size
        sha256 = $checksumMatch.Groups[1].Value.ToLowerInvariant()
        signer_subject = $signerSubject
        skip_code_sign_check = $skipCodeSignCheck
        created_utc = [DateTime]::UtcNow.ToString("o")
    })
    [Console]::Out.WriteLine([string]$latest.version)
}

function Remove-StaleUpdates {
    if (-not (Test-Path -LiteralPath $UpdateRoot -PathType Container)) {
        return
    }
    $cutoff = [DateTime]::UtcNow.AddDays(-7)
    Get-ChildItem -LiteralPath $UpdateRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTimeUtc -lt $cutoff } |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}

function Get-UpdateJob {
    param([Parameter(Mandatory = $true)][string]$DisplayName)

    $jobs = @(Get-BitsTransfer -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq $DisplayName })
    if ($jobs.Count -gt 1) {
        $jobs | Select-Object -Skip 1 | Remove-BitsTransfer -Confirm:$false
    }
    if ($jobs.Count -eq 0) {
        return $null
    }
    return $jobs[0]
}

function Wait-ForBitsTransfer {
    param(
        [Parameter(Mandatory = $true)][object]$Job,
        [Parameter(Mandatory = $true)][object]$Manifest
    )

    while ($true) {
        $Job = Get-BitsTransfer -JobId $Job.JobId
        Write-State -Status ([string]$Job.JobState).ToLowerInvariant() -Manifest $Manifest -BytesTransferred $Job.BytesTransferred -BytesTotal $Job.BytesTotal
        switch ([string]$Job.JobState) {
            "Transferred" {
                Complete-BitsTransfer -BitsJob $Job
                return
            }
            "Error" {
                $message = if ($null -ne $Job.Error) { $Job.Error.Description } else { "BITS transfer failed." }
                Remove-BitsTransfer -BitsJob $Job -Confirm:$false
                throw $message
            }
            "Cancelled" {
                throw "The background update download was cancelled."
            }
            "Acknowledged" {
                return
            }
            "Suspended" {
                Resume-BitsTransfer -BitsJob $Job -Asynchronous | Out-Null
            }
        }
        Start-Sleep -Seconds 5
    }
}

function Invoke-Download {
    $loaded = Read-Manifest
    $manifest = $loaded.Manifest
    $skipCodeSignCheck = $loaded.SkipCodeSignCheck
    Set-PrivateDirectoryAcl -Path $UpdateRoot
    $mutex = New-Object Threading.Mutex($false, "Global\Parashell.Update.x86_64")
    $hasMutex = $false
    try {
        try {
            $hasMutex = $mutex.WaitOne(0)
        }
        catch [Threading.AbandonedMutexException] {
            $hasMutex = $true
        }
        if (-not $hasMutex) {
            return
        }
        Remove-StaleUpdates
        Import-Module BitsTransfer -ErrorAction Stop
        $stagingDirectory = Join-Path $UpdateRoot ("{0}-{1}" -f $manifest.version, $manifest.installer_build)
        Set-PrivateDirectoryAcl -Path $stagingDirectory
        $partialPath = Join-Path $stagingDirectory ($manifest.asset_name + ".partial")
        $installerPath = Join-Path $stagingDirectory $manifest.asset_name
        $jobName = "Parashell.Update.$($manifest.sha256)"
        @(Get-BitsTransfer -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -like "Parashell.Update.*" -and $_.DisplayName -ne $jobName }) |
            Remove-BitsTransfer -Confirm:$false -ErrorAction SilentlyContinue
        $job = Get-UpdateJob -DisplayName $jobName
        if ($null -eq $job -and (Test-Path -LiteralPath $partialPath -PathType Leaf)) {
            $partialFile = Get-Item -LiteralPath $partialPath
            $partialHash = if ($partialFile.Length -eq [int64]$manifest.asset_size) {
                (Get-FileHash -LiteralPath $partialPath -Algorithm SHA256).Hash
            }
            else {
                ""
            }
            if ($partialHash -ne $manifest.sha256) {
                Remove-Item -LiteralPath $partialPath -Force
            }
        }
        if ($null -eq $job -and -not (Test-Path -LiteralPath $partialPath -PathType Leaf)) {
            $bitsParameters = @{
                Source = $loaded.DownloadUri.AbsoluteUri
                Destination = $partialPath
                DisplayName = $jobName
                Description = "Parashell $($manifest.version) update"
                Priority = "Normal"
                RetryInterval = 60
                RetryTimeout = 3600
                Asynchronous = $true
            }
            $job = Start-BitsTransfer @bitsParameters
        }
        if ($null -ne $job) {
            Wait-ForBitsTransfer -Job $job -Manifest $manifest
        }
        if (-not (Test-Path -LiteralPath $partialPath -PathType Leaf)) {
            throw "The background update download did not produce an installer."
        }
        $file = Get-Item -LiteralPath $partialPath
        if ($file.Length -ne [int64]$manifest.asset_size) {
            throw "The downloaded installer size does not match the release manifest."
        }
        $actualHash = (Get-FileHash -LiteralPath $partialPath -Algorithm SHA256).Hash
        if ($actualHash -ne $manifest.sha256) {
            throw "The downloaded installer checksum does not match the release manifest."
        }
        if (-not $skipCodeSignCheck) {
            $signature = Get-AuthenticodeSignature -FilePath $partialPath
            if ($signature.Status -ne [Management.Automation.SignatureStatus]::Valid -or $null -eq $signature.SignerCertificate) {
                throw "The downloaded installer signature is invalid."
            }
            if ($signature.SignerCertificate.Subject -ne $manifest.signer_subject) {
                throw "The downloaded installer publisher does not match this installer."
            }
        }
        Move-Item -LiteralPath $partialPath -Destination $installerPath -Force
        if (-not $skipCodeSignCheck) {
            $finalSignature = Get-AuthenticodeSignature -FilePath $installerPath
            if ($finalSignature.Status -ne [Management.Automation.SignatureStatus]::Valid -or $finalSignature.SignerCertificate.Subject -ne $manifest.signer_subject) {
                throw "The staged installer failed final signature verification."
            }
        }
        Write-State -Status "ready" -Manifest $manifest -BytesTransferred $file.Length -BytesTotal $file.Length
        if ($ParentProcessId -gt 0) {
            Get-Process -Id $ParentProcessId -ErrorAction SilentlyContinue | Wait-Process -Timeout 120 -ErrorAction SilentlyContinue
        }
        $process = Start-Process -FilePath $installerPath -PassThru
        Write-State -Status "installing" -Manifest $manifest -BytesTransferred $file.Length -BytesTotal $file.Length
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) {
            throw "The updated installer exited with code $($process.ExitCode)."
        }
        Write-State -Status "complete" -Manifest $manifest -BytesTransferred $file.Length -BytesTotal $file.Length
        Remove-Item -LiteralPath $installerPath -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $ManifestPath -Force -ErrorAction SilentlyContinue
    }
    finally {
        if ($hasMutex) {
            $mutex.ReleaseMutex()
        }
        $mutex.Dispose()
    }
}

try {
    if ($Mode -eq "Check") {
        Invoke-Check
    }
    else {
        Invoke-Download
    }
}
catch {
    if ($Mode -eq "Download") {
        try {
            [IO.Directory]::CreateDirectory($UpdateRoot) | Out-Null
            Write-State -Status "failed" -Manifest $null -ErrorMessage $_.Exception.Message
            Add-Type -AssemblyName PresentationFramework
            [System.Windows.MessageBox]::Show(
                "Parashell could not install the downloaded update. $($_.Exception.Message)",
                "Parashell Update",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Error
            ) | Out-Null
        }
        catch {
            [Console]::Error.WriteLine($_.Exception.Message)
        }
    }
    exit 1
}