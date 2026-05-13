<#
.SYNOPSIS
    Gemma 4 runtime benchmark: flutter_gemma baseline vs MTP paths.

.DESCRIPTION
    Launches Cairn in profile mode with one of the runtime dart-defines, then
    captures /perf logcat lines. Use the same held-out photo set for every run.

    Variants:
      flutter       — default flutter_gemma path, MTP off
      flutter_mtp   — official flutter_gemma speculative decoding path
      native_mtp    — legacy Android LiteRT-LM bridge with MTP enabled
      native_batch  — native_mtp plus BENCH_BATCH=true

.PARAMETER Variant
    flutter, flutter_mtp, native_mtp, native_batch, or all.

.PARAMETER DeviceId
    ADB serial. Default: RZCX920ARVA.

.PARAMETER CaptureDurationSeconds
    Logcat capture duration. Default: 600.

.PARAMETER OutDir
    Output directory. Default: current directory.
#>
param(
    [ValidateSet('flutter', 'flutter_mtp', 'native_mtp', 'native_batch', 'all')]
    [string] $Variant = 'flutter',

    [string] $DeviceId = 'RZCX920ARVA',

    [int] $CaptureDurationSeconds = 600,

    [string] $OutDir = '.'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$appDir = Split-Path -Parent $PSScriptRoot
$adbExe = if (Get-Command adb -ErrorAction SilentlyContinue) { 'adb' } else { 'C:\Dev\android-sdk\platform-tools\adb.exe' }
$flutterExe = if (Get-Command flutter -ErrorAction SilentlyContinue) { 'flutter' } else { 'C:\Dev\flutter\bin\flutter.bat' }

$variants = @{
    'flutter' = @{
        Defines = @('INFERENCE_RUNTIME=flutter_gemma', 'BENCH_IMAGE_PX=640')
        Notes   = 'Default flutter_gemma 0.15.x path, speculative decoding off.'
    }
    'flutter_mtp' = @{
        Defines = @('INFERENCE_RUNTIME=flutter_gemma', 'BENCH_MTP=true', 'BENCH_IMAGE_PX=640')
        Notes   = 'Official flutter_gemma 0.15.x LiteRT-LM speculative decoding path.'
    }
    'native_mtp' = @{
        Defines = @('INFERENCE_RUNTIME=native_mtp', 'BENCH_MTP=true', 'BENCH_IMAGE_PX=640')
        Notes   = 'Legacy Android LiteRT-LM bridge with speculative decoding enabled.'
    }
    'native_batch' = @{
        Defines = @('INFERENCE_RUNTIME=native_mtp', 'BENCH_MTP=true', 'BENCH_BATCH=true', 'BENCH_IMAGE_PX=640')
        Notes   = 'Legacy native MTP plus one-turn multi-image batch experiment.'
    }
}

function Run-Variant {
    param([string] $Name)

    $cfg = $variants[$Name]
    $defines = $cfg.Defines -as [string[]]
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $outFile = Join-Path $OutDir "bench_runtime_${Name}_${timestamp}.txt"
    $defineArgs = @()
    foreach ($d in $defines) { $defineArgs += "--dart-define=$d" }

    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    Set-Content -Path $outFile -Encoding UTF8 -Value @"
# Cairn Gemma 4 runtime benchmark — captured $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
# Variant : $Name
# Defines : $($defines -join ', ')
# Device  : $DeviceId
# Notes   : $($cfg.Notes)
# Acceptance:
#   flutter_mtp/native_mtp: decode tokens/sec +35% OR total wall time +20% vs flutter
#   native_batch: 4-photo total wall time +30% vs sequential, no contamination

"@

    Write-Host ""
    Write-Host "===================================================================="
    Write-Host "[benchmark_runtime] Variant : $Name"
    Write-Host "[benchmark_runtime] Defines : $($defineArgs -join ' ')"
    Write-Host "[benchmark_runtime] Output  : $outFile"
    Write-Host "===================================================================="
    Write-Host "Use the same 4 required photos for every variant."
    Write-Host "Press ENTER to launch the app..."
    Read-Host | Out-Null

    & $adbExe -s $DeviceId logcat -c 2>$null
    $flutterArgs = @('run', '--profile', '--no-pub', '-d', $DeviceId)
    $flutterArgs += $defineArgs
    $flutterProc = Start-Process -FilePath $flutterExe `
        -ArgumentList $flutterArgs `
        -WorkingDirectory $appDir `
        -NoNewWindow -PassThru

    Start-Sleep -Seconds 5
    $rawLog = Join-Path $env:TEMP "cairn_runtime_${Name}_raw.txt"
    $logcatProc = Start-Process -FilePath $adbExe `
        -ArgumentList "-s $DeviceId logcat -v time" `
        -NoNewWindow -PassThru `
        -RedirectStandardOutput $rawLog

    $stream = [System.IO.File]::Open(
        $rawLog,
        [System.IO.FileMode]::OpenOrCreate,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::ReadWrite)
    $reader = New-Object System.IO.StreamReader($stream)
    $deadline = (Get-Date).AddSeconds($CaptureDurationSeconds)
    try {
        while ((Get-Date) -lt $deadline) {
            $line = $reader.ReadLine()
            if ($null -eq $line) { Start-Sleep -Milliseconds 50; continue }
            if ($line -match '/perf|Cairn/native_mtp|Cairn/session') {
                Write-Host $line
                Add-Content -Path $outFile -Value $line -Encoding UTF8
            }
        }
    } finally {
        $reader.Close()
        $stream.Close()
        if (-not $logcatProc.HasExited) { $logcatProc.Kill() }
        if (-not $flutterProc.HasExited) { $flutterProc.Kill() }
        Remove-Item $rawLog -ErrorAction SilentlyContinue
    }
}

if ($Variant -eq 'all') {
    foreach ($v in @('flutter', 'flutter_mtp', 'native_mtp', 'native_batch')) {
        Run-Variant -Name $v
    }
} else {
    Run-Variant -Name $Variant
}
