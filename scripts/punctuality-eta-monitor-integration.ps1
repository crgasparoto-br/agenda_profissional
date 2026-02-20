param()

$ErrorActionPreference = "Stop"

function Get-EnvMapFromFile {
  param([string]$Path)
  $map = @{}
  if (-not (Test-Path $Path)) { return $map }
  Get-Content $Path | ForEach-Object {
    if ($_ -match '^[A-Za-z0-9_]+=') {
      $parts = $_ -split '=', 2
      $map[$parts[0]] = $parts[1]
    }
  }
  return $map
}

function Get-ConfigValue {
  param(
    [string]$Name,
    [hashtable]$FileMap,
    [string]$Fallback = ""
  )
  $envValue = [Environment]::GetEnvironmentVariable($Name)
  if ($envValue) { return $envValue }
  if ($FileMap.ContainsKey($Name) -and $FileMap[$Name]) { return $FileMap[$Name] }
  return $Fallback
}

function Info([string]$Message) {
  Write-Host ""
  Write-Host "[INFO] $Message"
}

function Fail([string]$Message) {
  Write-Host ""
  Write-Host "[ERRO] $Message" -ForegroundColor Red
  exit 1
}

$fileMap = Get-EnvMapFromFile -Path "supabase/functions/.env"

$supabaseUrl = [Environment]::GetEnvironmentVariable("APP_SUPABASE_URL")
if (-not $supabaseUrl) { $supabaseUrl = [Environment]::GetEnvironmentVariable("SUPABASE_URL") }
if (-not $supabaseUrl -and $fileMap.ContainsKey("APP_SUPABASE_URL")) { $supabaseUrl = $fileMap["APP_SUPABASE_URL"] }
if (-not $supabaseUrl -and $fileMap.ContainsKey("SUPABASE_URL")) { $supabaseUrl = $fileMap["SUPABASE_URL"] }

$serviceRoleKey = [Environment]::GetEnvironmentVariable("APP_SUPABASE_SERVICE_ROLE_KEY")
if (-not $serviceRoleKey) { $serviceRoleKey = [Environment]::GetEnvironmentVariable("SUPABASE_SERVICE_ROLE_KEY") }
if (-not $serviceRoleKey -and $fileMap.ContainsKey("APP_SUPABASE_SERVICE_ROLE_KEY")) { $serviceRoleKey = $fileMap["APP_SUPABASE_SERVICE_ROLE_KEY"] }
if (-not $serviceRoleKey -and $fileMap.ContainsKey("SUPABASE_SERVICE_ROLE_KEY")) { $serviceRoleKey = $fileMap["SUPABASE_SERVICE_ROLE_KEY"] }

$monitorSecret = Get-ConfigValue -Name "PUNCTUALITY_MONITOR_SECRET" -FileMap $fileMap
$tenantId = Get-ConfigValue -Name "TEST_TENANT_ID" -FileMap $fileMap
if (-not $tenantId) { $tenantId = Get-ConfigValue -Name "WHATSAPP_DEFAULT_TENANT_ID" -FileMap $fileMap }
$appointmentId = Get-ConfigValue -Name "TEST_APPOINTMENT_ID" -FileMap $fileMap
$clientLat = [double](Get-ConfigValue -Name "TEST_CLIENT_LAT" -FileMap $fileMap -Fallback "-23.55052")
$clientLng = [double](Get-ConfigValue -Name "TEST_CLIENT_LNG" -FileMap $fileMap -Fallback "-46.633308")

if (-not $supabaseUrl) { Fail "Variavel SUPABASE_URL/APP_SUPABASE_URL nao encontrada." }
if (-not $serviceRoleKey) { Fail "Variavel SUPABASE_SERVICE_ROLE_KEY/APP_SUPABASE_SERVICE_ROLE_KEY nao encontrada." }
if (-not $monitorSecret) { Fail "Variavel PUNCTUALITY_MONITOR_SECRET nao encontrada." }
if (-not $tenantId) { Fail "Variavel TEST_TENANT_ID (ou WHATSAPP_DEFAULT_TENANT_ID) nao encontrada." }
if (-not $appointmentId) { Fail "Variavel TEST_APPOINTMENT_ID nao encontrada." }

$startedAt = [DateTime]::UtcNow.ToString("o")
$fnUrl = "$supabaseUrl/functions/v1/punctuality-monitor"
$restBase = "$supabaseUrl/rest/v1"

Info "Executando teste para tenant $tenantId e appointment $appointmentId"

$headersFn = @{
  "Content-Type" = "application/json"
  "x-monitor-secret" = $monitorSecret
}

function Build-Body([string]$CapturedAt) {
  return @{
    tenant_id = $tenantId
    appointment_id = $appointmentId
    source = "integration_eta_monitor"
    snapshots = @(
      @{
        appointment_id = $appointmentId
        captured_at = $CapturedAt
        client_lat = $clientLat
        client_lng = $clientLng
      }
    )
  } | ConvertTo-Json -Depth 8
}

Info "Disparando 2 chamadas no punctuality-monitor sem eta_minutes (forca ETA provider -> monitor)"
$capturedAt1 = [DateTime]::UtcNow.ToString("o")
$firstRun = Invoke-RestMethod -Method Post -Uri $fnUrl -Headers $headersFn -Body (Build-Body -CapturedAt $capturedAt1)
Start-Sleep -Seconds 1
$capturedAt2 = [DateTime]::UtcNow.ToString("o")
$secondRun = Invoke-RestMethod -Method Post -Uri $fnUrl -Headers $headersFn -Body (Build-Body -CapturedAt $capturedAt2)

Info "Consultando snapshots mais recentes"
$headersDb = @{
  "apikey" = $serviceRoleKey
  "Authorization" = "Bearer $serviceRoleKey"
  "Accept" = "application/json"
}
$startedEscaped = [System.Uri]::EscapeDataString($startedAt)
$snapshotsUrl = "$restBase/appointment_eta_snapshots?tenant_id=eq.$tenantId&appointment_id=eq.$appointmentId&captured_at=gte.$startedEscaped&select=id,captured_at,eta_minutes,provider,traffic_level,predicted_arrival_delay,status&order=captured_at.desc&limit=10"
$snapshots = Invoke-RestMethod -Method Get -Uri $snapshotsUrl -Headers $headersDb

if (-not $snapshots -or $snapshots.Count -eq 0) {
  Fail "Nenhum snapshot novo encontrado apos o disparo."
}

$snapshotOk = $snapshots | Where-Object { $_.provider -and $_.eta_minutes -ne $null } | Select-Object -First 1
if (-not $snapshotOk) {
  Fail "Snapshots gravados sem provider/eta_minutes. Verifique PUNCTUALITY_ETA_PROVIDER e service_locations."
}

Info "Consultando estado atual da consulta em appointments"
$appointmentUrl = "$restBase/appointments?tenant_id=eq.$tenantId&id=eq.$appointmentId&select=id,punctuality_status,punctuality_eta_min,punctuality_predicted_delay_min,punctuality_last_calculated_at"
$appointmentRows = Invoke-RestMethod -Method Get -Uri $appointmentUrl -Headers $headersDb
if (-not $appointmentRows -or $appointmentRows.Count -eq 0) {
  Fail "Nao foi possivel ler a consulta em appointments."
}

$result = [ordered]@{
  first_run = $firstRun
  second_run = $secondRun
  snapshot_validado = $snapshotOk
  appointment = $appointmentRows[0]
}

Write-Host ""
Write-Host "[OK] Teste de integracao ETA -> monitor concluido." -ForegroundColor Green
$result | ConvertTo-Json -Depth 10
