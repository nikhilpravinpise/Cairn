<#
.SYNOPSIS
    Sprint 4 OPT-6 CPU/GPU backend diagnostic benchmark.

.DESCRIPTION
    Launches the Cairn mobile app in --profile mode with BENCH_BACKEND=cpu or
    no override (GPU default), then captures [*/perf] and [Cairn/perf] timing
    logs via adb logcat for the target task.

    Four variants covering two tasks × two backends:
      vision_gpu      — no BENCH_BACKEND (GPU, production default)
      vision_cpu      — BENCH_BACKEND=cpu, vision session
      synthesis_gpu   — no BENCH_BACKEND (GPU, production default)
      synthesis_cpu   — BENCH_BACKEND=cpu, synthesis session

    Each variant requires a focused manual flow: for vision variants, perform
    only the photo-describe step; for synthesis variants, load the synthesis
    model and run the synthesize step.

.PARAMETER Variant
    Which backend variant to run. Required.
    Choices: vision_gpu, vision_cpu, synthesis_gpu, synthesis_cpu, all.

.PARAMETER DeviceId
    ADB device serial number. Default: RZCX920ARVA.

.PARAMETER CaptureDurationSeconds
    How long to capture adb logcat in seconds. Default: 480.

.PARAMETER OutDir
    Directory for the perf log files. Default: current directory.

.EXAMPLE
    .\tool\benchmark_backend.ps1 -Variant vision_gpu
    .\tool\benchmark_backend.ps1 -Variant vision_cpu
    .\tool\benchmark_backend.ps1 -Variant all -OutDir C:\tmp\sprint4_backend

.NOTES
    Requires: adb in PATH, flutter in PATH.
    Reference: docs/optimization-plan.md §Sprint-4 OPT-6

    Gate criteria:
      vision_gpu vs vision_cpu  — which is faster for describe_photo on Exynos 2200?
      synthesis_gpu vs cpu      — which is faster for synthesize (thinking mode)?
    Decision: keep whichever backend gives lower TTFT + total wall clock.
    Expected outcome: GPU faster for multimodal (vision); may be comparable for
    text-only synthesis. Confirm before changing production SessionConfig defaults.

    Key logcat lines to compare per variant:
      [LiteRtLmFfi/perf]              — engine creation time
      [FfiInferenceModelSession/perf] — time_to_first_chunk_ms, generation_time_ms
      [Cairn/perf] phase=generate     — wall=...ms ttft=...ms
