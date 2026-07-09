#define version "0.4.3"
#define name "Kuvacult"
#define pub "ydlm88"

[Setup]
  AppName={#name}
  AppVersion={#version}
  AppPublisher={#pub}
  AppPublisherURL=https://github.com/ydlm88/Kuvacult
  Uninstallable=yes
  DefaultDirName={autopf}\Kuvacult
  DefaultGroupName={#name}
  OutputDir=installer_output
  OutputBaseFilename=Kuvacult-Setup
  Compression=lzma
  SolidCompression=yes 
  WizardStyle=modern
  UninstallDisplayIcon={app}\kuvacult.exe
  SetupIconFile=windows\runner\resources\app_icon.ico

[Languages]
  Name: "english"; MessagesFile: "compiler:Default.isl"
  

[Tasks]
  Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional icons:"

[Files]
  Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
  Source: "windows\runner\resources\app_icon.ico"; DestDir: "{app}"; Flags: ignoreversion
  
  
[Icons]
  Name: "{group}\Kuvacult"; Filename: "{app}\kuvacult.exe"; IconFilename:"{app}\app_icon.ico"
  Name: "{autodesktop}\Kuvacult"; Filename: "{app}\kuvacult.exe"; IconFilename: "{app}\app_icon.ico"; Tasks: desktopicon 

[Run]
  Filename: "{app}\kuvacult.exe"; Description: "Launch Kuvacult"; Flags: nowait postinstall skipifsilent










