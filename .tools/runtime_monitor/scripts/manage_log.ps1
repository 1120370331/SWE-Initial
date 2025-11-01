$ErrorActionPreference = 'Stop'

function Show-Usage {
@'
用法：manage_log.cmd --service <name> [选项]

操作模式：
  --clear                 启用清理模式
  --zip <archive>         启用归档模式（zip 文件路径）

常用选项：
  --service, -s <name>    目标服务名，可多次传入
  --before, -b <selector> 清理早于指定日期的日志（YYYY-MM-DD / today / dN / d-<N>）
  --using, -u             清理时包含当前最新日志
  --max-size, -m <size>   仅处理大于指定体积的文件（示例：30KB、100MB）
  --keep-latest, -k <n>   每个服务至少保留的最新日志数量（默认 1）
  --from <date>           归档起始日期（默认 d7）
  --to <date>             归档结束日期（默认 today）
  --append                归档时追加写入已存在 zip
  --dry-run               仅输出计划操作，不执行删除/写入
  --help, -h              显示帮助
  --version               显示版本号
'@
}

function Write-ErrorAndExit {
    param([string]$Message)
    [Console]::Error.WriteLine($Message)
    exit 1
}

function Write-Warn {
    param([string]$Message)
    [Console]::Error.WriteLine("提示：$Message")
}

function Get-LogsRoot {
    param(
        [string]$RuntimeRoot,
        [string]$ProjectRoot
    )
    if ($env:RAPID_LOGS_ROOT -and $env:RAPID_LOGS_ROOT.Trim() -ne '') {
        if (Test-Path -LiteralPath $env:RAPID_LOGS_ROOT) {
            return (Resolve-Path -LiteralPath $env:RAPID_LOGS_ROOT).Path
        }
        return $env:RAPID_LOGS_ROOT
    }
    $default = Join-Path -Path $RuntimeRoot -ChildPath 'logs'
    if (Test-Path -LiteralPath $default) {
        return (Resolve-Path -LiteralPath $default).Path
    }
    $fallback = Join-Path -Path $ProjectRoot -ChildPath 'logs'
    if (Test-Path -LiteralPath $fallback) {
        return (Resolve-Path -LiteralPath $fallback).Path
    }
    return $default
}

function Convert-DateSelector {
    param([string]$Selector)
    if ([string]::IsNullOrWhiteSpace($Selector) -or $Selector -eq 'today') {
        return (Get-Date).ToString('yyyy-MM-dd')
    }
    if ($Selector -eq 'yesterday') {
        return (Get-Date).AddDays(-1).ToString('yyyy-MM-dd')
    }
    if ($Selector -match '^d-?([0-9]+)$') {
        $days = [int]$Matches[1]
        return (Get-Date).AddDays(-$days).ToString('yyyy-MM-dd')
    }
    if ($Selector -match '^\d{4}-\d{2}-\d{2}$') {
        return $Selector
    }
    Write-ErrorAndExit "无法解析日期参数：$Selector"
}

function Parse-Size {
    param([string]$Text)
    if ($Text -match '^([0-9]+)([KkMmGgTt]?)[Bb]$') {
        $number = [int]$Matches[1]
        $unit = $Matches[2].ToUpperInvariant()
        switch ($unit) {
            '' { return $number }
            'K' { return $number * 1KB }
            'M' { return $number * 1MB }
            'G' { return $number * 1GB }
            'T' { return [int64]$number * (1TB) }
            default { Write-ErrorAndExit "未知体积单位：$unit" }
        }
    }
    Write-ErrorAndExit "体积阈值无法解析：$Text（示例：30KB、100MB）"
}

function Human-Size {
    param([int64]$Bytes)
    $units = @('B','KB','MB','GB','TB')
    $value = [double]$Bytes
    $idx = 0
    while ($value -ge 1024 -and $idx -lt $units.Length - 1) {
        $value = $value / 1024
        $idx++
    }
    if ($idx -eq 0) {
        return "{0:0}B" -f [math]::Round($value)
    }
    return "{0:0.0}{1}" -f $value, $units[$idx]
}

