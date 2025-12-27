# WinGet-Intune-Publisher

Utilities to package and publish WinGet applications to Microsoft Intune as Win32 apps, create AAD groups, and optionally set up Proactive Remediations—all in a single authenticated run.

## Features

- Build IntuneWin packages from WinGet install/uninstall scripts.
- Upload Win32 apps to Intune with detection, return codes, and optional icons.
- Create or reuse install/uninstall Azure AD groups and assign the app.
- (Optional) Create Proactive Remediations for ongoing updates.
- Batch mode: deploy multiple Winget App IDs in one session; display names auto-resolved via `Find-WinGetPackage`.

## Requirements

- PowerShell 5.1+ (or 7.x on Windows for WinGet) with `Microsoft.Graph.Authentication`.
- `SvRooij.ContentPrep.Cmdlet` for creating `.intunewin` packages.
- Winget available on the packaging host (script auto-installs if missing).
- Intune/Graph permissions: DeviceManagementApps.ReadWrite.All, DeviceManagementConfiguration.ReadWrite.All, Group.ReadWrite.All, GroupMember.ReadWrite.All (consent once).

## Quick Start

```pwsh
Import-Module ./WingetIntunePublisher.psd1

# Single app
Invoke-WingetIntunePublisher -appid "Google.Chrome"

# Multiple apps (names auto-resolved)
Invoke-WingetIntunePublisher -appid "Google.Chrome","7zip.7zip"

# Multiple apps with explicit names
Invoke-WingetIntunePublisher -appid "Google.Chrome","Notepad++.Notepad++" -appname "Google Chrome","Notepad++"

# Supply app registration for app-based auth
$clientId = "<appId>"
$tenantId = "<tenantId>"
$secret   = "<secret>"
Invoke-WingetIntunePublisher -appid "Google.Chrome" -tenant $tenantId -clientid $clientId -clientsecret $secret
```

## Deploy Popular Apps by Category

The module includes curated collections of 86 popular enterprise applications organized by category. You can deploy them using either `Invoke-PopularAppsDeployment` (recommended) or `Get-PopularAppsByCategory` with `Invoke-WingetIntunePublisher`.

### Quick Usage (Recommended)

```powershell
# Deploy all browsers (8 apps)
Invoke-PopularAppsDeployment -Category Browsers

# Deploy all development tools (14 apps)
Invoke-PopularAppsDeployment -Category Development

# Deploy specific utilities only
Invoke-PopularAppsDeployment -Category Utilities -AppName "7-Zip","Everything Search"

# Deploy password managers from Security category
Invoke-PopularAppsDeployment -Category Security -AppName "*Pass*"

# Preview what would be deployed without deploying
Invoke-PopularAppsDeployment -Category Browsers -WhatIf

# Deploy with app-based authentication
Invoke-PopularAppsDeployment -Category Media -Tenant "contoso.onmicrosoft.com" -ClientId "app-guid" -ClientSecret "secret"
```

### Advanced Usage (Manual Control)

```powershell
# Get apps and deploy with custom parameters
$browsers = Get-PopularAppsByCategory -Category Browsers -ReturnAsObject
Invoke-WingetIntunePublisher -appid $browsers.AppId -appname $browsers.AppName

# Deploy filtered subset of utilities
$utils = Get-PopularAppsByCategory -Category Utilities -ReturnAsObject
$essential = $utils | Where-Object { $_.AppName -in @('7-Zip', 'Everything Search') }
Invoke-WingetIntunePublisher -appid $essential.AppId -appname $essential.AppName
```

### Available Categories

#### Browsers (8 apps)

| App Name | WinGet Package ID |
|----------|-------------------|
| Google Chrome | `Google.Chrome` |
| Mozilla Firefox | `Mozilla.Firefox` |
| Microsoft Edge | `Microsoft.Edge` |
| Brave Browser | `BraveSoftware.BraveBrowser` |
| Opera | `Opera.Opera` |
| Vivaldi | `Vivaldi.Vivaldi` |
| LibreWolf | `LibreWolf.LibreWolf` |
| Chromium | `Chromium.Chromium` |

#### Productivity (10 apps)

| App Name | WinGet Package ID |
|----------|-------------------|
| Adobe Acrobat Reader | `Adobe.Acrobat.Reader.64-bit` |
| Notepad++ | `Notepad++.Notepad++` |
| Microsoft Office | `Microsoft.Office` |
| LibreOffice | `TheDocumentFoundation.LibreOffice` |
| Notion | `Notion.Notion` |
| Obsidian | `Obsidian.Obsidian` |
| PowerToys | `Microsoft.PowerToys` |
| Foxit Reader | `Foxit.FoxitReader` |
| Sumatra PDF | `SumatraPDF.SumatraPDF` |
| Evernote | `Evernote.Evernote` |

