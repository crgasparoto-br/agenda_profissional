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
  throw $Message
}

function Assert-Equal {
  param(
    [object]$Expected,
    [object]$Actual,
    [string]$Label
  )
  if ("$Expected" -ne "$Actual") {
    Fail "${Label}: esperado '$Expected', obtido '$Actual'."
  }
}

function Assert-True {
  param(
    [bool]$Condition,
    [string]$Label
  )
  if (-not $Condition) {
    Fail $Label
  }
}

function To-Encoded([string]$Value) {
  return [System.Uri]::EscapeDataString($Value)
}

function Invoke-RestJson {
  param(
    [string]$Method,
    [string]$Uri,
    [hashtable]$Headers,
    [object]$Body = $null
  )
  try {
    if ($null -eq $Body) {
      return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $Headers
    }
    $serialized = if ($Body -is [string]) { $Body } else { $Body | ConvertTo-Json -Depth 20 }
    return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $Headers -Body $serialized
  } catch {
    $responseText = ""
    try {
      $stream = $_.Exception.Response.GetResponseStream()
      if ($stream) {
        $reader = New-Object System.IO.StreamReader($stream)
        $responseText = $reader.ReadToEnd()
      }
    } catch {
      $responseText = ""
    }
    $message = "HTTP erro em $Method $Uri"
    if ($responseText) {
      $message = "$message | body=$responseText"
    }
    throw $message
  }
}

function Get-MinutesToStart([string]$StartsAtIso) {
  $target = [DateTime]::Parse($StartsAtIso).ToUniversalTime()
  $now = [DateTime]::UtcNow
  $deltaMinutes = [Math]::Floor(($target - $now).TotalMinutes)
  return [int]$deltaMinutes
}

$fileMap = Get-EnvMapFromFile -Path "supabase/functions/.env"

$supabaseUrl = Get-ConfigValue -Name "SUPABASE_URL" -FileMap $fileMap
if (-not $supabaseUrl) { $supabaseUrl = Get-ConfigValue -Name "APP_SUPABASE_URL" -FileMap $fileMap }
$serviceRoleKey = Get-ConfigValue -Name "SUPABASE_SERVICE_ROLE_KEY" -FileMap $fileMap
if (-not $serviceRoleKey) { $serviceRoleKey = Get-ConfigValue -Name "APP_SUPABASE_SERVICE_ROLE_KEY" -FileMap $fileMap }
$monitorSecret = Get-ConfigValue -Name "PUNCTUALITY_MONITOR_SECRET" -FileMap $fileMap
$pushDispatcherSecret = Get-ConfigValue -Name "PUNCTUALITY_PUSH_DISPATCHER_SECRET" -FileMap $fileMap
$whatsappDispatcherSecret = Get-ConfigValue -Name "PUNCTUALITY_WHATSAPP_DISPATCHER_SECRET" -FileMap $fileMap
$tenantId = Get-ConfigValue -Name "TEST_TENANT_ID" -FileMap $fileMap
if (-not $tenantId) { $tenantId = Get-ConfigValue -Name "WHATSAPP_DEFAULT_TENANT_ID" -FileMap $fileMap }
$keepData = (Get-ConfigValue -Name "E2E_KEEP_DATA" -FileMap $fileMap -Fallback "false").ToLower() -eq "true"

if (-not $supabaseUrl) { Fail "Variavel SUPABASE_URL/APP_SUPABASE_URL nao encontrada." }
if (-not $serviceRoleKey) { Fail "Variavel SUPABASE_SERVICE_ROLE_KEY/APP_SUPABASE_SERVICE_ROLE_KEY nao encontrada." }
if (-not $monitorSecret) { Fail "Variavel PUNCTUALITY_MONITOR_SECRET nao encontrada." }
if (-not $tenantId) { Fail "Variavel TEST_TENANT_ID (ou WHATSAPP_DEFAULT_TENANT_ID) nao encontrada." }

$restBase = "$supabaseUrl/rest/v1"
$monitorUrl = "$supabaseUrl/functions/v1/punctuality-monitor"
$pushDispatcherUrl = "$supabaseUrl/functions/v1/punctuality-push-dispatcher"
$whatsappDispatcherUrl = "$supabaseUrl/functions/v1/punctuality-whatsapp-dispatcher"

