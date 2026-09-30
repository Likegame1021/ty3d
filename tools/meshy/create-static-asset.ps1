param(
    [Parameter(Mandatory=$true)][ValidateSet('tool-shed','farm-cart','locust-tree')][string]$Asset
)
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$outputDir = Join-Path $projectRoot ('art\environment\meshy\' + $Asset + '\v001')
$responsePath = Join-Path $outputDir 'generation-created.json'
if (Test-Path -LiteralPath $responsePath) { throw 'Generation already submitted. Reuse its saved task ID.' }
$imagePath = Join-Path $projectRoot ('art\environment\references\style-v002\' + $Asset + '.png')
if (-not (Test-Path -LiteralPath $imagePath -PathType Leaf)) { throw 'Reviewed reference image is missing.' }
$polycounts = @{'tool-shed'=12000;'farm-cart'=6000;'locust-tree'=8000}
$parameters = [ordered]@{
    ai_model='meshy-7.1';model_type='standard';geometry_resolution='standard'
    should_texture=$true;enable_pbr=$true;texture_resolution='2k'
    should_remesh=$true;topology='triangle';target_polycount=$polycounts[$Asset]
    save_pre_remeshed_model=$false;image_enhancement=$false;target_formats=@('glb')
}
New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
[ordered]@{asset=$Asset;image_file=$imagePath;parameters=$parameters;submitted_at=(Get-Date).ToString('o')} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $outputDir 'generation-request.json') -Encoding utf8
$body = @{}
foreach ($key in $parameters.Keys) { $body[$key] = $parameters[$key] }
$body.image_url = 'data:image/png;base64,' + [Convert]::ToBase64String([IO.File]::ReadAllBytes($imagePath))
$secureKey = $null
$headers = $null
try {
    $secureKey = Import-Clixml -LiteralPath (Join-Path $projectRoot '.local\meshy\api-key.clixml')
    $credential = [Net.NetworkCredential]::new('', $secureKey)
    $headers = @{Authorization='Bearer ' + $credential.Password}
    $response = Invoke-WebRequest -Uri 'https://api.meshy.ai/openapi/v1/image-to-3d' -Method Post -Headers $headers -ContentType 'application/json' -Body ($body | ConvertTo-Json -Depth 8 -Compress) -MaximumRedirection 0 -TimeoutSec 120 -SkipHttpErrorCheck -Verbose:$false -Debug:$false
    if ([int]$response.StatusCode -notin @(200,201,202)) {
        [pscustomobject]@{success=$false;http_status=[int]$response.StatusCode;message=($response.Content -replace 'msy_[A-Za-z0-9]+','[REDACTED]')} | ConvertTo-Json -Compress
        exit 1
    }
    $data = $response.Content | ConvertFrom-Json
    if (-not $data.result) { throw 'No task ID in response.' }
    $response.Content | Set-Content -LiteralPath $responsePath -Encoding utf8
    [pscustomobject]@{asset=$Asset;success=$true;task_id=$data.result;output=$responsePath} | ConvertTo-Json -Compress
} catch {
    [pscustomobject]@{success=$false;error_type=$_.Exception.GetType().Name;message='Submission did not complete locally. Query task list before retrying to avoid duplicate charges.'} | ConvertTo-Json -Compress
    exit 1
} finally {
    if ($headers) { $headers.Clear() }
    if ($secureKey) { $secureKey.Dispose() }
    $credential = $null
    $body = $null
}