function Get-Services {
    param([string]$LogsRoot)
    if (-not (Test-Path -LiteralPath $LogsRoot)) { return @() }
    Get-ChildItem -LiteralPath $LogsRoot -Directory | Where-Object { $_.Name -notlike '.*' } | Select-Object -ExpandProperty Name | Sort-Object
}

function Get-Candidates {
    param([string]$Dir)
    if (-not (Test-Path -LiteralPath $Dir)) { return @() }
    Get-ChildItem -LiteralPath $Dir -File | Where-Object { $_.Name -ne 'index.json' } | Sort-Object -Property LastWriteTime -Descending
}

function Get-DateToken {
    param([System.IO.FileInfo]$Item)
    if ($Item.Name -match '\d{4}-\d{2}-\d{2}') {
        return $Matches[0]
    }
    return $Item.LastWriteTime.ToString('yyyy-MM-dd')
}

function Compare-DateToken {
    param([string]$Left, [string]$Right)
    return [string]::Compare($Left.Replace('-',''), $Right.Replace('-',''))
}

# -------- argument parsing --------

$Services = New-Object System.Collections.Generic.List[string]
$ClearMode = $false
$ArchiveTarget = $null
$BeforeSelector = $null
$IncludeLatest = $false
$MaxSizeText = $null
$KeepLatest = 1
$RangeFrom = 'd7'
$RangeTo = 'today'
$Append = $false
$DryRun = $false

$i = 0
while ($i -lt $args.Length) {
    $token = $args[$i]
    switch ($token) {
        '--service' { $i++; if ($i -ge $args.Length) { Write-ErrorAndExit '--service 需要参数' }; $Services.Add($args[$i]) }
        '-s'        { $i++; if ($i -ge $args.Length) { Write-ErrorAndExit '-s 需要参数' }; $Services.Add($args[$i]) }
        '--clear'   { $ClearMode = $true }
        '--zip'     { $i++; if ($i -ge $args.Length) { Write-ErrorAndExit '--zip 需要参数' }; $ArchiveTarget = $args[$i] }
        '--before'  { $i++; if ($i -ge $args.Length) { Write-ErrorAndExit '--before 需要参数' }; $BeforeSelector = $args[$i] }
        '-b'        { $i++; if ($i -ge $args.Length) { Write-ErrorAndExit '-b 需要参数' }; $BeforeSelector = $args[$i] }
        '--using'   { $IncludeLatest = $true }
        '-u'        { $IncludeLatest = $true }
        '--max-size'{ $i++; if ($i -ge $args.Length) { Write-ErrorAndExit '--max-size 需要参数' }; $MaxSizeText = $args[$i] }
        '-m'        { $i++; if ($i -ge $args.Length) { Write-ErrorAndExit '-m 需要参数' }; $MaxSizeText = $args[$i] }
        '--keep-latest' { $i++; if ($i -ge $args.Length) { Write-ErrorAndExit '--keep-latest 需要参数' }; $KeepLatest = [int]$args[$i] }
        '-k'           { $i++; if ($i -ge $args.Length) { Write-ErrorAndExit '-k 需要参数' }; $KeepLatest = [int]$args[$i] }
        '--from'    { $i++; if ($i -ge $args.Length) { Write-ErrorAndExit '--from 需要参数' }; $RangeFrom = $args[$i] }
        '--to'      { $i++; if ($i -ge $args.Length) { Write-ErrorAndExit '--to 需要参数' }; $RangeTo = $args[$i] }
        '--append'  { $Append = $true }
        '--dry-run' { $DryRun = $true }
        '--help'    { Show-Usage; exit 0 }
        '-h'        { Show-Usage; exit 0 }
        '--version' { Write-Output 'manage_log.cmd 0.1.0'; exit 0 }
        default     { Write-ErrorAndExit "未知参数：$token" }
    }
    $i++
}

