<#
.SYNOPSIS
    Guides the Sprint 2 + Sprint 4 SessionConfig benchmark matrix on a connected Android device.

.DESCRIPTION
    Automates the three-step loop for each benchmark variant:
      1. Launches the app with a launch argument that selects the config variant.
      2. Starts adb logcat capture filtered to /perf lines.
      3. Waits for the user to complete the target flow.
      4. Stops capture, writes the perf file, and appends a summary row.

    Benchmark matrix:

      Sprint 2 variants (docs/optimization-plan.md §OPT-3):
      Variant                  | maxTokens | temperature | clearHistory | Purpose
      -------------------------|-----------|-------------|:------------:|---------------------------
      baseline (vision)        | 4096      | 0.2         | true         | Production reference
      vision_3072              | 3072      | 0.2         | true         | KV-cache memory reduction
      vision_2048              | 2048      | 0.2         | true         | Maximum memory reduction
      vision_temp01            | 4096      | 0.1         | true         | Determinism / brevity
      standard_temp01          | 4096      | 0.1         | true         | Protocol / followup JSON

      Sprint 4 OPT-5 variant (docs/optimization-plan.md §Sprint-4):
      Variant                   | maxTokens | temperature | clearHistory | Purpose
      --------------------------|-----------|-------------|:------------:|-------------------------------
      vision_history_retained   | 4096      | 0.2         | FALSE        | History A/B — prefill delta?

    GATE: every variant must produce zero GemmaContractError and no output
    truncation before it can be promoted to the production default.

    IMPORTANT: The app must be built with --dart-define=BENCH_CONFIG=<variant>
    and the app must read that define at startup. See the implementation note
    below on wiring this into GemmaSessionNotifier.load().

.PARAMETER DeviceId
    ADB device serial number. Default: RZCX920ARVA.

.PARAMETER Variant
    Benchmark variant to run. One of:
      baseline | vision_3072 | vision_2048 | vision_temp01 | standard_temp01 |
      vision_history_retained | all
    Default: all (runs every variant in sequence).

.PARAMETER OutDir
    Directory for perf output files. Default: .\bench_results\

.PARAMETER DurationSeconds
    Seconds to capture logcat per variant. Default: 600 (10 min per variant
    gives enough time for the full describe → synthesize flow).

.EXAMPLE
    # Run all variants
    .\tool\benchmark_session_config.ps1

    # Run one variant with explicit device
    .\tool\benchmark_session_config.ps1 -Variant vision_3072 -DeviceId RZCX920ARVA

    # Short smoke run (120 s per variant)
    .\tool\benchmark_session_config.ps1 -DurationSeconds 120

.NOTES
    ## Wiring BENCH_CONFIG into the app

    In providers.dart, GemmaSessionNotifier.load() already accepts a
    SessionConfig? config parameter. To wire the bench variant from a launch
    argument:

    1. Add to main.dart (debug/profile builds only):
       ```dart
       const benchVariant = String.fromEnvironment('BENCH_CONFIG', defaultValue: '');
       ```

    2. Add a helper that maps the string to a SessionConfig constant:
       ```dart
       SessionConfig? benchConfigFromEnv(String variant) => switch (variant) {
         'vision_3072'    => SessionConfig.visionMaxTokens3072,
         'vision_2048'    => SessionConfig.visionMaxTokens2048,
         'vision_temp01'  => SessionConfig.visionTemp01,
         'std_temp01'     => SessionConfig.standardTemp01,
         _                => null, // null → production default
       };
       ```

    3. Pass the result to load():
       ```dart
       ref.read(gemmaSessionProvider.notifier).load(
         profile: SessionProfile.vision,
         config: benchConfigFromEnv(benchVariant),
       );
       ```

    ## Reading results

    Each variant writes a perf_<variant>_<timestamp>.txt in OutDir.
    Look for lines matching these patterns:

      [Cairn/session]      — config actually used (maxTokens, temperature, ...)
      [Cairn/perf]         — install / engine_create / generate timings
      [LiteRtLmFfi/perf]   — native dylib load, settings_create, engine_create
      [FfiInferenceModel/perf]         — createConversation total
      [FfiInferenceModelSession/perf]  — prefill TTFT, generation total

    ## Truncation check

    A turn is truncated if the output JSON is cut off mid-token. The app will
    throw GemmaContractError("no JSON object in response"). Check for this in
    turns.jsonl (no error entries should appear).

    Reference: docs/optimization-plan.md §Sprint-2, §OPT-3, §Sprint-4
