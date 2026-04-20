[CmdletBinding()]
param(
    [switch]$ShowTopFiles,
    [ValidateRange(1, 100)]
    [int]$TopFileCount = 10,
    [string]$ExportJsonPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Format-Bytes {
    param(
        [Parameter(Mandatory = $true)]
        [double]$Bytes
    )

    $units = @("B", "KB", "MB", "GB", "TB")
    $value = $Bytes
    $unitIndex = 0

    while ($value -ge 1024 -and $unitIndex -lt ($units.Count - 1)) {
        $value = $value / 1024
        $unitIndex++
    }

    return ("{0:N2} {1}" -f $value, $units[$unitIndex])
}

function New-ScanTarget {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Category
    )

    [PSCustomObject]@{
        Name     = $Name
        Path     = $Path
        Category = $Category
    }
}

function Get-FirefoxCacheTargets {
    $profileRoot = Join-Path $env:LOCALAPPDATA "Mozilla\Firefox\Profiles"
    if (-not (Test-Path -LiteralPath $profileRoot)) {
        return @()
    }

    $targets = @()
    $profiles = Get-ChildItem -LiteralPath $profileRoot -Directory -ErrorAction SilentlyContinue
    foreach ($profile in $profiles) {
        $cachePath = Join-Path $profile.FullName "cache2"
        $targets += New-ScanTarget -Name ("Firefox cache ({0})" -f $profile.Name) -Path $cachePath -Category "Browser Cache"
    }

    return $targets
}

function Get-DirectoryStats {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Target,
        [Parameter(Mandatory = $true)]
        [int]$TopCount
    )

    try {
        $pathExists = Test-Path -LiteralPath $Target.Path -ErrorAction Stop
    }
    catch {
        return [PSCustomObject]@{
            Name           = $Target.Name
            Category       = $Target.Category
            Path           = $Target.Path
            Exists         = $false
            FileCount      = 0
            DirectoryCount = 0
            SizeBytes      = 0
            Size           = Format-Bytes -Bytes 0
            Status         = ("Access denied: {0}" -f $_.Exception.Message)
            LargestFiles   = @()
        }
    }

    if (-not $pathExists) {
        return [PSCustomObject]@{
            Name           = $Target.Name
            Category       = $Target.Category
            Path           = $Target.Path
            Exists         = $false
            FileCount      = 0
            DirectoryCount = 0
            SizeBytes      = 0
            Size           = Format-Bytes -Bytes 0
            Status         = "Missing"
            LargestFiles   = @()
        }
    }

    try {
        $files = @(Get-ChildItem -LiteralPath $Target.Path -Recurse -Force -File -ErrorAction SilentlyContinue)
        $directories = @(Get-ChildItem -LiteralPath $Target.Path -Recurse -Force -Directory -ErrorAction SilentlyContinue)
        if ($files.Count -eq 0) {
            $measuredSize = 0
        }
        else {
            $measuredSize = ($files | Measure-Object -Property Length -Sum | Select-Object -ExpandProperty Sum)
        }

        $largestFiles = @(
            $files |
                Sort-Object -Property Length -Descending |
                Select-Object -First $TopCount -Property `
                    FullName,
                    @{ Name = "SizeBytes"; Expression = { $_.Length } },
                    @{ Name = "Size"; Expression = { Format-Bytes -Bytes $_.Length } }
        )

        return [PSCustomObject]@{
            Name           = $Target.Name
            Category       = $Target.Category
            Path           = $Target.Path
            Exists         = $true
            FileCount      = $files.Count
            DirectoryCount = $directories.Count
            SizeBytes      = [double]$measuredSize
            Size           = Format-Bytes -Bytes $measuredSize
            Status         = "OK"
            LargestFiles   = $largestFiles
        }
    }
    catch {
        return [PSCustomObject]@{
            Name           = $Target.Name
            Category       = $Target.Category
            Path           = $Target.Path
            Exists         = $true
            FileCount      = 0
            DirectoryCount = 0
            SizeBytes      = 0
            Size           = Format-Bytes -Bytes 0
            Status         = ("Error: {0}" -f $_.Exception.Message)
            LargestFiles   = @()
        }
    }
}

$targets = @(
    New-ScanTarget -Name "User temp" -Path $env:TEMP -Category "Temp Files"
    New-ScanTarget -Name "Windows temp" -Path (Join-Path $env:WINDIR "Temp") -Category "Temp Files"
    New-ScanTarget -Name "Windows update cache" -Path (Join-Path $env:WINDIR "SoftwareDistribution\Download") -Category "System Cache"
    New-ScanTarget -Name "Delivery optimization cache" -Path (Join-Path $env:ProgramData "Microsoft\Windows\DeliveryOptimization\Cache") -Category "System Cache"
    New-ScanTarget -Name "Windows error reporting" -Path (Join-Path $env:ProgramData "Microsoft\Windows\WER") -Category "Diagnostics"
    New-ScanTarget -Name "Thumbnail cache" -Path (Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Explorer") -Category "Windows Cache"
    New-ScanTarget -Name "Chrome cache" -Path (Join-Path $env:LOCALAPPDATA "Google\Chrome\User Data\Default\Cache\Cache_Data") -Category "Browser Cache"
    New-ScanTarget -Name "Edge cache" -Path (Join-Path $env:LOCALAPPDATA "Microsoft\Edge\User Data\Default\Cache\Cache_Data") -Category "Browser Cache"
)

$targets += Get-FirefoxCacheTargets

$report = @(
    foreach ($target in $targets) {
        Get-DirectoryStats -Target $target -TopCount $TopFileCount
    }
)

$sortedReport = $report | Sort-Object -Property SizeBytes -Descending
$totalBytes = if ($sortedReport.Count -eq 0) {
    0
}
else {
    $sortedReport | Measure-Object -Property SizeBytes -Sum | Select-Object -ExpandProperty Sum
}

Write-Host ""
Write-Host "Windows Junk File Scan Report" -ForegroundColor Cyan
Write-Host "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host ""

$sortedReport |
    Select-Object Name, Category, Status, FileCount, DirectoryCount, Size |
    Format-Table -AutoSize

Write-Host ""
Write-Host ("Estimated total size: {0}" -f (Format-Bytes -Bytes $totalBytes)) -ForegroundColor Yellow

if ($ShowTopFiles) {
    foreach ($entry in $sortedReport) {
        if ($entry.LargestFiles.Count -eq 0) {
            continue
        }

        Write-Host ""
        Write-Host ("Top files for {0}" -f $entry.Name) -ForegroundColor Green
        $entry.LargestFiles | Format-Table -AutoSize
    }
}

if ($ExportJsonPath) {
    $exportPayload = [PSCustomObject]@{
        GeneratedAt        = (Get-Date).ToString("o")
        TotalSizeBytes     = [double]$totalBytes
        TotalSizeFormatted = Format-Bytes -Bytes $totalBytes
        Items              = $sortedReport
    }

    $exportDirectory = Split-Path -Path $ExportJsonPath -Parent
    if ($exportDirectory -and -not (Test-Path -LiteralPath $exportDirectory)) {
        New-Item -ItemType Directory -Path $exportDirectory -Force | Out-Null
    }

    $exportPayload | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $ExportJsonPath -Encoding UTF8
    Write-Host ""
    Write-Host ("JSON report written to: {0}" -f $ExportJsonPath) -ForegroundColor Cyan
}
