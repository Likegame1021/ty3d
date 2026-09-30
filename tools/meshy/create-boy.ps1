$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$outputDir = Join-Path $projectRoot 'art\characters\boy\meshy\v001'
$responsePath = Join-Path $outputDir 'generation-created.json'
if (Test-Path -LiteralPath $responsePath) { throw 'Generation already submitted. Read the saved task ID; do not duplicate it.' }
$referenceDir = Join-Path $projectRoot 'art\characters\boy\references\v001'
$imagePaths = @('front.png','left.png','back.png','right.png') | ForEach-Object { Join-Path $referenceDir $_ }
foreach ($path in $imagePaths) { if (-not (Test-Path -LiteralPath $path)) { throw 'A required reference image is missing.' } }
$parameters = [ordered]@{
    ai_model = 'meshy-7.1'
    geometry_resolution = 'standard'
    should_texture = $true
    enable_pbr = $true
    texture_resolution = '2k'
    should_remesh = $true
    topology = 'triangle'
    target_polycount = 20000
    save_pre_remeshed_model = $true
    pose_mode = 't-pose'
    image_enhancement = $false
    remove_lighting = $true
    target_formats = @('glb')
}
New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
[ordered]@{image_files=$imagePaths;parameters=$parameters;submitted_at=(Get-Date).ToString('o')} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $outputDir 'generation-request.json') -Encoding utf8
$body = @{}
foreach ($key in $parameters.Keys) { $body[$key] = $parameters[$key] }
$body.image_urls = @($imagePaths | ForEach-Object { 'data:image/png;base64,' + [Convert]::ToBase64String([IO.File]::ReadAllBytes($_)) })
$secureKey = $null
$headers = $null
try {
    $secureKey = Import-Clixml -LiteralPath (Join-Path $projectRoot '.local\meshy\api-key.clixml')
    $credential = [Net.NetworkCredential]::new('', $secureKey)
    $headers = @{Authorization='Bearer ' + $credential.Password}
    $response = Invoke-WebRequest -Uri 'https://api.meshy.ai/openapi/v1/multi-image-to-3d' -Method Post -Headers $headers -ContentType 'application/json' -Body ($body | ConvertTo-Json -Depth 8 -Compress) -MaximumRedirection 0 -TimeoutSec 120 -SkipHttpErrorCheck -Verbose:$false -Debug:$false
    if ([int]$response.StatusCode -notin @(200,201,202)) {
        Write-Output ([pscustomobject]@{success=$false;http_status=[int]$response.StatusCode;message=($response.Content -replace 'msy_[A-Za-z0-9]+','[REDACTED]')} | ConvertTo-Json -Compress)
        exit 1
    }
    $result = $response.Content | ConvertFrom-Json
    if (-not $result.result) { throw 'Response did not include task ID.' }
    $response.Content | Set-Content -LiteralPath $responsePath -Encoding utf8
    [pscustomobject]@{success=$true;task_id=$result.result;reference_count=$imagePaths.Count;output=$responsePath} | ConvertTo-Json -Compress
} catch {
    Write-Output ([pscustomobject]@{success=$false;error_type=$_.Exception.GetType().Name;message='Meshy submission did not complete locally. Check task list before retrying.'} | ConvertTo-Json -Compress)
    exit 1
} finally {
    if ($headers) { $headers.Clear() }
    if ($secureKey) { $secureKey.Dispose() }
    $credential = $null
    $body = $null
}
