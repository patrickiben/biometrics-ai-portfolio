<#  Update-StudyKB.ps1  -------------------------------------------------------
  Build the Study Knowledge Base wiki from study email — AUTOMATICALLY, for the
  whole study, with NO Power Automate flow, NO SharePoint web UI, NO Copilot,
  and NO admin rights.

  WHAT IT DOES (the automated path — the default)
    Scheduled every few minutes, it ATTACHES to your already-open classic
    Outlook, reads the study mail folder(s) you point it at, and files EVERY new
    message as one searchable HTML note — then rebuilds index.html. You do not
    drag anything. It is incremental and idempotent: each message is filed once
    (tracked by Outlook EntryID in .state\seen.json) and your email is NEVER
    moved, deleted, or modified — it only reads.

  POINT IT AT THE STUDY MAIL — pick either or both:
    -StudyFolders "CP-101"                 # an Outlook folder. A bare name is
                                           #   found under your Inbox first (where
                                           #   an Outlook rule usually files it),
                                           #   then anywhere in your stores. Nested
                                           #   / shared: a path, e.g.
                                           #   "Project Mailbox\Inbox\CP-101".
                                           #   Semicolon-separate several.
    -SubjectContains "CP-101"              # OR sweep the Inbox by subject/sender.
                                           #   COARSE: a subject tag also matches a
                                           #   PARTICIPANT email about CP-101 — prefer
                                           #   the folder rule or -SenderContains.
    -SenderContains  "cro-bioanalytics"    #   See README governance.

  AD-HOC FALLBACK (optional): anything you drop into <Root>\_Inbox by hand
    (.msg/.eml/.txt/.md/.html) is also filed. Disable with -NoDropFolder.

  REQUIREMENTS / how to schedule it
    - Classic Outlook for Windows, ALREADY OPEN and signed in, in your own
      session. The script ATTACHES to that running instance (GetActiveObject); it
      will NOT launch a new Outlook (that would hang on the profile prompt under
      a scheduler). If Outlook isn't running it just skips auto-ingest and tells
      you. The "new" Outlook and Outlook on Mac don't expose this — use the
      drop-folder path (README).
    - Schedule it to run ONLY WHILE YOU ARE LOGGED ON, as yourself, interactive
      (so COM lands on the same desktop as Outlook):
        schtasks /Create /TN "StudyKB Update" /SC MINUTE /MO 15 /IT /F ^
          /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"...\Update-StudyKB.ps1\" -StudyFolders CP-101"
      ( /IT = interactive; do NOT use /RU SYSTEM or a stored-password batch task —
        those run in a session with no Outlook and will fail. )
    - Windows PowerShell 5.1+.

  Ops content only: no PHI / no participant-level data / no unblinded
  assignments / no randomization seeds / no sponsor IP in the KB. The script
  does NOT judge content — it files whatever is in the target folder/filter, so
  the control point is what you point it at (route only ops mail in).
