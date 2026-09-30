param(
    [string]$Godot = (Join-Path $env:USERPROFILE 'Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'),
    [switch]$Render
)
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$gamePath = Join-Path $projectRoot 'game'
$logPath = Join-Path $projectRoot 'docs\qa\logs'
if (-not (Test-Path -LiteralPath $Godot -PathType Leaf)) { throw 'Provide the Godot console executable with -Godot.' }
New-Item -ItemType Directory -Path $logPath -Force | Out-Null
$cases = @(
    @{Name='import';Arguments=@('--headless','--path',$gamePath,'--editor','--import')},
    @{Name='attack';Arguments=@('--headless','--path',$gamePath,'--script','res://tests/test_attack.gd')},
    @{Name='character';Arguments=@('--headless','--path',$gamePath,'--script','res://tests/test_character.gd')},
    @{Name='integration';Arguments=@('--headless','--path',$gamePath,'--script','res://tests/test_game.gd')},
    @{Name='input';Arguments=@('--headless','--path',$gamePath,'--script','res://tests/test_input.gd')},
    @{Name='environment';Arguments=@('--headless','--path',$gamePath,'--script','res://environment/check_environment.gd','--quit-after','20')},
    @{Name='smoke';Arguments=@('--headless','--path',$gamePath,'--quit-after','120')}
)
if ($Render) {
    $cases += @{Name='render';Arguments=@('--path',$gamePath,'--script','res://tests/render_sample.gd')}
    $cases += @{Name='character-render';Arguments=@('--path',$gamePath,'--script','res://tests/render_character.gd')}
}
$results = @()
foreach ($case in $cases) {
    $arguments = $case.Arguments
    $lines = @(& $Godot @arguments 2>&1)
    $code = $LASTEXITCODE
    $lines | Set-Content -LiteralPath (Join-Path $logPath ($case.Name + '.log')) -Encoding utf8
    $errors = @($lines | Where-Object { "$_" -match 'SCRIPT ERROR:|^ERROR:|^FAIL:|\b[1-9][0-9]* failures\b' })
    $passed = $code -eq 0 -and $errors.Count -eq 0
    $results += [pscustomobject]@{case=$case.Name;exit_code=$code;passed=$passed;errors=$errors.Count}
    Write-Output ($case.Name + ': ' + $(if ($passed) {'PASS'} else {'FAIL'}))
}
$results | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $logPath 'summary.json') -Encoding utf8
if (@($results | Where-Object { -not $_.passed }).Count) { exit 1 }
exit 0
