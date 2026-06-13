param(
  [string]$Query = 'london, for',
  [string]$Type = 'DESTINATION'
)

$ErrorActionPreference = 'Stop'

function Set-EnvFromFile {
  param([string]$Path)

  if (-not (Test-Path $Path)) {
    throw "Missing .env file at $Path"
  }

  Get-Content $Path | ForEach-Object {
    $line = $_.Trim()
    if (-not $line -or $line.StartsWith('#')) {
      return
    }

    $parts = $line -split '=', 2
    if ($parts.Count -ne 2) {
      return
    }

    $name = $parts[0].Trim()
    $value = $parts[1].Trim()

    if ($name) {
      Set-Item "Env:$name" $value
    }
  }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$envFile = Join-Path $repoRoot '.env'
Set-EnvFromFile -Path $envFile

$baseUrl = if ($env:MCP_BASE_URL) { $env:MCP_BASE_URL.TrimEnd('/') } else { 'https://mcp.routestack.ai' }
$memberToken = $env:MCP_MEMBER_TOKEN
$username = $env:MCP_USERNAME
$password = $env:MCP_PASSWORD

if ($memberToken -eq 'REPLACE_WITH_MEMBER_JWT') {
  $memberToken = $null
}

if (-not $memberToken) {
  if (-not $username -or -not $password) {
    throw 'Set MCP_MEMBER_TOKEN or provide MCP_USERNAME and MCP_PASSWORD in .env.'
  }

  $loginBody = @{ username = $username; password = $password } | ConvertTo-Json -Compress
  $loginResponse = curl.exe -s -X POST "$baseUrl/mcp/auth/login" `
    -H 'Content-Type: application/json' `
    -d $loginBody

  $loginJson = $loginResponse | ConvertFrom-Json
  $memberToken = $loginJson.token

  if (-not $memberToken) {
    $memberToken = $loginJson.accessToken
  }

  if (-not $memberToken) {
    throw 'Login succeeded but no token field was returned.'
  }
}

$requestBody = @{ type = $Type; query = $Query } | ConvertTo-Json -Compress

Write-Host "POST $baseUrl/mcp/hotel/search-destinations"
Write-Host "Request body: $requestBody"

curl.exe -s -X POST "$baseUrl/mcp/hotel/search-destinations" `
  -H "Authorization: Bearer $memberToken" `
  -H 'Content-Type: application/json' `
  -d $requestBody