<#  Update-Smartsheet.ps1  ----------------------------------------------------
  Push operational status from a CSV into a Smartsheet tracker, IDEMPOTENTLY,
  with NO Smartsheet GUI hunting. The ONLY Smartsheet UI step is generating the
  API token once (Account > Apps & Integrations > API Access > Generate). After
  that everything is the API:
     * find the sheet BY NAME            (no copying IDs from the URL)
     * map columns BY TITLE              (no copying column IDs)
     * upsert rows by a stable key       (re-run-safe, never duplicates)
     * ops-only allowlist guard          (the in-code PHI boundary)

  The Windows companion to the SHEETLINK %ss_* SAS / ss_companion.R helpers (use
  those inside EG / R pipelines; use this standalone on the laptop). Token comes
  from $env:SMARTSHEET_TOKEN and is NEVER logged. Windows PowerShell 5.1+.

  Example:
    setx SMARTSHEET_TOKEN "xxxxx"     # once, in a normal terminal (or use a secret store)
    .\Update-Smartsheet.ps1 -SheetName "CP-101 Deliverables" -CsvPath .\status.csv `
        -KeyColumn "Deliverable" -AllowColumns "Deliverable","Status","% Complete","Owner","Due"
  CSV headers MUST equal the Smartsheet column titles; one of them is -KeyColumn.
  Ops content only: never push PHI / subject-level / unblinded / reported clinical numbers.
--------------------------------------------------------------------------- #>
param(
  [Parameter(Mandatory)][string]   $SheetName,
  [Parameter(Mandatory)][string]   $CsvPath,
  [Parameter(Mandatory)][string]   $KeyColumn,
  [Parameter(Mandatory)][string[]] $AllowColumns,         # ops-only allowlist (PHI boundary)
  [switch] $DryRun,                                       # preview the upsert; send nothing
  [string] $Token   = $env:SMARTSHEET_TOKEN,
  [string] $BaseUrl = "https://api.smartsheet.com/2.0"
)
$ErrorActionPreference = 'Stop'
if (-not $Token) { throw "Set `$env:SMARTSHEET_TOKEN first (Account > Apps & Integrations > API Access). Never hard-code or log it." }
$Headers = @{ Authorization = "Bearer $Token" }            # token lives only here; never written out

function Invoke-SS([string]$Method,[string]$Path,[string]$BodyJson){
  for ($try = 1; $try -le 5; $try++){
    try {
      $p = @{ Method=$Method; Uri="$BaseUrl$Path"; Headers=$Headers; ContentType='application/json' }
      if ($BodyJson) { $p.Body = $BodyJson }
      return Invoke-RestMethod @p
    } catch {
      $resp = $_.Exception.Response
      $code = if ($resp) { [int]$resp.StatusCode } else { 0 }
      if ($code -eq 429 -or $code -ge 500) { Start-Sleep -Seconds ([math]::Pow(2,$try)); continue }  # backoff
      throw
    }
  }
  throw "Smartsheet API failed after retries: $Method $Path"
}
function To-JsonArray($items){                              # always emit a JSON array (even for 1 item)
  if (-not $items -or @($items).Count -eq 0) { return '[]' }
  '[' + ((@($items) | ForEach-Object { $_ | ConvertTo-Json -Depth 10 -Compress }) -join ',') + ']'
}

# 1) resolve the sheet by NAME ------------------------------------------------
$sheets = (Invoke-SS 'GET' '/sheets' $null).data
$sheet  = $sheets | Where-Object { $_.name -eq $SheetName } | Select-Object -First 1
if (-not $sheet) { throw "Sheet '$SheetName' not found. Sheets you can see: $((@($sheets.name)) -join ', ')" }
$full = Invoke-SS 'GET' "/sheets/$($sheet.id)" $null

# 2) column TITLE -> id -------------------------------------------------------
$colId = @{}; foreach ($c in $full.columns) { $colId[$c.title] = $c.id }
if (-not $colId.ContainsKey($KeyColumn)) { throw "Key column '$KeyColumn' is not on the sheet." }

# 3) ops-only allowlist guard (the PHI boundary) -----------------------------
$csv = @(Import-Csv $CsvPath)
if (-not $csv.Count) { Write-Host "No rows in $CsvPath; nothing to do."; return }
$incoming = ($csv | Select-Object -First 1).psobject.Properties.Name
$bad = $incoming | Where-Object { $_ -notin $AllowColumns }
if ($bad) { throw "BLOCKED: CSV has non-allowlisted column(s): $($bad -join ', '). Only add NON-sensitive operational fields to -AllowColumns." }
foreach ($col in $AllowColumns) { if (-not $colId.ContainsKey($col)) { throw "Allowlisted column '$col' not found on the sheet." } }

# 4) existing rows: key value (TEXT) -> rowId --------------------------------
$keyColId = $colId[$KeyColumn]; $existing = @{}
foreach ($r in $full.rows) {
  $kc = $r.cells | Where-Object { $_.columnId -eq $keyColId } | Select-Object -First 1
  if ($kc -and $null -ne $kc.value) { $existing["$($kc.value)"] = $r.id }     # cast to string = text-exact key
}

# 5) split into update (PUT) and add (POST) ----------------------------------
$toUpdate = @(); $toAdd = @()
foreach ($row in $csv) {
  $cells = foreach ($col in $AllowColumns) { $v = [string]$row.$col; if ($v -ne '') { @{ columnId = $colId[$col]; value = $v } } }  # skip empties: leave the cell untouched, never write a blank
  $k = "$($row.$KeyColumn)"
  if ($existing.ContainsKey($k)) { $toUpdate += @{ id = $existing[$k]; cells = @($cells) } }
  else                           { $toAdd    += @{ cells = @($cells); toBottom = $true } }
}

# 6) send in batches of <=500 ------------------------------------------------
function Send-Rows([string]$Method,$Rows){
  $n = 0; $Rows = @($Rows)
  for ($i = 0; $i -lt $Rows.Count; $i += 500) {
    $chunk = @($Rows[$i..([math]::Min($i+499, $Rows.Count-1))])
    Invoke-SS $Method "/sheets/$($sheet.id)/rows" (To-JsonArray $chunk) | Out-Null
    $n += $chunk.Count
  }
  $n
}
if ($DryRun) {
  Write-Host ("DRY RUN '{0}': would update {1} row(s), add {2} (idempotent on key '{3}') - nothing sent." -f $SheetName, @($toUpdate).Count, @($toAdd).Count, $KeyColumn)
  return
}
$u = Send-Rows 'PUT'  $toUpdate
$a = Send-Rows 'POST' $toAdd
Write-Host ("Smartsheet '{0}': {1} row(s) updated, {2} added (idempotent on key '{3}')." -f $SheetName, $u, $a, $KeyColumn)