#### Communication (9 apps)

| App Name | WinGet Package ID |
|----------|-------------------|
| Microsoft Teams | `Microsoft.Teams` |
| Zoom | `Zoom.Zoom` |
| Slack | `SlackTechnologies.Slack` |
| Discord | `Discord.Discord` |
| Cisco Webex | `Cisco.CiscoWebexMeetings` |
| RingCentral | `RingCentral.RingCentral` |
| Skype | `Microsoft.Skype` |
| Telegram Desktop | `Telegram.TelegramDesktop` |
| WhatsApp | `WhatsApp.WhatsApp` |

#### Development (14 apps)

| App Name | WinGet Package ID |
|----------|-------------------|
| Visual Studio Code | `Microsoft.VisualStudioCode` |
| Git | `Git.Git` |
| GitHub Desktop | `GitHub.GitHubDesktop` |
| Python 3.12 | `Python.Python.3.12` |
| Node.js | `OpenJS.NodeJS` |
| Visual Studio 2022 Community | `Microsoft.VisualStudio.2022.Community` |
| IntelliJ IDEA Community | `JetBrains.IntelliJIDEA.Community` |
| Docker Desktop | `Docker.DockerDesktop` |
| Postman | `Postman.Postman` |
| Windows Terminal | `Microsoft.WindowsTerminal` |
| WinSCP | `WinSCP.WinSCP` |
| PuTTY | `PuTTY.PuTTY` |
| NVM for Windows | `CoreyButler.NVMforWindows` |
| PowerShell | `Microsoft.PowerShell` |

#### Media (9 apps)

| App Name | WinGet Package ID |
|----------|-------------------|
| VLC Media Player | `VideoLAN.VLC` |
| Spotify | `Spotify.Spotify` |
| Audacity | `Audacity.Audacity` |
| HandBrake | `HandBrake.HandBrake` |
| OBS Studio | `OBSProject.OBSStudio` |
| iTunes | `Apple.iTunes` |
| AIMP | `AIMP.AIMP` |
| MPC-HC | `clsid2.mpc-hc` |
| Kodi | `Kodi.Kodi` |

#### Utilities (13 apps)

| App Name | WinGet Package ID |
|----------|-------------------|
| 7-Zip | `7zip.7zip` |
| WinRAR | `RARLab.WinRAR` |
| Everything Search | `voidtools.Everything` |
| TreeSize Free | `JAMSoftware.TreeSize.Free` |
| Greenshot | `Greenshot.Greenshot` |
| ShareX | `ShareX.ShareX` |
| CCleaner | `Piriform.CCleaner` |
| Sysinternals PsTools | `Microsoft.Sysinternals.PsTools` |
| Process Explorer | `Sysinternals.ProcessExplorer` |
| Autoruns | `Sysinternals.Autoruns` |
| WinDirStat | `WinDirStat.WinDirStat` |
| Rufus | `Rufus.Rufus` |
| Balena Etcher | `Balena.Etcher` |

#### Security (8 apps)

| App Name | WinGet Package ID |
|----------|-------------------|
| KeePassXC | `KeePassXCTeam.KeePassXC` |
| Bitwarden | `Bitwarden.Bitwarden` |
| 1Password | `1Password.1Password` |
| NordVPN | `NordVPN.NordVPN` |
| Proton VPN | `ProtonTechnologies.ProtonVPN` |
| Malwarebytes | `Malwarebytes.Malwarebytes` |
| Gpg4win | `GnuPG.Gpg4win` |
| VeraCrypt | `VeraCrypt.VeraCrypt` |

#### Graphics (8 apps)

| App Name | WinGet Package ID |
|----------|-------------------|
| GIMP | `GIMP.GIMP` |
| Inkscape | `Inkscape.Inkscape` |
| Paint.NET | `dotPDN.PaintDotNet` |
| Blender | `Blender.Blender` |
| IrfanView | `IrfanSkiljan.IrfanView` |
| XnView MP | `XnSoft.XnViewMP` |
| Figma | `Figma.Figma` |
| Canva | `Canva.Canva` |

#### Remote (7 apps)

