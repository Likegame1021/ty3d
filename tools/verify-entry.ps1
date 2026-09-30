param(
    [string]$Godot = (Join-Path $env:USERPROFILE 'Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'),
    [switch]$Render
)
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$gamePath = Join-Path $projectRoot 'game'
$logPath = Join-Path $projectRoot 'docs\qa\entry-evidence'
if (-not (Test-Path -LiteralPath $Godot -PathType Leaf)) { throw 'Provide the Godot console executable with -Godot.' }
if (-not (Test-Path -LiteralPath (Join-Path $gamePath 'levels\entry.tscn'))) { throw 'The entry adventure scene is missing.' }
New-Item -ItemType Directory -Path $logPath -Force | Out-Null
$cases = @(
    @{Name='import';Arguments=@('--headless','--path',$gamePath,'--editor','--import')},
    @{Name='entry-smoke';Arguments=@('--headless','--path',$gamePath,'res://levels/entry.tscn','--quit-after','180')}
)
$entryTests = @(Get-ChildItem -LiteralPath (Join-Path $gamePath 'tests') -Filter 'test_entry*.gd' | Sort-Object Name)
if ($entryTests.Count -eq 0) { throw 'No entry behavior tests were found.' }
foreach ($test in $entryTests) {
    $cases += @{Name=$test.BaseName;Arguments=@('--headless','--path',$gamePath,'--script',('res://tests/' + $test.Name))}
}
foreach ($test in 'test_attack','test_character','test_game','test_input') {
    $cases += @{Name=('m0-' + $test);Arguments=@('--headless','--path',$gamePath,'--script',('res://tests/' + $test + '.gd'))}
}
$cases += @{Name='m0-environment';Arguments=@('--headless','--path',$gamePath,'--script','res://environment/check_environment.gd','--quit-after','20')}
$cases += @{Name='entry-environment';Arguments=@('--headless','--path',$gamePath,'--script','res://environment/entry_check.gd','--quit-after','180')}
foreach ($test in @(Get-ChildItem -LiteralPath (Join-Path $gamePath 'environment') -Filter 'check_entry*.gd' | Sort-Object Name)) {
    $cases += @{Name=$test.BaseName;Arguments=@('--headless','--path',$gamePath,'--script',('res://environment/' + $test.Name),'--quit-after','90')}
}
if ($Render) {
    # Offscreen placement keeps the automated render window away from the user's work.
    $cases += @{Name='entry-render';Arguments=@('--path',$gamePath,'--position','4000,4000','--script','res://tests/render_entry.gd')}
    $cases += @{Name='entry-visual-diff';Arguments=@('--path',$gamePath,'--position','4000,4000','--script',(Join-Path $projectRoot 'tools\qa\entry-visual-diff.gd'))}
}
$results = @()
foreach ($case in $cases) {
    $arguments = $case.Arguments
    $lines = @(& $Godot @arguments 2>&1)
    $code = $LASTEXITCODE
    $lines | Set-Content -LiteralPath (Join-Path $logPath ($case.Name + '.log')) -Encoding utf8
    $errors = @($lines | Where-Object { "$_" -match 'SCRIPT ERROR:|^ERROR:|^FAIL:|\b[1-9][0-9]* failures\b|ObjectDB instances.*leaked|resources still in use|Leaked instance:' })
    $passed = $code -eq 0 -and $errors.Count -eq 0
    $results += [pscustomobject]@{case=$case.Name;exit_code=$code;passed=$passed;errors=$errors.Count}
    Write-Output ($case.Name + ': ' + $(if ($passed) {'PASS'} else {'FAIL'}))
}
$results | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $logPath 'summary.json') -Encoding utf8
if (@($results | Where-Object { -not $_.passed }).Count) { exit 1 }
exit 0
