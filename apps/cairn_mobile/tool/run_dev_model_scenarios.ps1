param(
  [string]$DeviceId = "",
  [switch]$NativeMtp,
  [switch]$CaptureLogcat
)

$ErrorActionPreference = "Stop"

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

if ($CaptureLogcat) {
  $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
  $logPath = "dev_model_eval_logcat_$stamp.txt"
  Write-Host "Capturing logcat to $logPath"
  Start-Process -NoNewWindow -FilePath "adb" -ArgumentList @(
    "logcat",
    "-v",
    "time"
  ) -RedirectStandardOutput $logPath
}

Write-Host "Launching Cairn Developer Model Test"
Write-Host "flutter $($argsList -join ' ')"
flutter @argsList
