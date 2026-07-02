<#  kb_ingest_demo.ps1 -----------------------------------------------------------
  A runnable demonstration of the FILE-PROCESSING CORE of Update-StudyKB.ps1.
  Production is Update-StudyKB.ps1, which ATTACHES to classic Outlook via COM and
  reads the study folder. This runs the SAME core — sanitize the HTML, write one
  structured read-only note, watermark it by (synthetic) Outlook EntryID, and keep
  an idempotent seen-set — over the _Inbox drop folder, so you can watch the
  knowledge base fill. Same PowerShell, no GUI.
---------------------------------------------------------------------------- #>
param([string]$Root = '.')
$Inbox = Join-Path $Root '_Inbox'
$Notes = Join-Path $Root 'Notes'
$Proc  = Join-Path $Inbox '_processed'
$State = Join-Path $Root '.state'
$SeenFile  = Join-Path $State 'seen.json'
$null  = New-Item -ItemType Directory -Force -Path $Inbox, $Notes, $Proc, $State

function HtmlEsc([string]$s){ [System.Net.WebUtility]::HtmlEncode($s) }

function Sanitize-Html([string]$h){           # mirrors Update-StudyKB.ps1 Sanitize-Html
  if (-not $h){ return $h }
  $h = $h -replace '(?is)<script.*?</script>',''
  $h = $h -replace '(?is)<style.*?</style>',''
  $h = $h -replace '(?is)<(iframe|object|embed).*?</\1>',''
  $h = $h -replace '(?i)<(script|style|iframe|object|embed|link|meta|base)\b[^>]*>',''
  $h = $h -replace '(?i)\son\w+\s*=\s*("[^"]*"|''[^'']*''|[^\s>]+)',''
  $h = $h -replace '(?i)(src|background)\s*=\s*("|'')\s*https?:','$1=$2blocked-remote:'
  $h = $h -replace '(?i)javascript:','blocked:'
  return $h
}

function Short-Hash([string]$s){              # mirrors Update-StudyKB.ps1 Short-Hash
  $md5 = [System.Security.Cryptography.MD5]::Create()
  $b   = $md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($s))
  -join ($b[0..3] | ForEach-Object { $_.ToString('x2') })
}

$seen = New-Object System.Collections.Generic.HashSet[string]
if (Test-Path $SeenFile){ try { foreach ($id in (Get-Content -Raw $SeenFile | ConvertFrom-Json)){ [void]$seen.Add([string]$id) } } catch {} }

$added = 0; $skipped = 0
Get-ChildItem $Inbox -File | Where-Object { $_.Extension -in '.html','.txt','.md' } | Sort-Object Name | ForEach-Object {
  $f = $_; $raw = Get-Content -Raw $f.FullName
  # synthetic Outlook EntryID (production: the real MailItem.EntryID)
  $sha = [System.Security.Cryptography.SHA1]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($f.Name))
  $entryid = '0000000' + (-join ($sha[0..15] | ForEach-Object { $_.ToString('X2') }))
  if ($seen.Contains($entryid)){ Write-Host ("    . skip (already filed): {0}" -f $f.Name); $skipped++; return }
  $mt   = [regex]::Match($raw,'(?is)<title[^>]*>(.*?)</title>')
  $subj = if ($mt.Success){ ([regex]::Replace($mt.Groups[1].Value,'<[^>]+>','')).Trim() } else { $f.BaseName }
  $mf   = [regex]::Match($raw,'(?i)<meta\s+name=["'']from["'']\s+content=["''](.*?)["'']')
  $from = if ($mf.Success){ $mf.Groups[1].Value } else { 'study ops' }
  $slug = (($subj -replace '[^\w\- ]','').Trim() -replace '\s+','_'); if ($slug.Length -gt 60){ $slug = $slug.Substring(0,60) }
  $when = Get-Date '2026-06-22 09:14'
  $note = ('{0}__{1}__{2}.html' -f $when.ToString('yyyyMMdd_HHmmss'), $slug, (Short-Hash $entryid))
  $body = Sanitize-Html $raw
  $html = @"
<!doctype html><meta charset="utf-8"><title>$(HtmlEsc $subj)</title>
<body style="font-family:Segoe UI,Arial,sans-serif;max-width:820px;margin:24px auto;padding:0 16px">
<h2>$(HtmlEsc $subj)</h2>
<p style="color:#555"><b>From:</b> $(HtmlEsc $from) &nbsp;|&nbsp; <b>Captured:</b> $($when.ToString('yyyy-MM-dd HH:mm'))</p><hr>
$body
<hr><p style="color:#888;font-size:12px">Study Knowledge Base - captured from email. Operations content only.</p></body>
"@
  $dest = Join-Path $Notes $note
  Set-Content -Path $dest -Value $html -Encoding UTF8
  Set-ItemProperty -Path $dest -Name IsReadOnly -Value $true
  [void]$seen.Add($entryid)
  Move-Item $f.FullName (Join-Path $Proc $f.Name) -Force
  Write-Host ("    + Notes\{0}" -f $note)
  Write-Host ("        EntryID {0}...  read-only  sanitized" -f $entryid.Substring(0,18))
  $added++
}
$json = @($seen | Sort-Object) | ConvertTo-Json
if (-not $json) { $json = '[]' }
Set-Content -Path $SeenFile -Value $json
Write-Host ("[StudyKB] done - {0} filed, {1} skipped - seen-set now {2} - operations-only" -f $added, $skipped, $seen.Count)
