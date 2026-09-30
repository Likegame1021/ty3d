param(
    [Parameter(Mandatory=$true)][ValidateSet('balance','rigging','animations','animations/library')][string]$Endpoint,
    [ValidateSet('GET','POST')][string]$Method = 'GET',
    [string]$BodyPath,
    [Parameter(Mandatory=$true)][string]$OutputPath,
    [string]$Search
)
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$outputFile = [IO.Path]::GetFullPath($OutputPath)
if (-not $outputFile.StartsWith($projectRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Output must be inside the project.' }
if ($Method -eq 'POST' -and (Test-Path -LiteralPath $outputFile)) { throw 'Submission result already exists. Reuse its task ID.' }
$uri = 'https://api.meshy.ai/openapi/v1/' + $Endpoint
if ($Search) { $uri += '?search=' + [Uri]::EscapeDataString($Search) }
$secureKey = $null
$headers = $null
try {
    $secureKey = Import-Clixml -LiteralPath (Join-Path $projectRoot '.local\meshy\api-key.clixml')
    $credential = [Net.NetworkCredential]::new('', $secureKey)
    $headers = @{Authorization='Bearer ' + $credential.Password}
    $options = @{Uri=$uri;Method=$Method;Headers=$headers;MaximumRedirection=0;TimeoutSec=60;SkipHttpErrorCheck=$true;Verbose=$false;Debug=$false}
    if ($Method -eq 'POST') {
        $options.ContentType = 'application/json'
        $options.Body = Get-Content -LiteralPath $BodyPath -Encoding utf8 -Raw
        $null = $options.Body | ConvertFrom-Json
    }
    $response = Invoke-WebRequest @options
    if ([int]$response.StatusCode -notin @(200,201,202)) {
        [pscustomobject]@{success=$false;http_status=[int]$response.StatusCode;message=($response.Content -replace 'msy_[A-Za-z0-9]+','[REDACTED]')} | ConvertTo-Json -Compress
        exit 1
    }
    $data = $response.Content | ConvertFrom-Json
    New-Item -ItemType Directory -Path (Split-Path -Parent $outputFile) -Force | Out-Null
    $response.Content | Set-Content -LiteralPath $outputFile -Encoding utf8
    $taskId = if ($Method -eq 'POST') { $data.result } else { $null }
    [pscustomobject]@{success=$true;endpoint=$Endpoint;task_id=$taskId;output=$outputFile} | ConvertTo-Json -Compress
} catch {
    [pscustomobject]@{success=$false;error_type=$_.Exception.GetType().Name;message='Request did not complete locally; query existing tasks before retrying a POST.'} | ConvertTo-Json -Compress
    exit 1
} finally {
    if ($headers) { $headers.Clear() }
    if ($secureKey) { $secureKey.Dispose() }
    $credential = $null
}
