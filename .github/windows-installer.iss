#ifndef AppVersion
  #error "AppVersion must be provided by the release workflow."
#endif
#ifndef SourceDir
  #error "SourceDir must be provided by the release workflow."
#endif

[Setup]
AppId={{5DAF18E2-2339-4B44-8431-A87BA6EAF1B2}
AppName=AI Voice Dictator
AppVersion={#AppVersion}
AppPublisher=md-riaz
DefaultDirName={localappdata}\Programs\AI Voice Dictator
DefaultGroupName=AI Voice Dictator
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputBaseFilename=AI-Voice-Dictator-v{#AppVersion}-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\AI-Voice-Dictator.exe

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\AI Voice Dictator"; Filename: "{app}\AI-Voice-Dictator.exe"

[Run]
Filename: "{app}\AI-Voice-Dictator.exe"; Description: "Launch AI Voice Dictator"; Flags: nowait postinstall skipifsilent