#>
param(
    [ValidateSet('vision_gpu', 'vision_cpu', 'synthesis_gpu', 'synthesis_cpu', 'all')]
    [string] $Variant = 'vision_gpu',

    [string] $DeviceId = 'RZCX920ARVA',

    [int] $CaptureDurationSeconds = 480,

    [string] $OutDir = '.'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$appDir = Split-Path -Parent $PSScriptRoot

# Each variant: label, dart-defines, action prompt.
$variants = @{
    'vision_gpu' = @{
        DartDefines = @()
        Task        = 'vision'
        Action      = @(
            '1. App launches with GPU backend (production default).',
            '2. Load the model.',
            '3. Start a new session.',
            '4. Navigate to the Photos screen.',
            '5. Describe all 5 photos using the held-out photo set.',
            '6. Wait for all descriptions to complete.',
            '   Do NOT proceed to Humility or Synthesize.'
        )
    }
    'vision_cpu' = @{
        DartDefines = @('BENCH_BACKEND=cpu')
        Task        = 'vision'
        Action      = @(
            '1. App launches with BENCH_BACKEND=cpu (CPU forced for all sessions).',
            '2. Load the model.',
            '3. Start a new session.',
            '4. Navigate to the Photos screen.',
            '5. Describe all 5 photos using the SAME held-out photo set.',
            '6. Wait for all descriptions to complete.',
            '   Do NOT proceed to Humility or Synthesize.'
        )
    }
    'synthesis_gpu' = @{
        DartDefines = @()
        Task        = 'synthesis'
        Action      = @(
            '1. App launches with GPU backend (production default).',
            '2. Load the model.',
            '3. Start a new session.',
            '4. Navigate through Photos (skip descriptions — tap Continue).',
            '5. Navigate through Humility (skip — tap Skip).',
            '6. Navigate to Synthesize and wait for the synthesis to complete.',
            '   The [*/perf] lines will capture the thinking-mode engine timings.'
        )
    }
    'synthesis_cpu' = @{
        DartDefines = @('BENCH_BACKEND=cpu')
        Task        = 'synthesis'
        Action      = @(
            '1. App launches with BENCH_BACKEND=cpu (CPU forced for all sessions).',
            '2. Load the model.',
            '3. Start a new session.',
            '4. Navigate through Photos (skip descriptions — tap Continue).',
            '5. Navigate through Humility (skip — tap Skip).',
            '6. Navigate to Synthesize and wait for the synthesis to complete.'
        )
    }
}

function Run-Variant {
    param([string] $name)

    $cfg       = $variants[$name]
    $defines   = $cfg.DartDefines -as [string[]]
    $task      = $cfg.Task
    $actionTxt = $cfg.Action -join "`n  "

    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $outFile   = Join-Path $OutDir "bench_backend_${name}_${timestamp}.txt"

    $defineStr = if ($defines.Count -gt 0) { ($defines | ForEach-Object { "--dart-define=$_" }) -join ' ' } else { '(none — GPU default)' }

    Write-Host ""
    Write-Host "===================================================================="
    Write-Host "[benchmark_backend] Variant : $name"
    Write-Host "[benchmark_backend] Defines : $defineStr"
    Write-Host "[benchmark_backend] Task    : $task"
    Write-Host "[benchmark_backend] Device  : $DeviceId"
    Write-Host "[benchmark_backend] Output  : $outFile"
    Write-Host "===================================================================="
    Write-Host ""
    Write-Host "ACTION REQUIRED:"
    Write-Host "  $actionTxt"
    Write-Host ""
    Write-Host "Press ENTER when you are ready to start the app..."
    Read-Host | Out-Null

    $header = @"
# Cairn Sprint 4 OPT-6 backend benchmark — captured $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
# Variant : $name
# Defines : $defineStr
# Task    : $task
# Device  : $DeviceId
# Filter  : adb logcat | grep /perf
# Reference: docs/optimization-plan.md §Sprint-4 OPT-6

"@
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    Set-Content -Path $outFile -Value $header -Encoding UTF8

    & $adbExe -s $DeviceId logcat -c 2>$null

    $flutterArgs = @('run', '--profile', '--no-pub', '-d', $DeviceId)
    foreach ($d in $defines) { $flutterArgs += "--dart-define=$d" }

    Write-Host "[benchmark_backend] Launching: flutter $($flutterArgs -join ' ')"

    $flutterProc = Start-Process -FilePath $flutterExe `
        -ArgumentList $flutterArgs `
        -WorkingDirectory $appDir `
        -NoNewWindow -PassThru

    Start-Sleep -Seconds 5

    $logcatProc = Start-Process -FilePath $adbExe `
        -ArgumentList "-s $DeviceId logcat -v time" `
        -NoNewWindow -PassThru `
        -RedirectStandardOutput "$env:TEMP\cairn_logcat_backend_raw.txt"

    $attempts = 0
    while (-not (Test-Path "$env:TEMP\cairn_logcat_backend_raw.txt") -and $attempts -lt 30) {
        Start-Sleep -Milliseconds 200; $attempts++
    }

    $stream = [System.IO.File]::Open(
        "$env:TEMP\cairn_logcat_backend_raw.txt",
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
        Remove-Item "$env:TEMP\cairn_logcat_backend_raw.txt" -ErrorAction SilentlyContinue
    }

    Write-Host "[benchmark_backend] Done. $lineCount /perf line(s) → $outFile"
}

# ---- Main ----

$adbExe     = if (Get-Command adb -ErrorAction SilentlyContinue) { 'adb' } else { 'C:\Dev\android-sdk\platform-tools\adb.exe' }
$flutterExe = if (Get-Command flutter -ErrorAction SilentlyContinue) { 'flutter' } else { 'C:\Dev\flutter\bin\flutter.bat' }

if ($Variant -eq 'all') {
    foreach ($v in @('vision_gpu', 'vision_cpu', 'synthesis_gpu', 'synthesis_cpu')) {
        Run-Variant -name $v
        Write-Host "[benchmark_backend] Pausing 15 s before next variant..."
        Start-Sleep -Seconds 15
    }
} else {
    Run-Variant -name $Variant
}

Write-Host ""
Write-Host "[benchmark_backend] OPT-6 benchmark complete."
Write-Host ""
Write-Host "Compare these metrics across GPU vs CPU for each task:"
Write-Host "  engine_create wall=...ms"
Write-Host "  [FfiInferenceModelSession/perf] time_to_first_chunk_ms"
Write-Host "  [FfiInferenceModelSession/perf] generation_time_ms"
Write-Host "  [Cairn/perf] phase=generate ttft=...ms wall=...ms"
Write-Host ""
Write-Host "Decision (update session_config.dart if CPU wins):"
Write-Host "  If vision_cpu TTFT < vision_gpu: set SessionConfig.vision.preferredBackend = cpu"
Write-Host "  If synthesis_cpu total < synthesis_gpu: set SessionConfig.synthesis.preferredBackend = cpu"
Write-Host "  Otherwise: GPU confirmed as optimal, no change needed."
