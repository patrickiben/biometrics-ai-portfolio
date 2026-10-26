' ============================================================================
' FileToKB.vba  —  one-click "file the selected email(s) into the Study KB"
'
' This is the AD-HOC one-click for the rare email that lives outside your study
' folder. The routine path is automatic: Update-StudyKB.ps1 reads the study
' folder on a schedule (-StudyFolders) — you don't click anything. Use this only
' to capture a stray forwarded thread into the KB inbox in one click.
'
' Outlook Quick Steps can only move mail to ANOTHER OUTLOOK FOLDER, not to a
' disk folder — so a true one-click-to-disk uses this tiny VBA button instead.
' (CLASSIC Outlook only; the "new" Outlook has no VBA — there, drag/Save-As the
'  email as .eml into the synced _Inbox and let the scheduled script file it.)
'
' SETUP (once):
'   1. Outlook ▸ Alt+F11 (VBA editor) ▸ Project1 ▸ right-click ▸ Insert ▸ Module
'      ▸ paste everything below. Set INBOX to your synced library's _Inbox path.
'   2. File ▸ Options ▸ Quick Access Toolbar ▸ "Choose commands from: Macros" ▸
'      select Project1.FileToKB ▸ Add ▸ OK.  (If macros are blocked: File ▸
'      Options ▸ Trust Center ▸ Macro Settings ▸ "Notifications for signed", or
'      ask IT to allow/sign — same one snag as the .ps1.)
' USE:  select one or more emails ▸ click the toolbar button = filed in one click.
'       The scheduled Update-StudyKB.ps1 then turns them into wiki notes.
' Ops content only — never file PHI / participant-level / sponsor-restricted email.
' ============================================================================
Sub FileToKB()
    Const INBOX As String = "C:\Users\you\Study Knowledge Base\_Inbox\"   ' <-- set this
    Dim sel As Outlook.Selection, itm As Object, n As Long, fn As String
    Set sel = Application.ActiveExplorer.Selection
    If sel Is Nothing Or sel.Count = 0 Then Exit Sub
    For Each itm In sel
        If itm.Class = olMail Then
            fn = INBOX & Format(itm.ReceivedTime, "yyyymmdd_hhnnss") & "__" _
                 & CleanName(itm.Subject) & ".msg"
            itm.SaveAs fn, olMSG
            n = n + 1
        End If
    Next
    MsgBox n & " message(s) filed to the Study KB inbox.", vbInformation, "FileToKB"
End Sub

' keep only safe filename characters; cap length
Private Function CleanName(ByVal s As String) As String
    Dim i As Long, c As String, o As String
    For i = 1 To Len(s)
        c = Mid$(s, i, 1)
        If c Like "[A-Za-z0-9 _-]" Then o = o & c
    Next
    o = Trim$(o)
    If Len(o) = 0 Then o = "email"
    If Len(o) > 60 Then o = Left$(o, 60)
    CleanName = o
End Function
