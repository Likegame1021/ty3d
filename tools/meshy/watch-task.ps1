param(
    [Parameter(Mandatory=$true)][ValidateSet('image-to-3d','multi-image-to-3d','rigging','animations')][string]$Kind,
    [Parameter(Mandatory=$true)][ValidatePattern('^[a-zA-Z0-9-]+$')][string]$TaskId,
    [Parameter(Mandatory=$true)][string]$OutputDirectory
)
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$outputDir = [IO.Path]::GetFullPath($OutputDirectory)
if (-not $outputDir.StartsWith($projectRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Output must stay inside the project.' }
New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
$secureKey = $null
$headers = $null
try {
    $secureKey = Import-Clixml -LiteralPath (Join-Path $projectRoot '.local\meshy\api-key.clixml')
    $credential = [Net.NetworkCredential]::new('', $secureKey)
    $headers = @{Authorization='Bearer ' + $credential.Password}
    $lastProgress = ''
    for ($attempt=0; $attempt -lt 90; $attempt++) {
        $response = Invoke-WebRequest -Uri ('https://api.meshy.ai/openapi/v1/' + $Kind + '/' + $TaskId) -Headers $headers -Method Get -MaximumRedirection 0 -TimeoutSec 45 -SkipHttpErrorCheck -Verbose:$false -Debug:$false
        if ([int]$response.StatusCode -ne 200) { throw ('Task query returned HTTP ' + [int]$response.StatusCode) }
        $data = $response.Content | ConvertFrom-Json
        $response.Content | Set-Content -LiteralPath (Join-Path $outputDir ($Kind + '-task.json')) -Encoding utf8
        $progressKey = [string]$data.status + ':' + [string]$data.progress
        if ($progressKey -ne $lastProgress) {
            [pscustomobject]@{kind=$Kind;task_id=$TaskId;status=$data.status;progress=$data.progress;credits=$data.consumed_credits} | ConvertTo-Json -Compress
            $lastProgress = $progressKey
        }
        if ($data.status -eq 'SUCCEEDED') {
            $downloads = [ordered]@{}
            if ($data.model_urls.glb) { $downloads['model.glb'] = $data.model_urls.glb }
            if ($data.model_urls.pre_remeshed_glb) { $downloads['high-poly.glb'] = $data.model_urls.pre_remeshed_glb }
            if ($data.thumbnail_url) { $downloads['preview.png'] = $data.thumbnail_url }
            if ($data.result.rigged_character_glb_url) { $downloads['rigged.glb'] = $data.result.rigged_character_glb_url }
            if ($data.result.basic_animations.walking_glb_url) { $downloads['walk.glb'] = $data.result.basic_animations.walking_glb_url }
            if ($data.result.basic_animations.running_glb_url) { $downloads['run.glb'] = $data.result.basic_animations.running_glb_url }
            if ($data.result.animation_glb_url) { $downloads['animations.glb'] = $data.result.animation_glb_url }
            foreach ($name in $downloads.Keys) {
                $assetUri = [Uri]$downloads[$name]
                if ($assetUri.Scheme -ne 'https') { throw 'Asset download must use HTTPS.' }
                $destination = Join-Path $outputDir $name
                # Signed asset URLs are downloaded WITHOUT the API Authorization header.
                Invoke-WebRequest -Uri $assetUri.AbsoluteUri -OutFile $destination -TimeoutSec 180 -Verbose:$false -Debug:$false
                [pscustomobject]@{downloaded=$name;bytes=(Get-Item -LiteralPath $destination).Length} | ConvertTo-Json -Compress
            }
            exit 0
        }
        if ($data.status -in @('FAILED','CANCELED')) {
            [pscustomobject]@{status=$data.status;error=([string]$data.task_error.message -replace 'msy_[A-Za-z0-9]+','[REDACTED]')} | ConvertTo-Json -Compress
            exit 1
        }
        Start-Sleep -Seconds 20
    }
    Write-Output 'Task still pending after observation window. Saved task ID is safe to query again.'
    exit 2
} catch {
    [pscustomobject]@{success=$false;error_type=$_.Exception.GetType().Name;message=($_.Exception.Message -replace 'msy_[A-Za-z0-9]+','[REDACTED]')} | ConvertTo-Json -Compress
    exit 1
} finally {
    if ($headers) { $headers.Clear() }
    if ($secureKey) { $secureKey.Dispose() }
    $credential = $null
}
