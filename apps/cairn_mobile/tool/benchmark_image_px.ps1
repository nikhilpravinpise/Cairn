<#
.SYNOPSIS
    Image-size benchmark — compares raw, 768 px, 640 px, and 512 px
    inference inputs on a connected Android device (RZCX920ARVA).

.DESCRIPTION
    Runs the Cairn mobile app in --profile mode with BENCH_IMAGE_PX set to
    one of three values, then captures [*/perf] and [Cairn/perf] timing logs
    via adb logcat.

    Variants:
      raw     — BENCH_IMAGE_PX=-1  PassthroughImagePreprocessor (no resize)
      768px   — BENCH_IMAGE_PX=768 BoundedImagePreprocessor at 768 px
      640px   — BENCH_IMAGE_PX=0   BoundedImagePreprocessor at spec default (640)
      512px   — BENCH_IMAGE_PX=512 BoundedImagePreprocessor at 512 px

    For each variant, launch the app, load the model, describe 5 photos
    (use the same held-out photo set for all variants), then stop.
    Compare the [*/perf] prefill/decode lines across the three runs.

.PARAMETER Variant
    Which image-size variant to run. Defaults to '640px'.
    Choices: raw, 768px, 640px, 512px, all (run all variants in sequence).

.PARAMETER DeviceId
    ADB device serial number. Default: RZCX920ARVA.

.PARAMETER CaptureDurationSeconds
    How long to capture adb logcat after flutter run starts, in seconds.
    Allow enough time to load the model + describe 5 photos. Default: 600.

.PARAMETER OutDir
    Directory for the perf log files. Default: current directory.

.EXAMPLE
    .\tool\benchmark_image_px.ps1 -Variant 640px
    .\tool\benchmark_image_px.ps1 -Variant all -OutDir C:\tmp\sprint3
    .\tool\benchmark_image_px.ps1 -Variant raw -DeviceId RZCX920ARVA

.NOTES
    Requires: adb in PATH, flutter in PATH.
    Reference: docs/optimization-plan.md §Sprint-3 OPT-1

    Current decision:
      640px  — promoted after S23 FE accuracy gate.
      512px  — rejected for soft-story / column-base accuracy regression.
