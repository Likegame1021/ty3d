param([switch]$CheckOnly, [switch]$Editor, [ValidateSet('Validation','Adventure','Full','CornGun')][string]$Mode = 'Validation')
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$gamePath = Join-Path $projectRoot 'game'
$scene = switch ($Mode) {
    'CornGun' { 'res://levels/corn_lab.tscn' }
    'Full' { 'res://levels/full.tscn' }
    'Adventure' { 'res://levels/entry.tscn' }
    default { 'res://main.tscn' }
}
$sceneFile = Join-Path $gamePath ($scene.Replace('res://',''))
$candidates = @(
    $env:GODOT_EXE,
    (Join-Path $env:USERPROFILE 'Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe')
)
$command = Get-Command godot -ErrorAction SilentlyContinue
if ($command) { $candidates += $command.Source }
$godot = $candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1
if (-not $godot) {
    Write-Host 'Godot was not found. Set GODOT_EXE to your Godot 4 executable, then run again.'
    exit 1
}
if (-not (Test-Path -LiteralPath (Join-Path $gamePath 'project.godot'))) {
    Write-Host 'The game/project.godot file is missing. Keep this launcher with the project.'
    exit 1
}
if (-not (Test-Path -LiteralPath $sceneFile -PathType Leaf)) {
    Write-Host ('The requested scene is missing: ' + $scene)
    exit 1
}
if ($CheckOnly) {
    [pscustomobject]@{engine=$godot;project=$gamePath;scene=$scene;character_present=(Test-Path -LiteralPath (Join-Path $gamePath 'assets\characters\boy\boy.glb'))} | ConvertTo-Json
    exit 0
}
# Import source assets on first use or after a Blender re-export.
& $godot --headless --path $gamePath --editor --import
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
if ($Editor) { & $godot --path $gamePath --editor $scene } else { & $godot --path $gamePath $scene }
exit $LASTEXITCODE