---------------------------------------------------------------------------- #>
param(
  # The script lives IN your synced library, so its own folder IS the KB root by
  # default — nothing to hand-edit. Override with -Root only if you keep the
  # script elsewhere. (Falls back to the profile folder if run with no file path.)
  [string]$Root            = $(if ($PSScriptRoot) { $PSScriptRoot } else { "$env:USERPROFILE\Study Knowledge Base" }),
  [string]$StudyFolders    = "",
  [string]$SubjectContains = "",
  [string]$SenderContains  = "",
  [int]   $BackfillDays    = 30,   # how far back to read (the seen-set stops re-filing)
  [switch]$NoDropFolder
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Web | Out-Null

# Full-fidelity .eml parsing IF MimeKit.dll is dropped next to this script.
$script:MimeKit = $false
$mkdll = Join-Path $PSScriptRoot 'MimeKit.dll'
if (Test-Path $mkdll) {
  try { Add-Type -Path $mkdll; $script:MimeKit = $true }
  catch { Write-Warning "MimeKit.dll found but failed to load (drop its deps too, or use PowerShell 7): $($_.Exception.Message)" }
}

$Inbox     = Join-Path $Root '_Inbox'
$Notes     = Join-Path $Root 'Notes'
$Processed = Join-Path $Inbox '_processed'
$StateDir  = Join-Path $Root '.state'
$SeenFile  = Join-Path $StateDir 'seen.json'
$Wiki      = Join-Path $Root 'index.html'
$null = New-Item -ItemType Directory -Force -Path $Inbox, $Notes, $Processed, $StateDir
Write-Host ("[StudyKB] root = {0}" -f $Root)   # so you can see WHERE the wiki is being written

function HtmlEsc([string]$s){ [System.Web.HttpUtility]::HtmlEncode($s) }

# best-effort hygiene on inbound email HTML before persisting it as a note that
# gets opened in a browser: drop active content and neutralize remote-image
# beacons / tracking pixels (a note should never phone home when you read it).
function Sanitize-Html([string]$h){
  if (-not $h){ return $h }
  $h = $h -replace '(?is)<script.*?</script>',''
  $h = $h -replace '(?is)<style.*?</style>',''
  $h = $h -replace '(?is)<(iframe|object|embed).*?</\1>',''
  $h = $h -replace '(?i)<(script|style|iframe|object|embed|link|meta|base)\b[^>]*>',''
  $h = $h -replace '(?i)\son\w+\s*=\s*("[^"]*"|''[^'']*''|[^\s>]+)',''   # on*= event handlers
  $h = $h -replace '(?i)(src|background)\s*=\s*("|'')\s*https?:','$1=$2blocked-remote:'  # stop remote fetches
  $h = $h -replace '(?i)javascript:','blocked:'
  return $h
}

# short, stable suffix from the EntryID so two same-second/same-subject messages
# never overwrite each other's note (silent data loss).
function Short-Hash([string]$s){
  $md5 = [System.Security.Cryptography.MD5]::Create()
  $b   = $md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($s))
  -join ($b[0..3] | ForEach-Object { $_.ToString('x2') })
}

# --- "already filed" watermark: a set of Outlook EntryIDs we've turned into ----
# notes. This is what makes the auto-ingest incremental + idempotent, and lets
# us read mail WITHOUT moving or deleting it.
$seen = New-Object System.Collections.Generic.HashSet[string]
if (Test-Path $SeenFile) {
  try {
    $raw = Get-Content -Raw $SeenFile
    if ($raw -and $raw.Trim()) { foreach ($id in (ConvertFrom-Json $raw)) { [void]$seen.Add([string]$id) } }
  } catch { Write-Warning "Could not read $SeenFile (starting fresh): $($_.Exception.Message)" }
}

