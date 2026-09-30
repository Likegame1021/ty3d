param(
    [string]$Godot = (Join-Path $env:USERPROFILE 'Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'),
    [switch]$Render,
    [switch]$SkipRegression,
    [string]$EvidenceDirectory
)
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$gamePath = Join-Path $projectRoot 'game'
$logPath = Join-Path $projectRoot 'docs\qa\full-evidence'
if ($EvidenceDirectory) { $logPath = [IO.Path]::GetFullPath($EvidenceDirectory) }
if (-not (Test-Path -LiteralPath $Godot -PathType Leaf)) { throw 'Provide the Godot console executable with -Godot.' }
if (-not (Test-Path -LiteralPath (Join-Path $gamePath 'levels\full.tscn'))) { throw 'The full scene is missing.' }
New-Item -ItemType Directory -Path $logPath -Force | Out-Null
function Get-VerifiedFiles {
    $files = @(Get-ChildItem -LiteralPath $gamePath -Recurse -File | Where-Object {
        $_.FullName -notmatch '[\\/]\.godot[\\/]' -and ($_.Extension -in '.gd','.gdshader','.tscn','.glb','.tres','.wav' -or $_.Name -eq 'project.godot' -or ($_.FullName -match '[\\/]assets[\\/]' -and $_.Extension -in '.png','.jpg','.jpeg','.webp'))
    })
    $files += @(Get-ChildItem -LiteralPath (Join-Path $projectRoot 'tools\qa') -Filter 'full-*.gd' -File)
    foreach ($file in ($files | Sort-Object FullName)) {
        [pscustomobject]@{path=$file.FullName.Substring($projectRoot.Length + 1).Replace('\','/');sha256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash}
    }
}
$beforeFiles = @(Get-VerifiedFiles)
$cases = @(
    @{Name='import';Arguments=@('--headless','--path',$gamePath,'--editor','--import')},
    @{Name='full-smoke';Arguments=@('--headless','--path',$gamePath,'res://levels/full.tscn','--quit-after','240')}
)
$fullTests = @(Get-ChildItem -LiteralPath (Join-Path $gamePath 'tests') -Filter 'test_full*.gd' | Sort-Object Name)
if ($fullTests.Count -eq 0) { throw 'No full scene behavior tests were found.' }
foreach ($test in $fullTests) {
    $cases += @{Name=$test.BaseName;Arguments=@('--headless','--path',$gamePath,'--script',('res://tests/' + $test.Name))}
}
foreach ($test in 'check_corn_fx','check_corn_hold') {
    if (Test-Path -LiteralPath (Join-Path $gamePath ('weapons/' + $test + '.gd'))) {
        $cases += @{Name=$test;Arguments=@('--headless','--path',$gamePath,'--script',('res://weapons/' + $test + '.gd'))}
    }
}
foreach ($test in @(Get-ChildItem -LiteralPath (Join-Path $gamePath 'environment') -Filter '*full*check*.gd' | Sort-Object Name)) {
    $cases += @{Name=$test.BaseName;Arguments=@('--headless','--path',$gamePath,'--script',('res://environment/' + $test.Name))}
}
foreach ($test in @(Get-ChildItem -LiteralPath (Join-Path $projectRoot 'tools\qa') -Filter 'full-*.gd' | Where-Object { $_.Name -notlike 'full-gpu-*' } | Sort-Object Name)) {
    $cases += @{Name=$test.BaseName;Arguments=@('--headless','--path',$gamePath,'--script',$test.FullName)}
}
if (-not $SkipRegression) {
    foreach ($test in @(Get-ChildItem -LiteralPath (Join-Path $gamePath 'tests') -Filter 'test_entry*.gd' | Sort-Object Name)) {
        $cases += @{Name=('m1-' + $test.BaseName);Arguments=@('--headless','--path',$gamePath,'--script',('res://tests/' + $test.Name))}
    }
    foreach ($test in 'test_attack','test_character','test_game','test_input') {
        $cases += @{Name=('m0-' + $test);Arguments=@('--headless','--path',$gamePath,'--script',('res://tests/' + $test + '.gd'))}
    }
}
if ($Render) {
    $environmentCapture = Join-Path $gamePath 'environment\full_capture.gd'
    if (Test-Path -LiteralPath $environmentCapture) {
        $cases += @{Name='full-environment-capture';Arguments=@('--path',$gamePath,'--position','4000,4000','--script','res://environment/full_capture.gd')}
    }
    foreach ($test in @(Get-ChildItem -LiteralPath (Join-Path $gamePath 'tests') -Filter 'render_full*.gd' | Sort-Object Name)) {
        $cases += @{Name=$test.BaseName;Arguments=@('--path',$gamePath,'--position','4000,4000','--script',('res://tests/' + $test.Name))}
    }
    foreach ($test in @(Get-ChildItem -LiteralPath (Join-Path $projectRoot 'tools\qa') -Filter 'full-gpu-*.gd' | Sort-Object Name)) {
        $cases += @{Name=$test.BaseName;Arguments=@('--path',$gamePath,'--position','4000,4000','--script',$test.FullName)}
    }
}
$results = @()
foreach ($case in $cases) {
    $arguments = $case.Arguments + @('--max-fps','60')
    if ($case.Name -in 'check_corn_fx','test_full_corn_audio') {
        $arguments += @('--audio-driver','WASAPI')
    }
    $lines = @(& $Godot @arguments 2>&1)
    $code = $LASTEXITCODE
    $lines | Set-Content -LiteralPath (Join-Path $logPath ($case.Name + '.log')) -Encoding utf8
    $errors = @($lines | Where-Object { "$_" -match 'SCRIPT ERROR:|^ERROR:|^FAIL:|\b[1-9][0-9]* failures\b|ObjectDB instances.*leaked|resources still in use|Leaked instance:' })
    $passed = $code -eq 0 -and $errors.Count -eq 0
    $results += [pscustomobject]@{case=$case.Name;exit_code=$code;passed=$passed;errors=$errors.Count}
    $results | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $logPath 'summary.json') -Encoding utf8
    Write-Output ($case.Name + ': ' + $(if ($passed) {'PASS'} else {'FAIL'}))
}
$afterFiles = @(Get-VerifiedFiles)
$stable = (ConvertTo-Json -InputObject $beforeFiles -Compress) -eq (ConvertTo-Json -InputObject $afterFiles -Compress)
$results += [pscustomobject]@{case='verified-files-unchanged';exit_code=$(if ($stable) {0} else {1});passed=$stable;errors=$(if ($stable) {0} else {1})}
$afterFiles | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $logPath 'verified-files.json') -Encoding utf8
$results | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $logPath 'summary.json') -Encoding utf8
Write-Output ('verified-files-unchanged: ' + $(if ($stable) {'PASS'} else {'FAIL (source changed during validation)'}))
if (@($results | Where-Object { -not $_.passed }).Count) { exit 1 }
exit 0