$headersDb = @{
  "apikey" = $serviceRoleKey
  "Authorization" = "Bearer $serviceRoleKey"
  "Accept" = "application/json"
}
$headersDbJson = @{
  "apikey" = $serviceRoleKey
  "Authorization" = "Bearer $serviceRoleKey"
  "Accept" = "application/json"
  "Content-Type" = "application/json"
  "Prefer" = "return=representation"
}
$headersMonitor = @{
  "Content-Type" = "application/json"
  "x-monitor-secret" = $monitorSecret
}

$createdAppointmentId = $null
$testStartedAt = [DateTime]::UtcNow.ToString("o")

try {
  Info "Preparando dados de teste E2E para tenant $tenantId"

  $professionals = Invoke-RestJson -Method Get -Uri "$restBase/professionals?tenant_id=eq.$tenantId&active=eq.true&select=id,user_id,name&limit=1" -Headers $headersDb
  if (-not $professionals -or $professionals.Count -eq 0) { Fail "Nenhum profissional ativo encontrado no tenant." }
  $professional = $professionals[0]

  $services = Invoke-RestJson -Method Get -Uri "$restBase/services?tenant_id=eq.$tenantId&active=eq.true&select=id,name,duration_min&limit=1" -Headers $headersDb
  if (-not $services -or $services.Count -eq 0) { Fail "Nenhum serviço ativo encontrado no tenant." }
  $service = $services[0]

  $clients = Invoke-RestJson -Method Get -Uri "$restBase/clients?tenant_id=eq.$tenantId&select=id,full_name&limit=1" -Headers $headersDb
  $clientId = if ($clients -and $clients.Count -gt 0) { $clients[0].id } else { $null }
  if (-not $clientId) {
    $createdClient = Invoke-RestJson -Method Post -Uri "$restBase/clients" -Headers $headersDbJson -Body @(@{
      tenant_id = $tenantId
      full_name = "Cliente E2E Pontualidade"
      phone = "5511999990000"
    })
    if (-not $createdClient -or $createdClient.Count -eq 0) {
      Fail "Nao foi possivel criar cliente de teste para o E2E."
    }
    $clientId = $createdClient[0].id
  }

  $durationMin = 30
  if ($null -ne $service.duration_min) {
    $durationMin = [int]$service.duration_min
  }
  $createdAppointment = $null
  for ($attempt = 0; $attempt -lt 12; $attempt++) {
    $startAt = [DateTime]::UtcNow.AddHours(2 + ($attempt * 3))
    $endAt = $startAt.AddMinutes([Math]::Max(30, $durationMin))
    $appointmentPayload = @{
      tenant_id = $tenantId
      professional_id = $professional.id
      service_id = $service.id
      client_id = $clientId
      starts_at = $startAt.ToString("o")
      ends_at = $endAt.ToString("o")
      status = "scheduled"
      source = "professional"
    }
    try {
      $createdAppointment = Invoke-RestJson -Method Post -Uri "$restBase/appointments" -Headers $headersDbJson -Body @($appointmentPayload)
      if ($createdAppointment -and $createdAppointment.Count -gt 0) {
        break
      }
    } catch {
      if ($_.Exception.Message -match "appointments_no_overlap|23P01|conflicting key value") {
        continue
      }
      throw
    }
  }
  if (-not $createdAppointment -or $createdAppointment.Count -eq 0) {
    Fail "Falha ao criar appointment de teste sem conflito de horario."
  }
  $createdAppointmentId = $createdAppointment[0].id
  Info "Appointment de teste criado: $createdAppointmentId"

  Info "Cenario 0: sem consentimento nao monitora"
  $noConsentCall = Invoke-RestJson -Method Post -Uri $monitorUrl -Headers $headersMonitor -Body @{
    tenant_id = $tenantId
    source = "e2e_flow_no_consent"
    snapshots = @(
      @{
        appointment_id = $createdAppointmentId
        eta_minutes = 12
      }
    )
  }
  if ($null -ne $noConsentCall.skipped_no_consent) {
    Assert-True -Condition ([int]$noConsentCall.skipped_no_consent -ge 1) -Label "Monitor deveria pular consulta sem consentimento."
  }

  Info "Registrando consentimento ativo para a consulta de teste"
  [void](Invoke-RestJson -Method Post -Uri "$restBase/client_location_consents" -Headers $headersDbJson -Body @(@{
    tenant_id = $tenantId
    client_id = $clientId
    appointment_id = $createdAppointmentId
    consent_status = "granted"
    consent_text_version = "v1"
    source_channel = "e2e_flow"
    granted_at = [DateTime]::UtcNow.ToString("o")
    expires_at = [DateTime]::UtcNow.AddHours(24).ToString("o")
  }))

  $policyRows = Invoke-RestJson -Method Get -Uri "$restBase/delay_policies?tenant_id=eq.$tenantId&professional_id=eq.$($professional.id)&select=id,tempo_maximo_atraso_min,fallback_whatsapp_for_professional" -Headers $headersDb
  if (-not $policyRows -or $policyRows.Count -eq 0) {
    [void](Invoke-RestJson -Method Post -Uri "$restBase/delay_policies" -Headers $headersDbJson -Body @(@{
      tenant_id = $tenantId
      professional_id = $professional.id
      tempo_maximo_atraso_min = 10
      fallback_whatsapp_for_professional = $true
    }))
    $maxDelay = 10
  } else {
    $maxDelay = [int]$policyRows[0].tempo_maximo_atraso_min
    [void](Invoke-RestJson -Method Patch -Uri "$restBase/delay_policies?tenant_id=eq.$tenantId&professional_id=eq.$($professional.id)" -Headers $headersDbJson -Body @{
      fallback_whatsapp_for_professional = $true
    })
  }

  if ($professional.user_id) {
    [void](Invoke-RestJson -Method Patch -Uri "$restBase/profiles?tenant_id=eq.$tenantId&id=eq.$($professional.user_id)" -Headers $headersDbJson -Body @{
      phone = "5511999999999"
    })
  }

  [void](Invoke-RestJson -Method Post -Uri "$restBase/service_locations" -Headers $headersDbJson -Body @(@{
    tenant_id = $tenantId
    professional_id = $professional.id
    name = "Endereco E2E"
    address_line = "Av. Teste, 100"
    city = "Sao Paulo"
    state = "SP"
    postal_code = "01000-000"
    country = "BR"
    latitude = -23.56321
    longitude = -46.65425
    is_active = $true
  }))

  function Send-StableSnapshot([string]$Scenario, [scriptblock]$BuildSnapshot) {
    $snap1 = & $BuildSnapshot
    $body1 = @{
      tenant_id = $tenantId
      source = "e2e_flow_$Scenario"
      snapshots = @($snap1)
    }
    $r1 = Invoke-RestJson -Method Post -Uri $monitorUrl -Headers $headersMonitor -Body $body1
    Start-Sleep -Milliseconds 1200
    $snap2 = & $BuildSnapshot
    $body2 = @{
      tenant_id = $tenantId
      source = "e2e_flow_$Scenario"
      snapshots = @($snap2)
    }
    $r2 = Invoke-RestJson -Method Post -Uri $monitorUrl -Headers $headersMonitor -Body $body2
    return @($r1, $r2)
  }

  function Get-AppointmentState {
    $rows = Invoke-RestJson -Method Get -Uri "$restBase/appointments?tenant_id=eq.$tenantId&id=eq.$createdAppointmentId&select=id,punctuality_status,punctuality_eta_min,punctuality_predicted_delay_min,starts_at" -Headers $headersDb
    if (-not $rows -or $rows.Count -eq 0) { Fail "Appointment de teste nao encontrado." }
    return $rows[0]
  }

  function Get-NotificationCount([string]$Type, [string]$Channel) {
    $startEscaped = To-Encoded($testStartedAt)
    $url = "$restBase/notification_log?tenant_id=eq.$tenantId&appointment_id=eq.$createdAppointmentId&type=eq.$Type&channel=eq.$Channel&created_at=gte.$startEscaped&select=id"
    $rows = Invoke-RestJson -Method Get -Uri $url -Headers $headersDb
    if (-not $rows) { return 0 }
    return [int]$rows.Count
  }

  Info "Cenario 1: NO_DATA"
  [void](Send-StableSnapshot -Scenario "no_data" -BuildSnapshot {
    return @{
      appointment_id = $createdAppointmentId
    }
  })
  $stateNoData = Get-AppointmentState
  Assert-Equal -Expected "no_data" -Actual $stateNoData.punctuality_status -Label "Status NO_DATA"

  Info "Cenario 2: LATE_OK"
  [void](Send-StableSnapshot -Scenario "late_ok" -BuildSnapshot {
    $st = Get-AppointmentState
    $minutesToStart = Get-MinutesToStart -StartsAtIso $st.starts_at
    $eta = [Math]::Max(0, $minutesToStart + [Math]::Max(1, $maxDelay - 1))
    return @{
      appointment_id = $createdAppointmentId
      eta_minutes = $eta
    }
  })
  $stateLateOk = Get-AppointmentState
  Assert-Equal -Expected "late_ok" -Actual $stateLateOk.punctuality_status -Label "Status LATE_OK"
  $lateOkInAppBefore = Get-NotificationCount -Type "punctuality_late_ok" -Channel "in_app"
  $lateOkPushBefore = Get-NotificationCount -Type "punctuality_late_ok" -Channel "push"
  $lateOkWaBefore = Get-NotificationCount -Type "punctuality_late_ok" -Channel "whatsapp"
  Assert-True -Condition ($lateOkInAppBefore -ge 1) -Label "Notificacao in_app late_ok nao gerada."
  Assert-True -Condition ($lateOkPushBefore -ge 1) -Label "Notificacao push late_ok nao gerada."
  Assert-True -Condition ($lateOkWaBefore -ge 1) -Label "Notificacao whatsapp late_ok nao gerada."

  Info "Cenario 3: LATE_CRITICAL"
  [void](Send-StableSnapshot -Scenario "late_critical" -BuildSnapshot {
    $st = Get-AppointmentState
    $minutesToStart = Get-MinutesToStart -StartsAtIso $st.starts_at
    $eta = [Math]::Max(0, $minutesToStart + $maxDelay + 20)
    return @{
      appointment_id = $createdAppointmentId
      eta_minutes = $eta
    }
  })
  $stateLateCritical = Get-AppointmentState
  Assert-Equal -Expected "late_critical" -Actual $stateLateCritical.punctuality_status -Label "Status LATE_CRITICAL"
  $lateCriticalInAppBefore = Get-NotificationCount -Type "punctuality_late_critical" -Channel "in_app"
  $lateCriticalPushBefore = Get-NotificationCount -Type "punctuality_late_critical" -Channel "push"
  $lateCriticalWaBefore = Get-NotificationCount -Type "punctuality_late_critical" -Channel "whatsapp"
  Assert-True -Condition ($lateCriticalInAppBefore -ge 1) -Label "Notificacao in_app late_critical nao gerada."
  Assert-True -Condition ($lateCriticalPushBefore -ge 1) -Label "Notificacao push late_critical nao gerada."
  Assert-True -Condition ($lateCriticalWaBefore -ge 1) -Label "Notificacao whatsapp late_critical nao gerada."

  Info "Cenario 4: Retorno ON_TIME"
  [void](Send-StableSnapshot -Scenario "on_time" -BuildSnapshot {
    $st = Get-AppointmentState
    $minutesToStart = Get-MinutesToStart -StartsAtIso $st.starts_at
    $eta = [Math]::Max(0, $minutesToStart - 5)
    return @{
      appointment_id = $createdAppointmentId
      eta_minutes = $eta
    }
  })
  $stateOnTime = Get-AppointmentState
  Assert-Equal -Expected "on_time" -Actual $stateOnTime.punctuality_status -Label "Status ON_TIME"
  $onTimeInApp = Get-NotificationCount -Type "punctuality_on_time" -Channel "in_app"
  Assert-True -Condition ($onTimeInApp -ge 1) -Label "Notificacao in_app on_time nao gerada."

  Info "Cenario 5: Dedupe/Throttling (retorno rapido para LATE_CRITICAL)"
  [void](Send-StableSnapshot -Scenario "late_critical_dedupe" -BuildSnapshot {
    $st = Get-AppointmentState
    $minutesToStart = Get-MinutesToStart -StartsAtIso $st.starts_at
    $eta = [Math]::Max(0, $minutesToStart + $maxDelay + 25)
    return @{
      appointment_id = $createdAppointmentId
      eta_minutes = $eta
    }
  })
  $stateLateCriticalAgain = Get-AppointmentState
  Assert-Equal -Expected "late_critical" -Actual $stateLateCriticalAgain.punctuality_status -Label "Status LATE_CRITICAL (dedupe)"
  $lateCriticalInAppAfter = Get-NotificationCount -Type "punctuality_late_critical" -Channel "in_app"
  $lateCriticalPushAfter = Get-NotificationCount -Type "punctuality_late_critical" -Channel "push"
  $lateCriticalWaAfter = Get-NotificationCount -Type "punctuality_late_critical" -Channel "whatsapp"
  Assert-Equal -Expected $lateCriticalInAppBefore -Actual $lateCriticalInAppAfter -Label "Dedupe in_app late_critical"
  Assert-Equal -Expected $lateCriticalPushBefore -Actual $lateCriticalPushAfter -Label "Dedupe push late_critical"
  Assert-Equal -Expected $lateCriticalWaBefore -Actual $lateCriticalWaAfter -Label "Dedupe whatsapp late_critical"

  $dispatchResult = [ordered]@{}
  if ($pushDispatcherSecret) {
    Info "Disparando push-dispatcher"
    $pushDispatch = Invoke-RestJson -Method Post -Uri $pushDispatcherUrl -Headers @{
      "Content-Type" = "application/json"
      "x-push-dispatcher-secret" = $pushDispatcherSecret
    } -Body @{
      tenant_id = $tenantId
      limit = 50
    }
    $dispatchResult.push = $pushDispatch
  }

  if ($whatsappDispatcherSecret) {
    Info "Disparando whatsapp-dispatcher"
    $waDispatch = Invoke-RestJson -Method Post -Uri $whatsappDispatcherUrl -Headers @{
      "Content-Type" = "application/json"
      "x-whatsapp-dispatcher-secret" = $whatsappDispatcherSecret
    } -Body @{
      tenant_id = $tenantId
      limit = 50
    }
    $dispatchResult.whatsapp = $waDispatch
  }

  $result = [ordered]@{
    ok = $true
    tenant_id = $tenantId
    appointment_id = $createdAppointmentId
    scenarios = @{
      no_data = $stateNoData.punctuality_status
      late_ok = $stateLateOk.punctuality_status
      late_critical = $stateLateCritical.punctuality_status
      on_time = $stateOnTime.punctuality_status
      late_critical_dedupe = $stateLateCriticalAgain.punctuality_status
    }
    notification_counts = @{
      late_ok = @{
        in_app = $lateOkInAppBefore
        push = $lateOkPushBefore
        whatsapp = $lateOkWaBefore
      }
      late_critical = @{
        in_app_before = $lateCriticalInAppBefore
        in_app_after = $lateCriticalInAppAfter
        push_before = $lateCriticalPushBefore
        push_after = $lateCriticalPushAfter
        whatsapp_before = $lateCriticalWaBefore
        whatsapp_after = $lateCriticalWaAfter
      }
      on_time = @{
        in_app = $onTimeInApp
      }
    }
    dispatch = $dispatchResult
  }

  Write-Host ""
  Write-Host "[OK] E2E de pontualidade concluido com sucesso." -ForegroundColor Green
  $result | ConvertTo-Json -Depth 20
}
finally {
  if ($createdAppointmentId -and -not $keepData) {
    Info "Limpando appointment de teste $createdAppointmentId"
    try {
      [void](Invoke-RestJson -Method Delete -Uri "$restBase/appointments?tenant_id=eq.$tenantId&id=eq.$createdAppointmentId" -Headers $headersDbJson)
    } catch {
      Write-Host "[WARN] Falha ao limpar appointment de teste: $($_.Exception.Message)"
    }
  }
}
