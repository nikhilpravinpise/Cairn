<#
.SYNOPSIS
    Android speed benchmark matrix for Cairn Gemma 4 inference.

.DESCRIPTION
    Runs profile builds for runtime/backend/image-size/batch variants and
    captures all /perf logcat lines. Use the same curated dev scenarios for
    every variant. The script does not decide production defaults; it records
    comparable evidence for the 3x end-to-end gate.
#>
param(
    [string] $DeviceId = 'RZCX920ARVA',
    [int] $CaptureDurationSeconds = 600,
    [string] $OutDir = '.',
    [ValidateSet('matrix', 'flutter', 'native_mtp_gpu', 'native_mtp_cpu', 'native_mtp_batch')]
    [string] $Variant = 'matrix'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$appDir = Split-Path -Parent $PSScriptRoot
$adbExe = if (Get-Command adb -ErrorAction SilentlyContinue) { 'adb' } else { 'C:\Dev\android-sdk\platform-tools\adb.exe' }
$flutterExe = if (Get-Command flutter -ErrorAction SilentlyContinue) { 'flutter' } else { 'C:\Dev\flutter\bin\flutter.bat' }

$matrix = @{
    flutter = @(
        @('INFERENCE_RUNTIME=flutter_gemma', 'BENCH_IMAGE_PX=768')
    )
    native_mtp_gpu = @(
        @('INFERENCE_RUNTIME=native_mtp', 'BENCH_MTP=true', 'BENCH_BACKEND=gpu', 'BENCH_IMAGE_PX=512'),
        @('INFERENCE_RUNTIME=native_mtp', 'BENCH_MTP=true', 'BENCH_BACKEND=gpu', 'BENCH_IMAGE_PX=640'),
        @('INFERENCE_RUNTIME=native_mtp', 'BENCH_MTP=true', 'BENCH_BACKEND=gpu', 'BENCH_IMAGE_PX=768')
    )
    native_mtp_cpu = @(
        @('INFERENCE_RUNTIME=native_mtp', 'BENCH_MTP=true', 'BENCH_BACKEND=cpu', 'BENCH_IMAGE_PX=640')
    )
    native_mtp_batch = @(
        @('INFERENCE_RUNTIME=native_mtp', 'BENCH_MTP=true', 'BENCH_BACKEND=gpu', 'BENCH_BATCH=true', 'BENCH_IMAGE_PX=640')
    )
}

function Run-One {
    param(
        [string] $Name,
        [string[]] $Defines
    )

    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $safeDefines = ($Defines -join '_') -replace '[^A-Za-z0-9_=-]', '_'
    $outFile = Join-Path $OutDir "bench_android_${Name}_${safeDefines}_${timestamp}.txt"
    $defineArgs = @()
    foreach ($d in $Defines) { $defineArgs += "--dart-define=$d" }

    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    Set-Content -Path $outFile -Encoding UTF8 -Value @"
# Cairn Android speed benchmark — captured $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
# Variant : $Name
# Defines : $($Defines -join ', ')
# Device  : $DeviceId
# Gate    : 4-photo total wall time >=3x faster than baseline, zero schema failures.

"@

    Write-Host ""
    Write-Host "===================================================================="
    Write-Host "[benchmark_android_speed] Variant : $Name"
    Write-Host "[benchmark_android_speed] Defines : $($defineArgs -join ' ')"
    Write-Host "[benchmark_android_speed] Output  : $outFile"
    Write-Host "===================================================================="
    Write-Host "Run the same curated scenario set, then wait for capture to finish."
    Write-Host "Press ENTER to launch..."
    Read-Host | Out-Null

    & $adbExe -s $DeviceId logcat -c 2>$null
    $flutterArgs = @('run', '--profile', '--no-pub', '-d', $DeviceId, '--dart-define=DEV_MODEL_TEST=true')
    $flutterArgs += $defineArgs
    $flutterProc = Start-Process -FilePath $flutterExe `
        -ArgumentList $flutterArgs `
        -WorkingDirectory $appDir `
        -NoNewWindow -PassThru

    Start-Sleep -Seconds 5
    $rawLog = Join-Path $env:TEMP "cairn_android_speed_${Name}_raw.txt"
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
            if ($line -match '/perf|Cairn/native_mtp|schema_failure|total_wallclock_ms') {
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

$groups = if ($Variant -eq 'matrix') {
    @('flutter', 'native_mtp_gpu', 'native_mtp_cpu', 'native_mtp_batch')
} else {
    @($Variant)
}

foreach ($group in $groups) {
    foreach ($defines in $matrix[$group]) {
        Run-One -Name $group -Defines $defines
        if ($group -ne $groups[-1]) { Start-Sleep -Seconds 10 }
    }
}