#>
param(
    [string] $DeviceId        = 'RZCX920ARVA',
    [string] $Variant         = 'all',
    [string] $OutDir          = '.\bench_results',
    [int]    $DurationSeconds  = 600
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$allVariants = @('baseline', 'vision_3072', 'vision_2048', 'vision_temp01', 'standard_temp01', 'vision_history_retained')

$variantsToRun = if ($Variant -eq 'all') { $allVariants } else { @($Variant) }
foreach ($v in $variantsToRun) {
    if ($v -notin $allVariants) {
        throw "Unknown variant '$v'. Valid values: $($allVariants -join ', '), all"
    }
}

$adbExe = if (Get-Command adb -ErrorAction SilentlyContinue) { 'adb' } else { 'C:\Dev\android-sdk\platform-tools\adb.exe' }
if (-not (Get-Command $adbExe -ErrorAction SilentlyContinue) -and -not (Test-Path $adbExe -ErrorAction SilentlyContinue)) {
    throw "adb not found. Install Android Platform Tools or add to PATH."
}

New-Item -ItemType Directory -Force $OutDir | Out-Null
$summaryFile = Join-Path $OutDir "benchmark_summary.tsv"

if (-not (Test-Path $summaryFile)) {
    Set-Content $summaryFile "variant`tmaxTokens`ttemperature`tengine_create_ms`tttft_ms_avg`twall_ms_avg`tout_chars_avg`tnotes" -Encoding UTF8
}

function Invoke-VariantBenchmark {
    param([string] $VariantName)

    $dartDefine = switch ($VariantName) {
        'baseline'                { '' }
        'vision_3072'             { '--dart-define=BENCH_CONFIG=vision_3072' }
        'vision_2048'             { '--dart-define=BENCH_CONFIG=vision_2048' }
        'vision_temp01'           { '--dart-define=BENCH_CONFIG=vision_temp01' }
        'standard_temp01'         { '--dart-define=BENCH_CONFIG=std_temp01' }
        'vision_history_retained' { '--dart-define=BENCH_CONFIG=vision_history_retained' }
    }

    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $perfFile  = Join-Path $OutDir "perf_${VariantName}_${timestamp}.txt"

    Write-Host ""
    Write-Host "================================================================"
    Write-Host "VARIANT : $VariantName"
    Write-Host "Device  : $DeviceId"
    Write-Host "Output  : $perfFile"
    Write-Host "Duration: ${DurationSeconds}s"
    Write-Host "================================================================"

    $header = @"
# Cairn SessionConfig benchmark — variant: $VariantName
# Captured: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
# Device  : $DeviceId
# dart-define: $dartDefine
# Duration: ${DurationSeconds}s
# Reference: docs/optimization-plan.md §Sprint-2 §OPT-3
#
# HOW TO INTERPRET:
#   [Cairn/session]              — active config (maxTokens, temperature, ...)
#   [Cairn/perf] phase=install   — model file already cached? (near-zero = yes)
#   [Cairn/perf] phase=engine_create  — model init + KV-cache alloc
#   [Cairn/perf] phase=generate  — per-turn TTFT + wallclock
#   [FfiInferenceModelSession/perf] time-to-first-chunk — native prefill
#   [FfiInferenceModelSession/perf] generation total    — native decode
#
# GATE: zero GemmaContractError entries in turns.jsonl, no JSON truncation.

"@
    Set-Content $perfFile $header -Encoding UTF8

    if ($dartDefine) {
        Write-Host ""
        Write-Host ">>> Run this command in ANOTHER terminal first:"
        Write-Host "    flutter run --profile -d $DeviceId $dartDefine"
        Write-Host ""
        Write-Host "Press ENTER when the app is running on the device..."
        [void][Console]::ReadLine()
    } else {
        Write-Host ""
        Write-Host ">>> BASELINE: Run the app normally (no --dart-define needed):"
        Write-Host "    flutter run --profile -d $DeviceId"
        Write-Host ""
        Write-Host "Press ENTER when the app is running on the device..."
        [void][Console]::ReadLine()
    }

    Write-Host "Clearing logcat buffer..."
    & $adbExe -s $DeviceId logcat -c 2>$null

    Write-Host "Capturing /perf lines for ${DurationSeconds}s..."
    Write-Host "Perform the FULL FLOW on the device: Start → Location → Photos (all 5) → Describe → Protocol → Humility → Synthesize → Report"
    Write-Host "(Press Ctrl+C to stop early)"

    $proc = Start-Process -FilePath $adbExe `
        -ArgumentList "-s $DeviceId logcat -v time" `
        -NoNewWindow -PassThru `
        -RedirectStandardOutput "$env:TEMP\bench_logcat_${VariantName}.txt"

    $deadline = (Get-Date).AddSeconds($DurationSeconds)
    $lineCount = 0

    $attempts = 0
    while (-not (Test-Path "$env:TEMP\bench_logcat_${VariantName}.txt") -and $attempts -lt 30) {
        Start-Sleep -Milliseconds 100
        $attempts++
    }

    $stream = [System.IO.File]::Open(
        "$env:TEMP\bench_logcat_${VariantName}.txt",
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::ReadWrite)
    $reader = New-Object System.IO.StreamReader($stream)

    try {
        while ((Get-Date) -lt $deadline -and -not $proc.HasExited) {
            $line = $reader.ReadLine()
            if ($null -eq $line) { Start-Sleep -Milliseconds 50; continue }
            if ($line -match '/perf|/session') {
                Write-Host $line
                Add-Content $perfFile $line -Encoding UTF8
                $lineCount++
            }
        }
    } finally {
        $reader.Close()
        $stream.Close()
        if (-not $proc.HasExited) { $proc.Kill() }
        Remove-Item "$env:TEMP\bench_logcat_${VariantName}.txt" -ErrorAction SilentlyContinue
    }

    Write-Host ""
    Write-Host "Captured $lineCount /perf lines → $perfFile"

    # Extract summary metrics from perf file
    $engineLine   = Get-Content $perfFile | Select-String 'phase=engine_create' | Select-Object -Last 1
    $generateLines = @(Get-Content $perfFile | Select-String 'phase=generate')

    $engineMs = 'N/A'
    if ($engineLine) {
        if ($engineLine -match 'wall=(\d+)ms') { $engineMs = $Matches[1] }
    }

    $avgTtft = 'N/A'; $avgWall = 'N/A'; $avgOut = 'N/A'
    if ($generateLines.Count -gt 0) {
        $ttfts = @(); $walls = @(); $outs = @()
        foreach ($gl in $generateLines) {
            if ($gl -match 'ttft=(\d+)ms')  { $ttfts += [int]$Matches[1] }
            if ($gl -match 'wall=(\d+)ms')  { $walls += [int]$Matches[1] }
            if ($gl -match 'out_chars=(\d+)') { $outs += [int]$Matches[1] }
        }
        if ($ttfts.Count -gt 0) { $avgTtft = [math]::Round(($ttfts | Measure-Object -Average).Average) }
        if ($walls.Count -gt 0) { $avgWall = [math]::Round(($walls | Measure-Object -Average).Average) }
        if ($outs.Count -gt 0)  { $avgOut  = [math]::Round(($outs  | Measure-Object -Average).Average) }
    }

    $maxTokens = switch ($VariantName) {
        'baseline'                { 4096 }
        'vision_3072'             { 3072 }
        'vision_2048'             { 2048 }
        'vision_temp01'           { 4096 }
        'standard_temp01'         { 4096 }
        'vision_history_retained' { 4096 }
    }
    $temp = if ($VariantName -match 'temp01') { 0.1 } else { 0.2 }

    $row = "$VariantName`t$maxTokens`t$temp`t$engineMs`t$avgTtft`t$avgWall`t$avgOut`t"
    Add-Content $summaryFile $row -Encoding UTF8

    Write-Host ""
    Write-Host "Summary row appended to $summaryFile"
    Write-Host "  engine_create: ${engineMs}ms | avg ttft: ${avgTtft}ms | avg wall: ${avgWall}ms | avg out_chars: $avgOut"
}

Write-Host "Cairn Sprint 2 + Sprint 4 — SessionConfig Benchmark Runner"
Write-Host "Variants to run: $($variantsToRun -join ', ')"
Write-Host "Results directory: $OutDir"
Write-Host ""

foreach ($v in $variantsToRun) {
    Invoke-VariantBenchmark -VariantName $v
    if ($variantsToRun.Count -gt 1 -and $v -ne $variantsToRun[-1]) {
        Write-Host ""
        Write-Host "Variant '$v' done. Press ENTER to continue to the next variant..."
        [void][Console]::ReadLine()
    }
}

Write-Host ""
Write-Host "================================================================"
Write-Host "ALL VARIANTS COMPLETE"
Write-Host "Summary: $summaryFile"
Write-Host ""
Write-Host "PROMOTION GATE (from docs/optimization-plan.md §Sprint-2):"
Write-Host "  - Zero GemmaContractError in turns.jsonl for all variants"
Write-Host "  - No output truncation (JSON parse failures = 0)"
Write-Host "  - engine_create and/or average TTFT/wall improve vs baseline"
Write-Host "  - Update SessionConfig production defaults only after meeting all gates"
Write-Host ""
Write-Host "Sprint 4 OPT-5 gate (vision_history_retained):"
Write-Host "  - Zero cross-photo output contamination (obs[n] must not reference photo[n-1])"
Write-Host "  - TTFT / prefill improves materially (measure vs baseline)"
Write-Host "  - GemmaContractError rate unchanged vs baseline"
Write-Host "  - Promote: set SessionConfig.vision.clearHistoryBetweenTurns = false only if all pass"
Write-Host "================================================================"