#>
param(
    [ValidateSet('raw', '768px', '640px', '512px', 'all')]
    [string] $Variant = '640px',

    [string] $DeviceId = 'RZCX920ARVA',

    [int] $CaptureDurationSeconds = 600,

    [string] $OutDir = '.'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$appDir = Split-Path -Parent $PSScriptRoot

# Map variant name to BENCH_IMAGE_PX value.
$variantMap = @{
    'raw'   = -1
    '768px' = 768
    '640px' = 0
    '512px' = 512
}

function Run-Variant {
    param([string] $name)

    $px = $variantMap[$name]
    if ($null -eq $px) { throw "Unknown variant: $name" }

    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $outFile   = Join-Path $OutDir "bench_image_px_${name}_${timestamp}.txt"

    Write-Host ""
    Write-Host "===================================================================="
    Write-Host "[benchmark_image_px] Variant : $name  (BENCH_IMAGE_PX=$px)"
    Write-Host "[benchmark_image_px] Device  : $DeviceId"
    Write-Host "[benchmark_image_px] Output  : $outFile"
    Write-Host "===================================================================="
    Write-Host ""
    Write-Host "ACTION REQUIRED:"
    Write-Host "  1. Wait for the app to launch and the model to load."
    Write-Host "  2. Start a new session."
    Write-Host "  3. Navigate to the Photos screen."
    Write-Host "  4. Describe all 5 photos using the SAME held-out photo set"
    Write-Host "     as every other benchmark variant."
    Write-Host "  5. Wait for all descriptions to complete."
    Write-Host "  The script will capture perf logs for $CaptureDurationSeconds seconds."
    Write-Host ""

    $header = @"
# Cairn Sprint 3 image-px benchmark — captured $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
# Variant : $name
# BENCH_IMAGE_PX : $px
# Device  : $DeviceId
# Filter  : adb logcat | grep /perf
# Reference: docs/optimization-plan.md §Sprint-3 OPT-1

"@
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    Set-Content -Path $outFile -Value $header -Encoding UTF8

    # Clear logcat before starting.
    & $adbExe -s $DeviceId logcat -c 2>$null

    # Launch flutter run --profile with the bench dart-define.
    $flutterArgs = @(
        'run', '--profile', '--no-pub',
        '-d', $DeviceId,
        "--dart-define=BENCH_IMAGE_PX=$px"
    )
    Write-Host "[benchmark_image_px] Launching: flutter $($flutterArgs -join ' ')"

    $flutterProc = Start-Process -FilePath $flutterExe `
        -ArgumentList $flutterArgs `
        -WorkingDirectory $appDir `
        -NoNewWindow -PassThru

    # Allow the app a moment to reach logcat output.
    Start-Sleep -Seconds 5

    # Stream logcat, filter for /perf lines, write to file.
    $logcatProc = Start-Process -FilePath $adbExe `
        -ArgumentList "-s $DeviceId logcat -v time" `
        -NoNewWindow -PassThru `
        -RedirectStandardOutput "$env:TEMP\cairn_logcat_px_raw.txt"

    $attempts = 0
    while (-not (Test-Path "$env:TEMP\cairn_logcat_px_raw.txt") -and $attempts -lt 30) {
        Start-Sleep -Milliseconds 200
        $attempts++
    }

    $stream = [System.IO.File]::Open(
        "$env:TEMP\cairn_logcat_px_raw.txt",
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::ReadWrite)
    $reader = New-Object System.IO.StreamReader($stream)

    $deadline  = (Get-Date).AddSeconds($CaptureDurationSeconds)
    $lineCount = 0

    try {
        while ((Get-Date) -lt $deadline) {
            $line = $reader.ReadLine()
            if ($null -eq $line) { Start-Sleep -Milliseconds 50; continue }
            if ($line -match '/perf') {
                Write-Host $line
                Add-Content -Path $outFile -Value $line -Encoding UTF8
                $lineCount++
            }
        }
    } finally {
        $reader.Close()
        $stream.Close()
        if (-not $logcatProc.HasExited) { $logcatProc.Kill() }
        if (-not $flutterProc.HasExited) { $flutterProc.Kill() }
        Remove-Item "$env:TEMP\cairn_logcat_px_raw.txt" -ErrorAction SilentlyContinue
    }

    Write-Host "[benchmark_image_px] Done. $lineCount /perf line(s) → $outFile"
    Write-Host ""
}

# ---- Main ----

$adbExe    = if (Get-Command adb -ErrorAction SilentlyContinue) { 'adb' } else { 'C:\Dev\android-sdk\platform-tools\adb.exe' }
$flutterExe = if (Get-Command flutter -ErrorAction SilentlyContinue) { 'flutter' } else { 'C:\Dev\flutter\bin\flutter.bat' }
if (-not (Test-Path $adbExe -ErrorAction SilentlyContinue) -and -not (Get-Command $adbExe -ErrorAction SilentlyContinue)) { throw "adb not found." }
if (-not (Test-Path $flutterExe -ErrorAction SilentlyContinue) -and -not (Get-Command $flutterExe -ErrorAction SilentlyContinue)) { throw "flutter not found." }

if ($Variant -eq 'all') {
    foreach ($v in @('raw', '768px', '640px', '512px')) {
        Run-Variant -name $v
        if ($v -ne '512px') {
            Write-Host "[benchmark_image_px] Pausing 10 s before next variant..."
            Start-Sleep -Seconds 10
        }
    }
} else {
    Run-Variant -name $Variant
}

Write-Host "[benchmark_image_px] Sprint 3 image-px benchmark complete."
Write-Host "Compare the captured files:"
Write-Host "  bench_image_px_raw_*.txt    → raw baseline"
Write-Host "  bench_image_px_768px_*.txt  → 768 px conservative fallback"
Write-Host "  bench_image_px_640px_*.txt  → 640 px current production default"
Write-Host "  bench_image_px_512px_*.txt  → 512 px rejected unless a new model recovers accuracy"
Write-Host ""
Write-Host "Key metrics to compare:"
Write-Host "  [FfiInferenceModelSession/perf] time_to_first_chunk_ms"
Write-Host "  [FfiInferenceModelSession/perf] generation_time_ms"
Write-Host "  [Cairn/perf] phase=generate img_bytes=..."
Write-Host ""
Write-Host "Keep 640px unless a new device/model run proves 512px preserves structural tags."
