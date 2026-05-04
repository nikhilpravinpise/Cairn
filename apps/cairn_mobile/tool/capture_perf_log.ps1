<#
.SYNOPSIS
    Captures flutter_gemma native [*/perf] and Cairn [Cairn/perf] timing
    logs from a connected Android device via adb logcat.

.DESCRIPTION
    Filters logcat for lines containing '/perf'. This single pattern captures
    all relevant timing lines:

      [LiteRtLmFfi/perf]              — dylib load, settings_create, engine_create
      [FfiInferenceModel/perf]        — createConversation, createSession total
      [FfiInferenceModelSession/perf] — time-to-first-chunk (prefill), generation total
      [Cairn/perf]                    — install, engine_create, generate (Dart layer)

    All of these lines appear under the 'flutter' logcat tag on Android because
    flutter_gemma 0.14.3+ and Cairn's PerfLogger both use debugPrint().

    Output is written to a timestamped file and also streamed to the console.

.PARAMETER DeviceId
    ADB device serial number (default: RZCX920ARVA per runlog).

.PARAMETER DurationSeconds
    Capture duration in seconds. 0 = indefinite (stop with Ctrl+C).
    Default: 300.

.PARAMETER OutDir
    Directory for the output file. Default: current directory.

.EXAMPLE
    .\tool\capture_perf_log.ps1
    .\tool\capture_perf_log.ps1 -DeviceId RZCX920ARVA -DurationSeconds 120
    .\tool\capture_perf_log.ps1 -OutDir C:\tmp\perf

.NOTES
    Requires adb in PATH (Android Platform Tools).
    Run `flutter run --release -d RZCX920ARVA` first, then run this script in
    a second terminal to capture the full-flow timing profile.
    Reference: docs/optimization-plan.md §MEASURE-1
#>
param(
    [string] $DeviceId       = 'RZCX920ARVA',
    [int]    $DurationSeconds = 300,
    [string] $OutDir          = '.'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$outFile   = Join-Path $OutDir "perf_${timestamp}.txt"

Write-Host "[capture_perf_log] Device  : $DeviceId"
Write-Host "[capture_perf_log] Duration: $(if ($DurationSeconds -gt 0) { "${DurationSeconds}s" } else { 'indefinite (Ctrl+C to stop)' })"
Write-Host "[capture_perf_log] Output  : $outFile"
Write-Host "[capture_perf_log] Filter  : /perf (flutter_gemma native + Cairn)"
Write-Host "----"

$header = @"
# Cairn perf log — captured $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
# Device  : $DeviceId
# Filter  : adb logcat | grep /perf
# Sources : [LiteRtLmFfi/perf]  [FfiInferenceModel/perf]
#           [FfiInferenceModelSession/perf]  [Cairn/perf]
# flutter_gemma: 0.14.3+
# Reference: docs/optimization-plan.md §MEASURE-1, §Sprint-1

"@
Set-Content -Path $outFile -Value $header -Encoding UTF8

try {
    $adb = Get-Command adb -ErrorAction SilentlyContinue
    if (-not $adb) {
        throw "adb not found in PATH. Install Android Platform Tools and add to PATH."
    }

    # Clear existing logcat buffer so we start clean.
    & adb -s $DeviceId logcat -c 2>$null

    Write-Host "[capture_perf_log] Listening ... (press Ctrl+C to stop early)"

    $proc = Start-Process -FilePath 'adb' `
        -ArgumentList "-s $DeviceId logcat -v time" `
        -NoNewWindow -PassThru `
        -RedirectStandardOutput "$env:TEMP\cairn_logcat_raw.txt"

    $lineCount = 0
    $deadline  = if ($DurationSeconds -gt 0) {
        (Get-Date).AddSeconds($DurationSeconds)
    } else { $null }

    # Stream the raw logcat file and filter for /perf in real time.
    $reader = $null
    $attempts = 0
    while (-not (Test-Path "$env:TEMP\cairn_logcat_raw.txt") -and $attempts -lt 20) {
        Start-Sleep -Milliseconds 100
        $attempts++
    }

    $stream = [System.IO.File]::Open(
        "$env:TEMP\cairn_logcat_raw.txt",
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::ReadWrite)
    $reader = New-Object System.IO.StreamReader($stream)

    while ($true) {
        if ($deadline -and (Get-Date) -ge $deadline) { break }
        if ($proc.HasExited) { break }

        $line = $reader.ReadLine()
        if ($null -eq $line) {
            Start-Sleep -Milliseconds 50
            continue
        }
        if ($line -match '/perf') {
            Write-Host $line
            Add-Content -Path $outFile -Value $line -Encoding UTF8
            $lineCount++
        }
    }
} finally {
    if ($reader) { $reader.Close() }
    if ($proc -and -not $proc.HasExited) { $proc.Kill() }
    Remove-Item "$env:TEMP\cairn_logcat_raw.txt" -ErrorAction SilentlyContinue
}

Write-Host "----"
Write-Host "[capture_perf_log] Done. $lineCount /perf line(s) captured to: $outFile"