| App Name | WinGet Package ID |
|----------|-------------------|
| TeamViewer | `TeamViewer.TeamViewer` |
| AnyDesk | `AnyDeskSoftwareGmbH.AnyDesk` |
| Chrome Remote Desktop | `Google.ChromeRemoteDesktop` |
| VNC Viewer | `RealVNC.VNCViewer` |
| Microsoft Remote Desktop | `Microsoft.RemoteDesktopClient` |
| Parsec | `Parsec.Parsec` |
| TightVNC | `TightVNC.TightVNC` |

**Total: 86 curated applications across 9 categories**

## What the Script Does

1. Ensures required modules are installed.
2. Connects to Microsoft Graph (interactive or app-based).
3. Generates install/uninstall/detection scripts per app and packages them into `.intunewin`.
4. Searches for an icon (optional) and uploads the Win32 app to Intune with default return codes.
5. Creates/reuses install and uninstall AAD groups and assigns the app; optionally creates a Proactive Remediation if licensed.

All resources created by this module are automatically tagged with a standardized description identifier for easy management and cleanup.

## Managing Deployed Apps

### Removing Apps

The module provides `Remove-WingetIntuneApps` to clean up deployed applications and their associated resources. This function automatically removes:

- Win32 apps deployed via WingetIntunePublisher
- Associated Azure AD groups (`{AppName} Required` and `{AppName} Uninstall`)
- Associated Proactive Remediations (`{AppName} Proactive Update`)

```powershell
# Remove all WingetIntunePublisher apps (with confirmation prompts)
Remove-WingetIntuneApps

# Remove a specific app
Remove-WingetIntuneApps -AppName "Google Chrome"

# Remove apps matching a pattern
Remove-WingetIntuneApps -AppName "*Adobe*"

# Preview what would be deleted (no changes made)
Remove-WingetIntuneApps -WhatIf

# Remove without confirmation prompts (use with caution!)
Remove-WingetIntuneApps -Confirm:$false
```

See [Examples/Remove-AllWingetApps.ps1](Examples/Remove-AllWingetApps.ps1) for a complete example script.

### Resource Identification

All resources created by WingetIntunePublisher are tagged with a standardized description for identification:

**Identifier Tag**: `Imported with Winget Intune Publisher - github.com/jorgeasaurus/WingetIntunePublisher`

**Naming Conventions**:

- **Install Groups**: `{AppName} Required`
- **Uninstall Groups**: `{AppName} Uninstall`
- **Proactive Remediations**: `{AppName} Proactive Update`

**Description Formats**:

- **Apps**: `{AppDescription} Imported with Winget Intune Publisher - github.com/jorgeasaurus/WingetIntunePublisher`
- **Groups**: `{Install|Uninstall} group for {AppName} - Imported with Winget Intune Publisher - github.com/jorgeasaurus/WingetIntunePublisher`
- **Remediations**: `Auto-update remediation for {AppName} - Imported with Winget Intune Publisher - github.com/jorgeasaurus/WingetIntunePublisher`

This standardized tagging enables:

- Easy identification of all WingetIntunePublisher resources
- Bulk operations across all deployed apps
- Migration from older description formats using [Update-WingetGroupRemediationDescriptions.ps1](Examples/Update-WingetGroupRemediationDescriptions.ps1)

## Inputs

- `-appid` (string[]): One or more Winget IDs (e.g., `Google.Chrome`, `7zip.7zip`).
- `-appname` (string[]): Optional display names aligned to `-appid`; otherwise auto-resolved or falls back to the ID.
- `-tenant`, `-clientid`, `-clientsecret`: Optional app-based authentication details; if omitted, interactive auth with requested scopes is used.
- `-installgroupname`, `-uninstallgroupname`: Optional custom group names; defaults are generated per app.
- `-availableinstall`: `User`, `Device`, `Both`, or `None` (default `User`).
- `-Force`: Overwrite deployment even if an app with a matching name already exists.

## Notes & Caveats

- **Windows-only**: This module requires Windows for WinGet packaging operations. The CI pipeline runs code quality checks cross-platform but build/test steps only on Windows.
- `Out-GridView` is only used for interactive app selection when no `-appid` is supplied.
- Winget downloads and installs dependencies; ensure network access to `aka.ms` and `github.com` endpoints.
- Proactive Remediations creation requires an eligible license (Intune Plan 2/Intune Suite/Windows 365 Enterprise).

## Repository Structure

- `Invoke-WingetIntunePublisher.ps1` – entry point orchestrator.
- `Public/` – exported functions (module cmdlet entrypoint, deployment orchestration, Winget operations, Graph auth, utility helpers).
- `Private/` – internal helpers (Win32 packaging, storage upload, group management, script generation).

## Support

Use GitHub issues for bugs or questions. Contributions welcome via pull requests.***
