$ErrorActionPreference = "Stop"
# 本脚本位于 <项目>/tools/
$repoRoot = Split-Path $PSScriptRoot -Parent
if (-not (Test-Path (Join-Path $repoRoot "project.godot"))) {
	throw "未找到 project.godot，请从项目根目录的 tools 运行: $PSScriptRoot"
}
$pathsFile = Join-Path $PSScriptRoot "EDITOR_PATHS.txt"
$exeLine = Get-Content $pathsFile | Where-Object { $_ -match '^GODOT_CONSOLE_EXE=' } | Select-Object -First 1
if (-not $exeLine) { throw "EDITOR_PATHS.txt 缺少 GODOT_CONSOLE_EXE=" }
$godotExe = ($exeLine -split "=", 2)[1].Trim()
if (-not (Test-Path $godotExe)) { throw "找不到 Godot: $godotExe" }
Write-Host "Godot: $godotExe"
Write-Host "Project: $repoRoot"
& $godotExe --path $repoRoot --headless --display-driver headless --audio-driver Dummy --import --quit