if ($Services.Count -eq 0) {
    Show-Usage
    Write-ErrorAndExit '必须至少指定一个 --service'
}

if (-not $ClearMode -and -not $ArchiveTarget) {
    Write-ErrorAndExit '请至少指定 --clear 或 --zip 之一'
}

if ($KeepLatest -lt 0) {
    Write-ErrorAndExit '--keep-latest 需为非负整数'
}

$SizeThreshold = $null
if ($MaxSizeText) {
    $SizeThreshold = Parse-Size -Text $MaxSizeText
}

$BeforeDate = $null
if ($BeforeSelector) {
    $BeforeDate = Convert-DateSelector -Selector $BeforeSelector
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$runtimeDir = Split-Path -Parent $scriptDir
$toolsDir = Split-Path -Parent $runtimeDir
$projectRoot = Split-Path -Parent $toolsDir
$logsRoot = Get-LogsRoot -RuntimeRoot $runtimeDir -ProjectRoot $projectRoot

$serviceDirs = @{}
foreach ($svc in $Services) {
    $dir = Join-Path -Path $logsRoot -ChildPath $svc
    if (-not (Test-Path -LiteralPath $dir)) {
        $available = (Get-Services -LogsRoot $logsRoot) -join ', '
        if (-not $available) { $available = '无' }
        Write-ErrorAndExit "服务 `$svc` 缺少日志目录：$dir。当前可用服务：$available"
    }
    $serviceDirs[$svc] = $dir
}

$ArchivePath = $null
$StartDate = $null
$EndDate = $null
if ($ArchiveTarget) {
    $StartDate = Convert-DateSelector -Selector $RangeFrom
    $EndDate = Convert-DateSelector -Selector $RangeTo
    if ($env:RAPID_DEBUG -eq '1') {
        $cmp = Compare-DateToken $StartDate $EndDate
        Write-Host ("DEBUG Start={0} (len={1}) End={2} (len={3}) Compare={4}" -f $StartDate, $StartDate.Length, $EndDate, $EndDate.Length, $cmp)
    }
    if ((Compare-DateToken $StartDate $EndDate) -gt 0) {
        Write-Warn '归档日期区间已自动对调。'
        $tmp = $StartDate
        $StartDate = $EndDate
        $EndDate = $tmp
    }
    if ([System.IO.Path]::IsPathRooted($ArchiveTarget)) {
        $ArchivePath = $ArchiveTarget
    } elseif ([string]::IsNullOrEmpty([System.IO.Path]::GetDirectoryName($ArchiveTarget))) {
        $ArchivePath = Join-Path -Path $logsRoot -ChildPath (Join-Path -Path 'archive' -ChildPath $ArchiveTarget)
    } else {
        $ArchivePath = Join-Path -Path $projectRoot -ChildPath $ArchiveTarget
    }
    if ([string]::IsNullOrEmpty([System.IO.Path]::GetExtension($ArchivePath))) {
        $ArchivePath = "$ArchivePath.zip"
    }
}

function Select-Clear {
    param(
        [System.Collections.Generic.List[System.IO.FileInfo]]$Files,
        [string]$Service,
        [string]$BeforeDate,
        [Nullable[int64]]$SizeThreshold,
        [int]$KeepLatest,
        [bool]$IncludeLatest
    )
    $selection = New-Object System.Collections.Generic.List[System.IO.FileInfo]
    $protect = $KeepLatest
    if (-not $IncludeLatest -and $protect -lt 1) { $protect = 1 }
    for ($idx = 0; $idx -lt $Files.Count; $idx++) {
        $file = $Files[$idx]
        if ($idx -lt $protect) { continue }
        $token = Get-DateToken -Item $file
        if ($BeforeDate -and ((Compare-DateToken $token $BeforeDate) -ge 0)) { continue }
        if ($SizeThreshold -and $file.Length -lt $SizeThreshold) { continue }
        $selection.Add($file)
    }
    return $selection
}

function Collect-ZipTargets {
    param(
        [System.Collections.Generic.List[System.IO.FileInfo]]$Files,
        [string]$StartDate,
        [string]$EndDate,
        [string]$Service
    )
    $targets = New-Object System.Collections.Generic.List[object]
    foreach ($file in $Files) {
        $token = Get-DateToken -Item $file
        if ((Compare-DateToken $token $StartDate) -lt 0) { continue }
        if ((Compare-DateToken $token $EndDate) -gt 0) { continue }
        $targets.Add([PSCustomObject]@{
            Service = $Service
            Path    = $file.FullName
            Name    = $file.Name
        })
    }
    return $targets
}

function Ensure-ZipAssembly {
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
}

$zipEntries = New-Object System.Collections.Generic.List[object]

if ($ArchivePath) {
    Ensure-ZipAssembly
    foreach ($svc in $Services) {
        $dir = $serviceDirs[$svc]
        $files = Get-Candidates -Dir $dir
        $list = New-Object System.Collections.Generic.List[System.IO.FileInfo]
        foreach ($f in $files) { $list.Add($f) }
        $targets = Collect-ZipTargets -Files $list -StartDate $StartDate -EndDate $EndDate -Service $svc
        foreach ($item in $targets) { $zipEntries.Add($item) }
    }

    if ($zipEntries.Count -eq 0) {
        Write-Warn '归档条件未匹配任何文件。'
    } else {
        foreach ($entry in $zipEntries) {
            Write-Output ("[zip] {0} <= {1}/{2}" -f (Split-Path -Leaf $ArchivePath), $entry.Service, $entry.Name)
        }
        if (-not $DryRun) {
            $archiveDir = Split-Path -Parent $ArchivePath
            if ($archiveDir -and -not (Test-Path -LiteralPath $archiveDir)) {
                New-Item -ItemType Directory -Path $archiveDir -Force | Out-Null
            }
            if (-not $Append -and (Test-Path -LiteralPath $ArchivePath)) {
                Remove-Item -LiteralPath $ArchivePath -Force
            }
            $mode = if ($Append -and (Test-Path -LiteralPath $ArchivePath)) { 'Update' } elseif ($Append) { 'Create' } else { 'Create' }
            $zip = [System.IO.Compression.ZipFile]::Open($ArchivePath, $mode)
            try {
                foreach ($entry in $zipEntries) {
                    $entryName = "{0}/{1}" -f $entry.Service, $entry.Name
                    if ($mode -ne 'Create') {
                        $existing = $zip.GetEntry($entryName)
                        if ($existing) { $existing.Delete() }
                    }
                    [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                        $zip,
                        $entry.Path,
                        $entryName,
                        [System.IO.Compression.CompressionLevel]::Optimal
                    ) | Out-Null
                }
            } finally {
                $zip.Dispose()
            }
        }
    }
}

$totalRemoved = 0
$totalBytes = [int64]0

if ($ClearMode) {
    foreach ($svc in $Services) {
        $dir = $serviceDirs[$svc]
        $files = Get-Candidates -Dir $dir
        $list = New-Object System.Collections.Generic.List[System.IO.FileInfo]
        foreach ($f in $files) { $list.Add($f) }
        $selection = Select-Clear -Files $list -Service $svc -BeforeDate $BeforeDate -SizeThreshold $SizeThreshold -KeepLatest $KeepLatest -IncludeLatest $IncludeLatest
        foreach ($file in $selection) {
            $size = $file.Length
            Write-Output ("[clear] {0} -> {1} ({2})" -f $svc, $file.Name, (Human-Size $size))
            if (-not $DryRun) {
                Remove-Item -LiteralPath $file.FullName -Force
            }
            $totalRemoved++
            $totalBytes += $size
        }
    }
    if ($totalRemoved -eq 0) {
        Write-Warn '没有文件符合清理条件。'
    } else {
        Write-Output ("清理完成，共删除 {0} 个文件，释放 {1}。" -f $totalRemoved, (Human-Size $totalBytes))
    }
}

exit 0
