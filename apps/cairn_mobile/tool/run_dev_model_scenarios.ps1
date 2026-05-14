param(
  [string]$DeviceId     = "",
  [switch]$NativeMtp,
  [switch]$BenchMtp,
  [switch]$CaptureLogcat,
  # §5  — image-size accuracy check: pass 512, 256, 768, or 0 (default)
  [int]   $BenchImagePx  = 0,
  # §6  — backend diagnostic: pass "cpu" or leave empty for GPU default
  [string]$BenchBackend  = "",
  # §7/§8 — session config variant: vision_3072, vision_temp01,
  #          vision_history_retained, std_temp01, etc.  Empty = production.
  [string]$BenchConfig   = "",
  # Destination directory for logcat files (default: bench_out/)
  [string]$OutDir        = "bench_out"
)

$ErrorActionPreference = "Stop"

$adbExe = if (Get-Command adb -ErrorAction SilentlyContinue) { 'adb' } else { 'C:\Dev\android-sdk\platform-tools\adb.exe' }

$argsList = @(
  "run",
  "--profile",
  "--dart-define=DEV_MODEL_TEST=true"
)

if ($DeviceId -ne "") {
  $argsList += @("-d", $DeviceId)
}

if ($NativeMtp) {
  $argsList += @(
    "--dart-define=INFERENCE_RUNTIME=native_mtp",
    "--dart-define=BENCH_RUNTIME=native_mtp",
    "--dart-define=BENCH_MTP=true",
    "--dart-define=BENCH_BATCH=true"
  )
}

if ($BenchMtp -and -not $NativeMtp) {
  $argsList += "--dart-define=BENCH_MTP=true"
}

if ($BenchImagePx -ne 0) {
  $argsList += "--dart-define=BENCH_IMAGE_PX=$BenchImagePx"
}

if ($BenchBackend -ne "") {
  $argsList += "--dart-define=BENCH_BACKEND=$BenchBackend"
}

if ($BenchConfig -ne "") {
  $argsList += "--dart-define=BENCH_CONFIG=$BenchConfig"
}

if ($CaptureLogcat) {
  $stamp   = Get-Date -Format "yyyyMMdd_HHmmss"
  $tag     = @()
  if ($BenchImagePx -ne 0)   { $tag += "px${BenchImagePx}" }
  if ($BenchBackend -ne "")  { $tag += $BenchBackend }
  if ($BenchConfig  -ne "")  { $tag += $BenchConfig }
  $tagStr  = if ($tag.Count -gt 0) { "_$($tag -join '_')" } else { "" }
  $logName = "dev_model_eval_logcat${tagStr}_${stamp}.txt"
  New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
  $logPath = Join-Path $OutDir $logName
  Write-Host "Capturing logcat → $logPath"
  & $adbExe -s $DeviceId logcat -c 2>&1 | Out-Null
  Start-Process -NoNewWindow -FilePath $adbExe -ArgumentList @(
    "-s", $DeviceId, "logcat", "-v", "time"
  ) -RedirectStandardOutput $logPath
}

Write-Host "Launching Cairn Developer Model Test"
Write-Host "flutter $($argsList -join ' ')"
flutter @argsList
