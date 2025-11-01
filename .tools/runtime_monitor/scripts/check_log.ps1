$ErrorActionPreference = 'Stop'

function Show-Usage {
    @'
用法：check_log.cmd --service <name> [选项]

必选：
  --service, -s <name>    服务名，映射到 logs\<service>\ 目录

可选：
  --date, -d <selector>   日期（YYYY-MM-DD / today / yesterday / d<N> / d-<N>），默认 today
  --tail, -t <n>          最末行窗口（10-500），与 --start/--end 同时指定时忽略，默认 20
  --start <line>          起始行（正整数），可与 --end 配合
  --end <line>            结束行（正整数），可与 --start 配合
  --keyword, -k <text>    关键词过滤，可多次传入，AND 逻辑
  --regex, -r <pattern>   正则过滤，与 --keyword 互斥（正则优先）
  --plain                 关闭彩色高亮
  --output <path>         将结果写入文件路径（自动创建目录）
  --force                 允许覆盖已存在的 --output 文件
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
        return (Resolve-Path -LiteralPath $env:RAPID_LOGS_ROOT).Path
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

function Get-Services {
    param([string]$LogsRoot)
    if (-not (Test-Path -LiteralPath $LogsRoot)) {
        return @()
    }
    Get-ChildItem -LiteralPath $LogsRoot -Directory | Where-Object { $_.Name -notlike '.*' } | Select-Object -ExpandProperty Name | Sort-Object
}

function Lookup-Index {
    param(
        [string]$ServiceDir,
        [string]$DateToken
    )
    $indexFile = Join-Path -Path $ServiceDir -ChildPath 'index.json'
    if (-not (Test-Path -LiteralPath $indexFile)) {
        return $null
    }
    try {
        $json = Get-Content -LiteralPath $indexFile -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        Write-ErrorAndExit "index.json 解析失败：$($_.Exception.Message)"
    }
    if ($json.PSObject.Properties.Name -contains $DateToken) {
        $candidate = $json.$DateToken
        if ($candidate) {
            return (Join-Path -Path $ServiceDir -ChildPath $candidate)
        }
    }
    return $null
}

function Collect-KnownDates {
    param([string]$ServiceDir)
    $dates = [System.Collections.Generic.HashSet[string]]::new()
    $indexFile = Join-Path -Path $ServiceDir -ChildPath 'index.json'
    if (Test-Path -LiteralPath $indexFile) {
        try {
            $json = Get-Content -LiteralPath $indexFile -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($name in $json.PSObject.Properties.Name) {
                $null = $dates.Add($name)
            }
        } catch {
            # ignore malformed json for date hints
        }
    }
    Get-ChildItem -LiteralPath $ServiceDir -File | ForEach-Object {
        if ($_.Name -match '\d{4}-\d{2}-\d{2}') {
            $null = $dates.Add($Matches[0])
        }
    }
    return $dates.ToArray() | Sort-Object
}

function Resolve-LogFile {
    param(
        [string]$ServiceDir,
        [string]$DateToken
    )
    $expected = Join-Path -Path $ServiceDir -ChildPath ("{0}.log" -f $DateToken)
    if (Test-Path -LiteralPath $expected) {
        return (Resolve-Path -LiteralPath $expected).Path
    }
    $mapped = Lookup-Index -ServiceDir $ServiceDir -DateToken $DateToken
    if ($mapped -and (Test-Path -LiteralPath $mapped)) {
        return (Resolve-Path -LiteralPath $mapped).Path
    }
    $matches = Get-ChildItem -LiteralPath $ServiceDir -File |
        Where-Object { $_.Name -like "*$DateToken*" } |
        Sort-Object -Property LastWriteTime -Descending
    if ($matches) {
        return (Resolve-Path -LiteralPath $matches[0].FullName).Path
    }
    return $null
}

function Compute-LineWindow {
    param(
        [int]$Total,
        [Nullable[int]]$Start,
        [Nullable[int]]$End,
        [int]$Tail
    )
    if ($Total -lt 0) { $Total = 0 }
    $s = $Start
    $e = $End
    if (-not $s -and -not $e) {
        $s = [Math]::Max($Total - $Tail + 1, 1)
        $e = $Total
    } else {
        if ($s -and $s -lt 1) { $s = 1 }
        if ($e -and $e -lt 1) { $e = 1 }
        if (-not $s -and $e) {
            $s = [Math]::Max($e - $Tail + 1, 1)
        }
        if (-not $e -and $s) {
            $e = [Math]::Min($s + $Tail - 1, $Total)
        }
    }
    if (-not $s) { $s = 1 }
    if (-not $e) { $e = $Total }
    if ($e -lt $s) {
        Write-Warn "结束行小于起始行，已自动调整。"
        $tmp = $s
        $s = $e
        $e = $tmp
    }
    if ($s -lt 1) { $s = 1 }
    if ($e -gt $Total) { $e = $Total }
    return @{ Start = [int]$s; End = [int]$e }
}

function Escape-RegexLiteral {
    param([string]$Text)
    return [regex]::Escape($Text)
}

# -------- argument parsing --------

$Service = $null
$DateSelector = 'today'
$Tail = 20
$StartLine = $null
$EndLine = $null
$Keywords = @()
$Regex = $null
$Plain = $false
$OutputPath = $null
$Force = $false

$i = 0
while ($i -lt $args.Length) {
    $token = $args[$i]
    switch ($token) {
        '--service' { $i++; if ($i -ge $args.Length) { Write-ErrorAndExit '--service 需要参数' }; $Service = $args[$i] }
        '-s'        { $i++; if ($i -ge $args.Length) { Write-ErrorAndExit '-s 需要参数' }; $Service = $args[$i] }
        '--date'    { $i++; if ($i -ge $args.Length) { Write-ErrorAndExit '--date 需要参数' }; $DateSelector = $args[$i] }
        '-d'        { $i++; if ($i -ge $args.Length) { Write-ErrorAndExit '-d 需要参数' }; $DateSelector = $args[$i] }
        '--tail'    { $i++; if ($i -ge $args.Length) { Write-ErrorAndExit '--tail 需要参数' }; $Tail = [int]$args[$i] }
        '-t'        { $i++; if ($i -ge $args.Length) { Write-ErrorAndExit '-t 需要参数' }; $Tail = [int]$args[$i] }
        '--start'   { $i++; if ($i -ge $args.Length) { Write-ErrorAndExit '--start 需要参数' }; $StartLine = [int]$args[$i] }
        '--end'     { $i++; if ($i -ge $args.Length) { Write-ErrorAndExit '--end 需要参数' }; $EndLine = [int]$args[$i] }
        '--keyword' { $i++; if ($i -ge $args.Length) { Write-ErrorAndExit '--keyword 需要参数' }; $Keywords += $args[$i] }
        '-k'        { $i++; if ($i -ge $args.Length) { Write-ErrorAndExit '-k 需要参数' }; $Keywords += $args[$i] }
        '--regex'   { $i++; if ($i -ge $args.Length) { Write-ErrorAndExit '--regex 需要参数' }; $Regex = $args[$i] }
        '-r'        { $i++; if ($i -ge $args.Length) { Write-ErrorAndExit '-r 需要参数' }; $Regex = $args[$i] }
        '--plain'   { $Plain = $true }
        '--output'  { $i++; if ($i -ge $args.Length) { Write-ErrorAndExit '--output 需要参数' }; $OutputPath = $args[$i] }
        '--force'   { $Force = $true }
        '--help'    { Show-Usage; exit 0 }
        '-h'        { Show-Usage; exit 0 }
        '--version' { Write-Output 'check_log.cmd 0.1.0'; exit 0 }
        default     { Write-ErrorAndExit "未知参数：$token" }
    }
    $i++
}

if (-not $Service) {
    Show-Usage
    Write-ErrorAndExit '必须提供 --service'
}

if ($Tail -lt 10 -or $Tail -gt 500) {
    Write-ErrorAndExit '--tail 范围需在 10-500 之间'
}

if ($StartLine -and $StartLine -lt 1) {
    Write-ErrorAndExit '--start 需为正整数'
}
if ($EndLine -and $EndLine -lt 1) {
    Write-ErrorAndExit '--end 需为正整数'
}

if ($OutputPath -and (Test-Path -LiteralPath $OutputPath) -and -not $Force) {
    Write-ErrorAndExit "输出文件已存在：$OutputPath（使用 --force 覆盖）"
}

if ($Regex -and $Keywords.Count -gt 0) {
    Write-Warn '同时传入关键词与正则，将优先使用正则。'
    $Keywords = @()
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$runtimeDir = Split-Path -Parent $scriptDir
$toolsDir = Split-Path -Parent $runtimeDir
$projectRoot = Split-Path -Parent $toolsDir
$logsRoot = Get-LogsRoot -RuntimeRoot $runtimeDir -ProjectRoot $projectRoot
$serviceDir = Join-Path -Path $logsRoot -ChildPath $Service

if (-not (Test-Path -LiteralPath $serviceDir)) {
    $available = (Get-Services -LogsRoot $logsRoot) -join ', '
    if (-not $available) { $available = '无' }
    Write-ErrorAndExit "服务 `$Service` 缺少日志目录：$serviceDir。当前可用服务：$available"
}

$dateToken = Convert-DateSelector -Selector $DateSelector
$logFile = Resolve-LogFile -ServiceDir $serviceDir -DateToken $dateToken
if (-not $logFile) {
    $dates = Collect-KnownDates -ServiceDir $serviceDir | Select-Object -Last 7
    $hint = if ($dates) { ($dates -join ', ') } else { '无可用日期' }
    Write-ErrorAndExit "未找到 $Service 在 $dateToken 的日志文件。可用日期：$hint"
}

if (-not (Test-Path -LiteralPath $logFile)) {
    Write-ErrorAndExit "日志文件缺失：$logFile"
}

$lines = Get-Content -LiteralPath $logFile -Encoding UTF8
$totalLines = $lines.Count
$window = Compute-LineWindow -Total $totalLines -Start $StartLine -End $EndLine -Tail $Tail
$start = $window.Start
$finish = $window.End

$results = @()
for ($idx = $start; $idx -le $finish; $idx++) {
    if ($idx -gt $lines.Count) { break }
    $text = $lines[$idx - 1]
    $keep = $true
    if ($Regex) {
        try {
            if (-not [regex]::new($Regex).IsMatch($text)) {
                $keep = $false
            }
        } catch {
            Write-ErrorAndExit "正则解析失败：$($PSItem.Exception.Message)"
        }
    } elseif ($Keywords.Count -gt 0) {
        foreach ($kw in $Keywords) {
            if ($kw -and ($text.IndexOf($kw, [StringComparison]::OrdinalIgnoreCase) -lt 0)) {
                $keep = $false
                break
            }
        }
    }
    if ($keep) {
        $results += [PSCustomObject]@{
            LineNumber = $idx
            Text       = $text
        }
    }
}

$colorYellow = "$([char]27)[33;1m"
$colorReset = "$([char]27)[0m"
$shouldHighlight = (-not $Plain) -and (-not $OutputPath) -and (-not $Regex) -and ($Keywords.Count -gt 0)

if ($results.Count -eq 0) {
    Write-Warn '当前筛选条件未匹配任何内容。'
} else {
    foreach ($item in $results) {
        $display = $item.Text
        if ($shouldHighlight) {
            foreach ($kw in $Keywords) {
                if (-not [string]::IsNullOrEmpty($kw)) {
                    $escaped = Escape-RegexLiteral -Text $kw
                    $display = [regex]::Replace($display, $escaped, { param($m) "$colorYellow$($m.Value)$colorReset" })
                }
            }
        }
        Write-Output ("{0,6} | {1}" -f $item.LineNumber, $display)
    }
}

if ($OutputPath) {
    $directory = Split-Path -Parent $OutputPath
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    $plainLines = $results | ForEach-Object {
        $text = $_.Text
        "{0,6} | {1}" -f $_.LineNumber, $text
    }
    $plainLines | Set-Content -LiteralPath $OutputPath -Encoding UTF8
}

exit 0
