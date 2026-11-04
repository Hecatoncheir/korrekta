#ifndef AppVersion
  #define AppVersion "0.1.0"
#endif
[Setup]
AppId={{AA281971-7A99-4540-97EB-EA52B50BD007}
AppName=Корректа
AppVersion={#AppVersion}
AppPublisher=Hecatoncheir
AppPublisherURL=https://github.com/Hecatoncheir/korrekta
DefaultDirName={localappdata}\Programs\Korrekta
PrivilegesRequired=lowest
DefaultGroupName=Корректа
OutputDir=..\release
OutputBaseFilename=Korrekta-{#AppVersion}-windows-x64-setup
SetupIconFile=..\app\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\korrekta.exe
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
CloseApplications=yes
RestartApplications=no

[Languages]
Name: russian; MessagesFile: compiler:Languages\Russian.isl

[Files]
Source: ..\app\build\windows\x64\runner\Release\*; DestDir: {app}; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: {group}\Корректа; Filename: {app}\korrekta.exe

[Run]
Filename: {app}\korrekta.exe; Description: Открыть Корректу; Flags: nowait postinstall skipifsilent
Filename: {app}\korrekta.exe; Flags: nowait; Check: RelaunchRequested

[Code]
function RelaunchRequested: Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 1 to ParamCount do
    if CompareText(ParamStr(I), '/RELAUNCH') = 0 then
      Result := True;
end;
