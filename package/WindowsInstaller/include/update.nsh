Function CheckForUpdates

  StrCpy $UpdateVersion ""
  ReadEnvStr $2 "ProgramData"
  ${if} $2 == ""
   Return
  ${endif}
  StrCpy $UpdateScript "$2\Parashell\Updater\ParashellUpdater.ps1"
  StrCpy $UpdateManifest "$2\Parashell\Updater\update-manifest.json"
  InitPluginsDir
  SetOutPath "$PLUGINSDIR"
  File /oname=ParashellUpdater.ps1 "${__FILEDIR__}\..\updater\ParashellUpdater.ps1"

  nsExec::ExecToStack `"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$PLUGINSDIR\ParashellUpdater.ps1" -Mode Check -CurrentVersion "${APP_VERSION_NUMBER}" -FeedUrl "${DROPSITE_CHECK_URL}" -ManifestPath "$UpdateManifest" -BootstrapPath "$EXEPATH"`
  Pop $0
  Pop $1

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
  StrCpy $UpdateVersion $1

  MessageBox MB_OKCANCEL|MB_ICONQUESTION "$(UpdateAvailable)" /SD IDCANCEL IDOK StartBackgroundUpdate
  Return

  StartBackgroundUpdate:
   System::Call 'kernel32::GetCurrentProcessId() i .r2'
   ClearErrors
   Exec '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "$UpdateScript" -Mode Download -ManifestPath "$UpdateManifest" -ParentProcessId $2'
   IfErrors UpdateLaunchFailed
   MessageBox MB_OK|MB_ICONINFORMATION "$(UpdateStarted)" /SD IDOK
   Quit

  UpdateLaunchFailed:
   MessageBox MB_OK|MB_ICONEXCLAMATION "$(UpdateDownloadFailed)" /SD IDOK

FunctionEnd

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
