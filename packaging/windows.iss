#ifndef AppVersion
  #define AppVersion "0.1.0"
#endif
[Setup]
AppId={{AA281971-7A99-4540-97EB-EA52B50BD007}
AppName=Корректа
AppVersion={#AppVersion}
AppPublisher=Hecatoncheir
AppPublisherURL=https://github.com/Hecatoncheir/korrekta
DefaultDirName={autopf}\Korrekta
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

[Languages]
Name: russian; MessagesFile: compiler:Languages\Russian.isl

[Files]
Source: ..\app\build\windows\x64\runner\Release\*; DestDir: {app}; Flags: ignoreversion recursesubdirs createallsubdirs
Source: ..\release\vc_redist.x64.exe; DestDir: {tmp}; Flags: deleteafterinstall

[Icons]
Name: {group}\Корректа; Filename: {app}\korrekta.exe

[Run]
Filename: {tmp}\vc_redist.x64.exe; Parameters: /install /quiet /norestart; StatusMsg: Установка компонентов Microsoft; Flags: waituntilterminated
Filename: {app}\korrekta.exe; Description: Открыть Корректу; Flags: nowait postinstall skipifsilent