# attach to the RUNNING classic Outlook only (never launch one under a scheduler)
function Get-RunningOutlook {
  try { return [System.Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application') }
  catch { return $null }
}
$script:OL = $null

# --- write one note from a normalised record + remember it (by EntryID key) ---
function Write-Note($rec, $key){
  try { $when = Get-Date $rec.Date } catch { $when = Get-Date }
  $slug = ($rec.Subject -replace '[^\w\- ]','').Trim() -replace '\s+','_'
  if (-not $slug){ $slug = 'email' }
  if ($slug.Length -gt 60){ $slug = $slug.Substring(0,60) }
  $suffix   = if ($key){ '__' + (Short-Hash ([string]$key)) } else { '' }
  $noteName = ('{0}__{1}{2}.html' -f $when.ToString('yyyyMMdd_HHmmss'), $slug, $suffix)
  $bodyHtml = if ($rec.IsHtml){ Sanitize-Html $rec.Body } else { '<pre>' + (HtmlEsc $rec.Body) + '</pre>' }
  $note = @"
<!doctype html><meta charset="utf-8"><title>$(HtmlEsc $rec.Subject)</title>
<body style="font-family:Segoe UI,Arial,sans-serif;max-width:820px;margin:24px auto;padding:0 16px">
<h2 style="margin-bottom:4px">$(HtmlEsc $rec.Subject)</h2>
<p style="color:#555;margin-top:0"><b>From:</b> $(HtmlEsc $rec.From) &nbsp;|&nbsp; <b>Captured:</b> $($when.ToString('yyyy-MM-dd HH:mm'))</p>
<hr>
$bodyHtml
<hr><p style="color:#888;font-size:12px">Study Knowledge Base — captured from email. Operations content only.</p>
</body>
"@
  Set-Content -Path (Join-Path $Notes $noteName) -Value $note -Encoding UTF8
  if ($key){ [void]$seen.Add([string]$key) }
  Write-Host ("[StudyKB]  + Notes\{0}" -f $noteName)
}

# ============================================================================
#  AUTO-INGEST  —  read study mail straight from Outlook (the default path)
# ============================================================================
$madeMail = 0
$useFolders = [bool]$StudyFolders
$useFilter  = ($SubjectContains -or $SenderContains)
if ($useFolders -or $useFilter) {
  $script:OL = Get-RunningOutlook
  if (-not $script:OL) {
    Write-Warning "Auto-ingest skipped: classic Outlook isn't running. Open Outlook (desktop), signed in, and the next scheduled run will pick up. (New Outlook / Mac: use the _Inbox drop path — see README.)"
  } else {
    try {
      $ns = $script:OL.GetNamespace('MAPI')

      function Find-FolderRecursive($parent,$name){
        foreach ($f in $parent.Folders){
          if ($f.Name -eq $name){ return $f }
          $deep = Find-FolderRecursive $f $name
          if ($deep){ return $deep }
        }
        return $null
      }
      function Resolve-Folder($path){
        $parts = $path -split '\\' | Where-Object { $_ -ne '' }
        if (-not $parts){ return $null }
        if ($parts.Count -eq 1){
          # bare name: the common case is an Outlook rule filing into Inbox\<name>
          $inbox = $ns.GetDefaultFolder(6)                       # 6 = olFolderInbox
          if ($inbox.Name -eq $parts[0]){ return $inbox }
          $hit = $inbox.Folders | Where-Object { $_.Name -eq $parts[0] } | Select-Object -First 1
          if ($hit){ return $hit }
          foreach ($store in $ns.Folders){
            if ($store.Name -eq $parts[0]){ return $store }
            $deep = Find-FolderRecursive $store $parts[0]
            if ($deep){ return $deep }
          }
          return $null
        }
        $cur = $null
        foreach ($store in $ns.Folders){ if ($store.Name -eq $parts[0]){ $cur = $store; break } }
        if ($cur){ $rest = $parts[1..($parts.Count-1)] }
        else {
          foreach ($store in $ns.Folders){ $deep = Find-FolderRecursive $store $parts[0]; if ($deep){ $cur = $deep; break } }
          if (-not $cur){ return $null }
          $rest = $parts[1..($parts.Count-1)]
        }
        foreach ($seg in $rest){
          $nxt = $cur.Folders | Where-Object { $_.Name -eq $seg } | Select-Object -First 1
          if (-not $nxt){ return $null }
          $cur = $nxt
        }
        return $cur
      }
      # best-effort real SMTP address for the sender filter (Exchange senders
      # otherwise return an X.500 EX-DN that won't match a domain string)
      function Resolve-Smtp($it){
        try { if ($it.SenderEmailType -eq 'EX'){ $u = $it.Sender.GetExchangeUser(); if ($u){ return [string]$u.PrimarySmtpAddress } } } catch {}
        try { return [string]$it.SenderEmailAddress } catch { return '' }
      }

      $targets = @()
      if ($useFolders){
        foreach ($p in ($StudyFolders -split ';' | Where-Object { $_.Trim() })){
          $f = Resolve-Folder $p.Trim()
          if ($f){ $targets += $f } else { Write-Warning "Outlook folder not found: '$p' (skipped). A bare name is looked for under your Inbox, then your stores; for a shared/nested folder pass a path like 'Mailbox\Inbox\CP-101'." }
        }
      }
      $inboxId = $null
      if ($useFilter){ $defInbox = $ns.GetDefaultFolder(6); $inboxId = $defInbox.EntryID; $targets += $defInbox }

      $watermark = (Get-Date).AddDays(-[math]::Abs($BackfillDays))
      $ci  = [System.Globalization.CultureInfo]::CurrentCulture       # Outlook parses the literal in the host's culture
      $fmt = $ci.DateTimeFormat.ShortDatePattern + ' ' + $ci.DateTimeFormat.ShortTimePattern
      $restrict = "[ReceivedTime] >= '" + $watermark.ToString($fmt, $ci) + "'"

      foreach ($fld in $targets){
        Write-Host ('[StudyKB] reading Outlook folder "{0}"' -f $fld.Name)
        $items = $fld.Items
        try { $items.Sort('[ReceivedTime]', $true) } catch {}
        try { $recent = $items.Restrict($restrict) }       # server-side date prefilter
        catch { Write-Warning "Date filter not accepted on this locale — scanning the folder client-side."; $recent = $items }
        foreach ($it in @($recent)){
          try {
            if ($it.Class -ne 43){ continue }              # 43 = olMail
            $id = [string]$it.EntryID
            if ($seen.Contains($id)){ continue }
            $rt = $it.ReceivedTime
            if ($rt -lt $watermark){ continue }            # client-side backstop (covers the Restrict fallback)
            $subj = [string]$it.Subject
            $from = [string]$it.SenderName
            if ($inboxId -and $fld.EntryID -eq $inboxId){   # Inbox-filter mode only
              if ($SubjectContains -and $subj -notmatch [regex]::Escape($SubjectContains)){ continue }
              if ($SenderContains){
                $hay = "$from " + (Resolve-Smtp $it)
                if ($hay -notmatch [regex]::Escape($SenderContains)){ continue }
              }
            }
            $body = [string]$it.HTMLBody
            if (-not $body){
              $plain = [string]$it.Body
              if (-not $plain){ Write-Warning "Empty body (header-only / not yet synced?): '$subj' — filed as a stub." }
              $body = '<pre>' + (HtmlEsc $plain) + '</pre>'
            }
            Write-Note ([ordered]@{ Subject=$subj; From=$from; Date=$rt; Body=$body; IsHtml=$true }) $id
            $madeMail++
          } catch {
            Write-Warning ("Skipped one item: {0}" -f $_.Exception.Message)
          } finally {
            if ($it){ [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($it) }
          }
        }
      }
    } catch {
      Write-Warning ("Auto-ingest error: {0}" -f $_.Exception.Message)
    }
  }
}

# ============================================================================
#  AD-HOC DROP FOLDER  —  optional: anything you dragged into _Inbox by hand
# ============================================================================
function Read-Msg($path){
  try {
    $app = $script:OL
    if (-not $app){ $app = Get-RunningOutlook }   # attach only — never launch (would hang on the profile prompt)
    if (-not $app){ Write-Warning "Skipping $(Split-Path $path -Leaf): classic Outlook isn't running and this script won't launch it. Open Outlook, or save the email as .eml/.txt into _Inbox."; return $null }
    $m   = $app.Session.OpenSharedItem($path)
    $r = [ordered]@{ Subject=$m.Subject; From=$m.SenderName; Date=$m.ReceivedTime; Body=$m.HTMLBody; IsHtml=$true }
    [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($m)
    return $r
  } catch {
    Write-Warning "Could not read $($path): $($_.Exception.Message). Re-save the email as .eml or .txt into _Inbox."
    return $null
  }
}
function Read-Eml($path){
  if ($script:MimeKit) {
    try {
      $m = [MimeKit.MimeMessage]::Load($path)
      if ($m.HtmlBody) { $body = $m.HtmlBody } else { $body = '<pre>' + (HtmlEsc ([string]$m.TextBody)) + '</pre>' }
      try { $dt = $m.Date.DateTime } catch { $dt = (Get-Item $path).LastWriteTime }
      return [ordered]@{ Subject=[string]$m.Subject; From=[string]$m.From; Date=$dt; Body=$body; IsHtml=$true }
    } catch { Write-Warning "MimeKit parse failed on $($path): $($_.Exception.Message); using naive parser." }
  }
  $raw   = Get-Content -Raw -Encoding UTF8 $path
  $parts = $raw -split '\r?\n\r?\n', 2
  $head  = $parts[0]; $body = if ($parts.Count -ge 2){ $parts[1] } else { '' }
  $h = @{}
  foreach ($ln in ($head -split '\r?\n')){ if ($ln -match '^(Subject|From|Date):\s*(.*)$'){ $h[$matches[1]] = $matches[2] } }
  $isHtml = ($head -match 'Content-Type:\s*text/html') -or ($body -match '(?i)<html')
  $subj = if ($h.ContainsKey('Subject')){ $h['Subject'] } else { [IO.Path]::GetFileNameWithoutExtension($path) }
  $from = if ($h.ContainsKey('From')){ $h['From'] } else { '' }
  $dt   = if ($h.ContainsKey('Date')){ $h['Date'] } else { (Get-Item $path).LastWriteTime }
  return [ordered]@{ Subject=$subj; From=$from; Date=$dt; Body=$body; IsHtml=$isHtml }
}
function Read-Plain($file,$isHtml){
  return [ordered]@{ Subject=$file.BaseName; From=''; Date=$file.LastWriteTime;
                     Body=(Get-Content -Raw $file.FullName); IsHtml=$isHtml }
}

$madeDrop = 0
if (-not $NoDropFolder){
  $exts = '.msg','.eml','.txt','.md','.html','.htm'
  $drops = Get-ChildItem -File $Inbox | Where-Object { $exts -contains $_.Extension.ToLower() }
  foreach ($f in $drops){
    switch ($f.Extension.ToLower()){
      '.msg'  { $c = Read-Msg  $f.FullName }
      '.eml'  { $c = Read-Eml  $f.FullName }
      '.html' { $c = Read-Plain $f $true }
      '.htm'  { $c = Read-Plain $f $true }
      default { $c = Read-Plain $f $false }     # .txt / .md
    }
    if (-not $c){ continue }
    Write-Note $c $null
    Move-Item -Force $f.FullName (Join-Path $Processed $f.Name)
    $madeDrop++
  }
}

# release the Outlook RCW (do NOT Quit — that would close the user's Outlook)
if ($script:OL){ try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($script:OL) } catch {} }

# persist the watermark (a JSON array of EntryIDs — tiny even for a long study)
Set-Content -Path $SeenFile -Value (ConvertTo-Json @($seen) -Depth 1) -Encoding UTF8

# ============================================================================
#  REBUILD THE WIKI INDEX  (searchable, newest first)
# ============================================================================
$cards = ""
foreach ($n in (Get-ChildItem -File $Notes -Filter *.html | Sort-Object Name -Descending)){
  $txt = (Get-Content -Raw $n.FullName) -replace '<[^>]+>',' '
  $snip = (($txt -replace '\s+',' ').Trim())
  if ($snip.Length -gt 240){ $snip = $snip.Substring(0,240) + '...' }
  $title = $n.BaseName -replace '^\d{8}_\d{6}__','' -replace '__[0-9a-f]{8}$',''
  $sattr = (HtmlEsc (($title + ' ' + $snip).ToLower()))
  $cards += "<a class='card' data-s='$sattr' href='Notes/$([uri]::EscapeDataString($n.Name))'>" +
            "<div class='t'>$(HtmlEsc ($title -replace '_',' '))</div>" +
            "<div class='m'>$($n.LastWriteTime.ToString('yyyy-MM-dd HH:mm'))</div>" +
            "<div class='s'>$(HtmlEsc $snip)</div></a>`n"
}
$count = (Get-ChildItem -File $Notes -Filter *.html).Count
$index = @"
<!doctype html><meta charset="utf-8"><title>Study Knowledge Base</title>
<style>
 body{font-family:Segoe UI,Arial,sans-serif;max-width:980px;margin:24px auto;padding:0 16px;color:#1a1a1a}
 h1{margin-bottom:2px} .sub{color:#666;margin-top:0}
 #q{width:100%;padding:10px 12px;font-size:15px;border:1px solid #ccc;border-radius:8px;margin:14px 0}
 .card{display:block;text-decoration:none;color:inherit;border:1px solid #e3e3e3;border-radius:10px;padding:12px 14px;margin:8px 0}
 .card:hover{border-color:#1f6feb;background:#f6f9ff}
 .t{font-weight:600} .m{color:#888;font-size:12px;margin:2px 0} .s{color:#444;font-size:13px}
</style>
<h1>Study Knowledge Base</h1>
<p class="sub">$count notes — rebuilt $((Get-Date).ToString('yyyy-MM-dd HH:mm')). Filed automatically from study email; this page updates itself.</p>
<input id="q" onkeyup="flt()" placeholder="Search notes...">
<div id="list">
$cards
</div>
<script>
function flt(){var t=document.getElementById('q').value.toLowerCase();
 document.querySelectorAll('.card').forEach(function(c){c.style.display=c.dataset.s.indexOf(t)>-1?'':'none';});}
</script>
"@
Set-Content -Path $Wiki -Value $index -Encoding UTF8
Write-Host ("[StudyKB] {0} new from Outlook, {1} from drop-folder; {2} total. Wiki: {3}  ·  mail left untouched in Outlook" -f $madeMail, $madeDrop, $count, $Wiki)
