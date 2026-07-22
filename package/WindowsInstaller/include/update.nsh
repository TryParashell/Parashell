/*
update.nsh

Queries the Dropsite autoupdate feed (api8.parashell.cloud) for the latest
published release. When the bundled installer is older than what is available,
the user is offered a one-click update: the newest installer is downloaded and
launched, and the current installer bows out.
*/

Function CheckForUpdates

  StrCpy $UpdateUrl ""
  StrCpy $UpdateVersion ""
  StrCpy $UpdateFile ""

  nsExec::ExecToStack `powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "$$ProgressPreference='SilentlyContinue'; try { $$resp = Invoke-RestMethod -UseBasicParsing -TimeoutSec 10 -Uri '${DROPSITE_CHECK_URL}?current=${APP_VERSION}'; if ($$resp.update_available) { Write-Output ($$resp.latest.version + '|' + $$resp.latest.download_url) } } catch { exit 1 }"`
  Pop $0 # return/exit code
  Pop $1 # captured stdout

  # network failure, timeout, or a non-zero PowerShell exit must never block installing
  ${if} $0 != "0"
   Return
  ${endif}
  ${if} $1 == ""
   Return
  ${endif}

  Call TrimUpdateOutput
  ${if} $1 == ""
   Return
  ${endif}

  # split "version|download_url" on the first "|"
  StrCpy $String $1
  StrCpy $Search "|"
  Call StrPoint
  ${if} $Pointer == "-1"
   Return
  ${endif}
  StrCpy $UpdateVersion $1 $Pointer
  IntOp $3 $Pointer + 1
  StrCpy $UpdateUrl $1 "" $3

  # only trust an absolute https/http download target
  StrCpy $2 $UpdateUrl 4
  ${if} $2 != "http"
   Return
  ${endif}

  MessageBox MB_OKCANCEL|MB_ICONQUESTION "$(UpdateAvailable)" /SD IDCANCEL IDOK DoUpdate
  Return

  DoUpdate:
   ${IfNot} ${Silent}
    Banner::show /NOUNLOAD "$(UpdateDownloading)"
   ${endif}

   nsExec::ExecToStack `powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "$$ProgressPreference='SilentlyContinue'; try { $$u='$UpdateUrl'; $$ext=[System.IO.Path]::GetExtension(([System.Uri]$$u).AbsolutePath); if (-not $$ext) { $$ext='.exe' }; $$out=Join-Path $$env:TEMP ('Parashell-Update-' + [System.Guid]::NewGuid().ToString('N') + $$ext); Invoke-WebRequest -UseBasicParsing -Uri $$u -OutFile $$out; Write-Output $$out } catch { exit 1 }"`
   Pop $0 # return/exit code
   Pop $1 # captured stdout (downloaded file path)

   ${IfNot} ${Silent}
    Banner::destroy
   ${endif}

   ${if} $0 != "0"
    MessageBox MB_OK|MB_ICONEXCLAMATION "$(UpdateDownloadFailed)" /SD IDOK
    Return
   ${endif}

   Call TrimUpdateOutput
   StrCpy $UpdateFile $1
   ${if} $UpdateFile == ""
    MessageBox MB_OK|MB_ICONEXCLAMATION "$(UpdateDownloadFailed)" /SD IDOK
    Return
   ${endif}
   IfFileExists "$UpdateFile" 0 DownloadMissing

   ClearErrors
   ExecShell "open" "$UpdateFile"
   IfErrors LaunchFailed
   Quit

   DownloadMissing:
   LaunchFailed:
    MessageBox MB_OK|MB_ICONEXCLAMATION "$(UpdateDownloadFailed)" /SD IDOK

FunctionEnd

#--------------------------------
# strips trailing whitespace and newlines from the captured stdout in $1

Function TrimUpdateOutput

  TrimTail:
  StrCpy $2 $1 1 -1
  ${if} $2 == "$\r"
  ${orif} $2 == "$\n"
  ${orif} $2 == " "
  ${orif} $2 == "$\t"
   StrCpy $1 $1 -1
   ${if} $1 == ""
    Return
   ${endif}
   Goto TrimTail
  ${endif}

FunctionEnd
