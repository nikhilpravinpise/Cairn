$ErrorActionPreference = "Stop"

$repo_root = Resolve-Path "$PSScriptRoot\..\..\.."
$app_root = "$repo_root\apps\cairn_mobile"

$src_prompt = "$repo_root\docs\prompts\system_prompt_v1.txt"
$dst_prompt = "$app_root\assets\prompts\system_prompt_v1.txt"

$src_schema = "$repo_root\docs\schema\evidence_packet_v1.schema.json"
$dst_schema = "$app_root\assets\schema\evidence_packet_v1.schema.json"

if (-Not (Test-Path $src_prompt)) { Write-Error "missing $src_prompt"; exit 1 }
if (-Not (Test-Path $src_schema)) { Write-Error "missing $src_schema"; exit 1 }

New-Item -ItemType Directory -Force (Split-Path $dst_prompt) | Out-Null
New-Item -ItemType Directory -Force (Split-Path $dst_schema) | Out-Null

Copy-Item $src_prompt $dst_prompt -Force
Copy-Item $src_schema $dst_schema -Force

Write-Host "synced $dst_prompt"
Write-Host "synced $dst_schema"
