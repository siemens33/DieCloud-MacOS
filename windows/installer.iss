#define MyAppName "DieCloud"
#define MyAppVersion "5.0.1"
#define MyAppPublisher "siemens"
#define MyAppURL "https://github.com/siemens33/DieCloud-MacOS"
#define MyAppExeName "DieCloud.exe"

[Setup]
AppId={{D1EC10UD-5010-4A21-853B-EF0759B9DAFA}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputBaseFilename=DieCloud-Setup
OutputDir=..\release-win
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
SetupIconFile=resources\DieCloudIcon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "build\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "build\xray.exe"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist
Source: "resources\theme-engine.js"; DestDir: "{app}\resources"; Flags: ignoreversion skipifsourcedoesntexist
Source: "resources\adblock-rules.json"; DestDir: "{app}\resources"; Flags: ignoreversion skipifsourcedoesntexist
Source: "resources\DieCloudIcon.ico"; DestDir: "{app}\resources"; Flags: ignoreversion skipifsourcedoesntexist

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
