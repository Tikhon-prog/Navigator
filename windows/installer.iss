#define MyAppName "Поколение"
#ifndef MyAppVersion
  #define MyAppVersion "0.2.0"
#endif
#define MyAppPublisher "Школа «Поколение»"
#define MyAppExeName "pokolenie.exe"

[Setup]
AppId={{7B68277C-0C39-4F4C-94CE-4F899CC2F7D4}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={localappdata}\Programs\Поколение
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\dist
OutputBaseFilename=Pokolenie-Setup-{#MyAppVersion}
SetupIconFile=runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"

[Tasks]
Name: "desktopicon"; Description: "Создать ярлык на рабочем столе"; GroupDescription: "Дополнительные значки:"; Flags: unchecked

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; AppUserModelID: "Pokolenie.Navigator.Desktop"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon; AppUserModelID: "Pokolenie.Navigator.Desktop"

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Запустить «Поколение»"; Flags: postinstall nowait skipifsilent
