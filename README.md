# WinGet-Intune-Publisher

**Version:** 0.2.0 | **License:** GPL-3.0 | **Author:** Jorge Suarez (jorgeasaurus)

Enterprise-grade PowerShell module for automating the packaging and deployment of WinGet applications to Microsoft Intune as Win32 apps. Handles everything from package creation to Azure AD group management and Proactive Remediation setup—all in a single authenticated run.

## ✨ Features

- **Automated Win32 App Packaging**: Build `.intunewin` packages from WinGet install/uninstall scripts
- **Complete Deployment Workflow**: Upload to Intune with detection scripts, return codes, and optional icons
- **Azure AD Integration**: Automatically create or reuse install/uninstall groups and assign applications
- **Proactive Remediations**: Optional auto-update remediations for ongoing application maintenance
- **Batch Deployment**: Deploy multiple apps in one session with automatic name resolution via `Find-WinGetPackage`
- **Enterprise Security**: Input validation, code injection prevention, secure credential handling
- **Error Resilience**: Individual error handling per app with deployment result tracking
- **WhatIf Support**: Preview changes before deployment with `-WhatIf`/`-Confirm` parameters
- **Curated App Library**: 74 popular enterprise applications across 9 categories
- **Declarative Portfolio Sync**: GitOps-style YAML configuration — define your desired Intune app state and sync it with drift detection

## 🔒 Security & Quality

This module has undergone comprehensive enterprise security review and implements:

- ✅ Input validation on all user-provided parameters
- ✅ Code injection prevention in generated scripts
- ✅ Secure credential handling with environment variable support
- ✅ Server-side OData filtering for performance
- ✅ Comprehensive error handling with result tracking
- ✅ Production-ready for Fortune 100 enterprise environments

## 📋 Requirements

### System Requirements

- **Operating System**: Windows 10/11 or Windows Server 2016+
- **PowerShell**: Version 5.1 (PowerShell 7 not supported - script will error)
- **WinGet**: Auto-installed if missing
- **Network Access**: Required to `aka.ms`, `github.com`, and Microsoft Graph endpoints

### PowerShell Modules (Auto-installed)

- `Microsoft.Graph.Authentication` - Graph API authentication
- `SvRooij.ContentPrep.Cmdlet` - IntuneWin package creation
- `powershell-yaml` - YAML parsing for portfolio sync

### Microsoft Graph API Permissions

The following delegated or application permissions are required (admin consent needed):

| Permission | Scope | Purpose |
|------------|-------|---------|
| `DeviceManagementApps.ReadWrite.All` | Required | Create and manage Win32 apps |
| `DeviceManagementConfiguration.ReadWrite.All` | Required | Create Proactive Remediations |
| `Group.ReadWrite.All` | Required | Create and manage Azure AD groups |
| `GroupMember.ReadWrite.All` | Required | Assign apps to groups |

**First-time setup:**

```powershell
# Interactive authentication (prompts for consent)
Connect-MgGraph -Scopes "DeviceManagementApps.ReadWrite.All","DeviceManagementConfiguration.ReadWrite.All","Group.ReadWrite.All","GroupMember.ReadWrite.All"
```

### Intune Licensing

- **Basic Deployment**: Microsoft Intune Plan 1 or higher
- **Proactive Remediations**: Requires Intune Plan 2, Intune Suite, or Windows 365 Enterprise

## 🚀 Quick Start

### Installation

```powershell
# Install from PowerShell Gallery
Install-Module -Name WingetIntunePublisher -Scope CurrentUser

# Or for all users (requires admin)
Install-Module -Name WingetIntunePublisher -Scope AllUsers
```

### Basic Usage

```powershell
# Import the module (auto-imported if installed from PSGallery)
Import-Module WingetIntunePublisher

# Deploy a single app (interactive authentication)
Invoke-WingetIntunePublisher -appid "Google.Chrome"

# Deploy multiple apps (names auto-resolved from WinGet)
Invoke-WingetIntunePublisher -appid "Google.Chrome","7zip.7zip","Notepad++.Notepad++"

# Deploy with explicit app names
Invoke-WingetIntunePublisher -appid "Google.Chrome","Notepad++.Notepad++" -appname "Google Chrome","Notepad++"

# Preview deployment without making changes
Invoke-WingetIntunePublisher -appid "Google.Chrome" -WhatIf

# Force re-deployment even if app exists
Invoke-WingetIntunePublisher -appid "Google.Chrome" -Force
```

### Authentication Options

#### Interactive Authentication (Recommended for Manual Use)

```powershell
# First time: consent to permissions
Connect-MgGraph -Scopes "DeviceManagementApps.ReadWrite.All","DeviceManagementConfiguration.ReadWrite.All","Group.ReadWrite.All","GroupMember.ReadWrite.All"

# Deploy apps (uses existing session)
Invoke-WingetIntunePublisher -appid "Google.Chrome"
```

#### App-Based Authentication (Recommended for Automation)

**Using Parameters (Less Secure):**

```powershell
$clientId = "your-app-registration-id"
$tenantId = "your-tenant-id"
$secret = "your-client-secret"

Invoke-WingetIntunePublisher -appid "Google.Chrome" `
    -tenant $tenantId `
    -clientid $clientId `
    -clientsecret $secret
```

**Using Environment Variables (More Secure):**

```powershell
# Set environment variables (persist across sessions)
$env:INTUNE_TENANT_ID = "your-tenant.onmicrosoft.com"
$env:INTUNE_CLIENT_ID = "your-app-registration-id"
$env:INTUNE_CLIENT_SECRET = "your-client-secret"

# Deploy without exposing credentials in command
Invoke-WingetIntunePublisher -appid "Google.Chrome" `
    -tenant $env:INTUNE_TENANT_ID `
    -clientid $env:INTUNE_CLIENT_ID `
    -clientsecret $env:INTUNE_CLIENT_SECRET
```

### Error Handling & Results

```powershell
# Capture deployment results for error handling
$results = Invoke-WingetIntunePublisher -appid "Google.Chrome","Invalid.App","7zip.7zip"

# Check deployment summary
$results | Format-Table AppId, Status, Error

# Filter failed deployments
$failures = $results | Where-Object Status -eq 'Failed'
if ($failures) {
    Write-Warning "Failed deployments: $($failures.Count)"
    $failures | ForEach-Object {
        Write-Host "  - $($_.AppId): $($_.Error)" -ForegroundColor Red
    }
}

# Export results for reporting
$results | Export-Csv -Path "deployment-results.csv" -NoTypeInformation
```

### Advanced Options

```powershell
# Custom group names
Invoke-WingetIntunePublisher -appid "Google.Chrome" `
    -installgroupname "Chrome-Required-Users" `
    -uninstallgroupname "Chrome-Removal-Users"

# Control availability assignments
Invoke-WingetIntunePublisher -appid "7zip.7zip" -availableinstall "Both"  # User + Device
Invoke-WingetIntunePublisher -appid "VLC.VLC" -availableinstall "Device"   # Device only
Invoke-WingetIntunePublisher -appid "Zoom.Zoom" -availableinstall "None"   # Required only
```

## 📦 Deploy Popular Apps by Category

The module includes curated collections of 74 popular enterprise applications organized by category.

### Quick Category Deployment

```powershell
# Deploy all browsers (6 apps)
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
Invoke-PopularAppsDeployment -Category Media `
    -Tenant "contoso.onmicrosoft.com" `
    -ClientId "app-guid" `
    -ClientSecret "secret"
```

### Available Categories

#### Browsers (6 apps)

| App Name | WinGet Package ID |
|----------|-------------------|
| Google Chrome | `Google.Chrome` |
| Mozilla Firefox | `Mozilla.Firefox` |
| Microsoft Edge | `Microsoft.Edge` |
| Opera | `Opera.Opera` |
| Vivaldi | `Vivaldi.Vivaldi` |
| LibreWolf | `LibreWolf.LibreWolf` |

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

#### Communication (7 apps)

| App Name | WinGet Package ID |
|----------|-------------------|
| Microsoft Teams | `Microsoft.Teams` |
| Zoom | `Zoom.Zoom` |
| Slack | `SlackTechnologies.Slack` |
| Discord | `Discord.Discord` |
| Cisco Webex | `Cisco.CiscoWebexMeetings` |
| RingCentral | `RingCentral.RingCentral` |
| Telegram Desktop | `Telegram.TelegramDesktop` |

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

#### Media (8 apps)

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
| Process Explorer | `Microsoft.Sysinternals.ProcessExplorer` |
| Autoruns | `Microsoft.Sysinternals.Autoruns` |
| WinDirStat | `WinDirStat.WinDirStat` |
| Rufus | `Rufus.Rufus` |
| Balena Etcher | `Balena.Etcher` |

#### Security (4 apps)

| App Name | WinGet Package ID |
|----------|-------------------|
| KeePassXC | `KeePassXCTeam.KeePassXC` |
| Bitwarden | `Bitwarden.Bitwarden` |
| Malwarebytes | `Malwarebytes.Malwarebytes` |
| Gpg4win | `GnuPG.Gpg4win` |

#### Graphics (7 apps)

| App Name | WinGet Package ID |
|----------|-------------------|
| GIMP | `GIMP.GIMP.2` |
| Inkscape | `Inkscape.Inkscape` |
| Paint.NET | `dotPDN.PaintDotNet` |
| IrfanView | `IrfanSkiljan.IrfanView` |
| XnView MP | `XnSoft.XnViewMP` |
| Figma | `Figma.Figma` |
| Canva | `Canva.Canva` |

#### Remote (5 apps)

| App Name | WinGet Package ID |
|----------|-------------------|
| TeamViewer | `TeamViewer.TeamViewer` |
| Chrome Remote Desktop | `Google.ChromeRemoteDesktopHost` |
| VNC Viewer | `RealVNC.VNCViewer` |
| Microsoft Remote Desktop | `Microsoft.RemoteDesktopClient` |
| Parsec | `Parsec.Parsec` |

**Total: 74 curated applications across 9 categories**

## 📋 Declarative Portfolio Sync (GitOps for Intune)

Define your entire Intune app portfolio in a single YAML file and sync it declaratively. `Sync-IntunePortfolio` compares the YAML against your live Intune tenant, deploys missing apps, and optionally removes orphans — like Terraform for Intune apps.

### Portfolio YAML Format

```yaml
# portfolio.yml
defaults:
  availableInstall: User       # User | Device | Both | None

apps:
  - id: Google.Chrome
    name: Google Chrome
    availableInstall: Both     # Override default

  - id: Microsoft.Teams
    name: Microsoft Teams
    availableInstall: Device
    groups:                    # Custom Azure AD group names
      install: Org-Teams-Required
      uninstall: Org-Teams-Uninstall

  - id: 7zip.7zip
    name: 7-Zip

  - id: Notepad++.Notepad++
    name: Notepad++
    force: true                # Always redeploy this app
```

See [`examples/portfolio.yml`](examples/portfolio.yml) for a full 17-app example across 7 categories.

### Drift Detection (Dry Run)

```powershell
# See what's out of sync without making any changes
Sync-IntunePortfolio -Path ./portfolio.yml -WhatIf
```

Output shows a sync plan:

```
═══════════════════════════════════════════
  Intune Portfolio Sync Plan
═══════════════════════════════════════════
  Portfolio apps: 4 | Deploy: 2 | Up to date: 2 | Orphaned: 1

  TO DEPLOY:
    + Notepad++.Notepad++ (Notepad++) (new)
    + 7zip.7zip (7-Zip) (new)

  UP TO DATE:
    = Google.Chrome (Google Chrome)
    = Microsoft.Teams (Microsoft Teams)

  ORPHANED (use -RemoveAbsent to remove):
    - Old Legacy App
═══════════════════════════════════════════
```

### Deploy Missing Apps

```powershell
# Interactive authentication
Sync-IntunePortfolio -Path ./portfolio.yml

# App-based authentication
Sync-IntunePortfolio -Path ./portfolio.yml `
    -Tenant "contoso.onmicrosoft.com" `
    -ClientId "your-app-guid" `
    -ClientSecret "your-secret"
```

### Full Reconciliation

```powershell
# Deploy missing + remove apps no longer in the YAML
Sync-IntunePortfolio -Path ./portfolio.yml -RemoveAbsent

# Force redeploy everything
Sync-IntunePortfolio -Path ./portfolio.yml -Force
```

### GitOps Workflow

1. **Define** your app portfolio in `portfolio.yml` (checked into Git)
2. **PR review** — team reviews app additions/removals
3. **Merge** — the `deploy.yml` GitHub Action syncs Intune to match:

```bash
gh workflow run deploy.yml -f mode="portfolio" -f portfolio_file="examples/portfolio.yml"
```

### Result Handling

```powershell
$results = Sync-IntunePortfolio -Path ./portfolio.yml

# Inspect results
$results.Deployed   # Apps that were newly deployed
$results.Skipped    # Apps already up to date
$results.Removed    # Orphaned apps that were removed
$results.Failed     # Operations that failed (with .Error details)

# Check for failures
if ($results.Failed.Count -gt 0) {
    $results.Failed | ForEach-Object { Write-Host "FAILED: $($_.AppId) — $($_.Error)" }
}
```

## 🔄 What the Script Does

The module automates the entire deployment workflow:

1. **Prerequisites**: Ensures required PowerShell modules are installed
2. **Authentication**: Connects to Microsoft Graph (interactive or app-based)
3. **Package Creation**: Generates install/uninstall/detection scripts per app
4. **Packaging**: Creates `.intunewin` packages using IntuneWin32App wrapper
5. **Icon Search**: Attempts to find application icons (optional)
6. **Upload**: Uploads Win32 app to Intune with metadata and default return codes
7. **Group Management**: Creates or reuses Azure AD groups for install/uninstall targeting
8. **Assignment**: Assigns the app to specified groups with chosen intent
9. **Proactive Remediation**: Creates auto-update remediations (if licensed and requested)
10. **Result Tracking**: Returns deployment status for each app

All resources created by this module are automatically tagged with a standardized description identifier for easy management and cleanup.

## 🗑️ Managing Deployed Apps

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

## 📖 Parameter Reference

### Invoke-WingetIntunePublisher

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `-appid` | string[] | Yes | - | One or more WinGet package IDs (e.g., `Google.Chrome`) |
| `-appname` | string[] | No | Auto-resolved | Display names for apps (aligned to `-appid`) |
| `-tenant` | string | No | Interactive | Tenant ID or domain for app-based auth |
| `-clientid` | string | No | Interactive | App registration client ID (GUID format) |
| `-clientsecret` | string | No | Interactive | App registration client secret |
| `-installgroupname` | string[] | No | `{AppName} Required` | Custom install group name(s) |
| `-uninstallgroupname` | string[] | No | `{AppName} Uninstall` | Custom uninstall group name(s) |
| `-availableinstall` | string | No | `User` | Availability assignment: `User`, `Device`, `Both`, `None` |
| `-Force` | switch | No | `$false` | Overwrite existing app with same name |
| `-WhatIf` | switch | No | `$false` | Preview changes without deployment |
| `-Confirm` | switch | No | `$false` | Prompt before each destructive operation |

**Input Validation:**

- `appid`: Max 255 chars, no special characters `<>:"|?*\`, validates against WinGet repository
- `clientid`: Must be valid GUID format
- `tenant`: Alphanumeric with dots/hyphens only (e.g., `contoso.onmicrosoft.com`)

### Sync-IntunePortfolio

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `-Path` | string | Yes | - | Path to the portfolio YAML file |
| `-Tenant` | string | No | Interactive | Tenant ID or domain for app-based auth |
| `-ClientId` | string | No | Interactive | App registration client ID (GUID format) |
| `-ClientSecret` | string | No | Interactive | App registration client secret |
| `-Force` | switch | No | `$false` | Force redeployment of all apps, even if already present |
| `-RemoveAbsent` | switch | No | `$false` | Remove orphaned managed apps not in the portfolio |
| `-WhatIf` | switch | No | `$false` | Preview sync plan without making changes (drift detection) |
| `-Confirm` | switch | No | `$true` | Prompt before each deployment or removal operation |

**Portfolio YAML Schema:**

| Field | Level | Required | Default | Description |
|-------|-------|----------|---------|-------------|
| `defaults.availableInstall` | Global | No | `User` | Default availability for all apps |
| `apps[].id` | Per-app | Yes | - | WinGet package ID |
| `apps[].name` | Per-app | No | Auto-resolved | Display name (resolved from WinGet if omitted) |
| `apps[].availableInstall` | Per-app | No | Inherits default | Override availability for this app |
| `apps[].groups.install` | Per-app | No | `{AppName} Required` | Custom install group name |
| `apps[].groups.uninstall` | Per-app | No | `{AppName} Uninstall` | Custom uninstall group name |
| `apps[].force` | Per-app | No | `false` | Always redeploy this specific app |

## 🏗️ Repository Structure

```
WingetIntunePublisher/
├── .github/workflows/               # CI/CD pipelines
│   ├── ci.yml                            # PSScriptAnalyzer → Pester tests → Build
│   └── deploy.yml                        # Manual app deployment to Intune
├── Public/                          # Exported functions (user-facing)
│   ├── Invoke-WingetIntunePublisher.ps1  # Main cmdlet entrypoint
│   ├── Invoke-PopularAppsDeployment.ps1  # Category-based batch deployment
│   ├── Sync-IntunePortfolio.ps1          # Declarative portfolio sync (GitOps)
│   ├── DeploymentOrchestration.ps1       # Deploy-WinGetApp orchestrator
│   ├── WingetFunctions.ps1               # WinGet package operations
│   ├── GraphHelpers.ps1                  # Graph API authentication
│   ├── UtilityFunctions.ps1              # Logging and utilities
│   ├── Get-PopularAppsByCategory.ps1     # Curated app library
│   └── Remove-WingetIntuneApps.ps1       # Cleanup deployed apps
├── Private/                         # Internal helper functions
│   ├── Win32AppHelpers.ps1               # Win32 app creation/upload
│   ├── AzureStorageHelpers.ps1           # Blob storage chunked upload
│   ├── GroupManagement.ps1               # Azure AD group operations
│   ├── ScriptGeneration.ps1              # Install/uninstall script generation
│   └── PortfolioHelpers.ps1              # Portfolio parsing, diffing, reporting
├── Tests/                           # Pester test suites
│   ├── WingetIntunePublisher.Tests.ps1   # Module import & integration tests
│   ├── DeploymentOrchestration.Tests.ps1 # Deployment workflow tests
│   ├── CoreFunctions.Tests.ps1           # Core function unit tests
│   └── Portfolio.Tests.ps1               # Portfolio sync unit tests
├── Examples/                        # Sample configurations
│   └── portfolio.yml                     # Example portfolio YAML (17 apps)
├── Dev/                             # Development utilities
│   └── Check-AppIcon.ps1                 # Icon availability checker
├── WingetIntunePublisher.psm1       # Module loader
├── WingetIntunePublisher.psd1       # Module manifest
├── WingetIntunePublisher.build.ps1  # InvokeBuild build script
└── README.md                        # This file
```

## 🔄 CI/CD with GitHub Actions

The repository includes two GitHub Actions workflows for automated testing and deployment.

### CI Pipeline (`ci.yml`)

Runs automatically on push to `main` and on pull requests:

1. **Code Quality**: PSScriptAnalyzer linting (Error + Warning severity)
2. **Build and Test**: Pester tests on Windows (106 tests)
3. **Publish and Release**: Module packaging (triggered on version tags)

### Deploy Pipeline (`deploy.yml`)

Manual workflow dispatch to deploy apps to Intune. Supports two modes:

**App IDs mode** — deploy specific apps imperatively:

```bash
gh workflow run deploy.yml -f mode="app_ids" -f app_ids="7zip.7zip,Google.Chrome" -f force="true"
```

**Portfolio mode** — declarative sync from a YAML file:

```bash
gh workflow run deploy.yml -f mode="portfolio" -f portfolio_file="examples/portfolio.yml"
gh workflow run deploy.yml -f mode="portfolio" -f portfolio_file="examples/portfolio.yml" -f remove_absent="true"
```

**Required GitHub Secrets:**

| Secret | Description |
|--------|-------------|
| `TENANT_ID` | Azure AD tenant ID |
| `CLIENT_ID` | App registration client ID |
| `CLIENT_SECRET` | App registration client secret |

### Setting Up Your Own Repository

1. Fork or clone this repository
2. Create an Azure AD App Registration with the [required permissions](#microsoft-graph-api-permissions)
3. Add `TENANT_ID`, `CLIENT_ID`, and `CLIENT_SECRET` as repository secrets
4. Trigger the deploy workflow with your desired app IDs

## 🔍 Troubleshooting

### Common Issues

#### "PowerShell 7 is not supported"

**Cause:** Module requires PowerShell 5.1 for WinGet packaging dependencies

**Solution:** Use Windows PowerShell 5.1 instead of PowerShell Core/7

```powershell
powershell.exe  # Use this instead of pwsh.exe
```

#### "Package not found in WinGet repository"

**Cause:** Invalid AppId or package not available in WinGet

**Solution:** Search WinGet repository first

```powershell
winget search "Chrome"
# Use exact ID from search results: Google.Chrome
```

#### "Access denied" or "Forbidden" Graph API errors

**Cause:** Missing Graph API permissions or lack of admin consent

**Solution:** Re-authenticate with correct scopes

```powershell
Disconnect-MgGraph
Connect-MgGraph -Scopes "DeviceManagementApps.ReadWrite.All","DeviceManagementConfiguration.ReadWrite.All","Group.ReadWrite.All","GroupMember.ReadWrite.All"
# Admin must consent in Azure AD portal for app-based auth
```

#### "App already exists" error

**Cause:** Win32 app with same display name already exists in Intune

**Solution:** Use `-Force` to overwrite or rename the app

```powershell
Invoke-WingetIntunePublisher -appid "Google.Chrome" -Force
# Or use custom name:
Invoke-WingetIntunePublisher -appid "Google.Chrome" -appname "Chrome 2024"
```

#### Proactive Remediation not created

**Cause:** Missing Intune Plan 2/Suite license

**Solution:** Verify licensing or skip remediation creation (app deployment will still succeed)

#### Graph API timeout or throttling

**Cause:** Too many API calls in short period (429 errors)

**Solution:** Module has built-in retry for throttling; for large batches, deploy in smaller chunks

```powershell
# Instead of deploying 50 apps at once, batch them:
$allApps = @("Google.Chrome","Mozilla.Firefox") # ... 50 apps
$batches = 0..4 | ForEach-Object { $allApps[($_ * 10)..(($_ + 1) * 10 - 1)] }
foreach ($batch in $batches) {
    Invoke-WingetIntunePublisher -appid $batch
    Start-Sleep -Seconds 30  # Rate limiting
}
```

### Log Files

The module creates detailed logs in `$env:TEMP`:

- **Main Log**: `intune-{timestamp}.log` - Overall deployment activity
- **App Logs**: `intuneauto-{timestamp}.log` - WinGet operations
- **Device Logs**: `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\{AppId}_Install.log` - Client-side installation logs

```powershell
# View recent logs
Get-ChildItem $env:TEMP -Filter "intune-*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 5

# Tail the latest log
$latestLog = Get-ChildItem $env:TEMP -Filter "intune-*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
Get-Content $latestLog.FullName -Tail 50 -Wait
```

### Validation Testing

```powershell
# Test parameter validation
Invoke-WingetIntunePublisher -appid "" -WhatIf  # Should fail: empty AppId
Invoke-WingetIntunePublisher -appid "app<>id" -WhatIf  # Should fail: invalid chars

# Test authentication
Connect-MgGraph  # Should prompt for interactive auth
Get-MgContext    # Verify scopes include required permissions

# Test WinGet availability
Find-WinGetPackage -Id "Google.Chrome"  # Should return package info
```

## 📚 Additional Resources

- **Development Guide**: [CLAUDE.md](CLAUDE.md) - Architecture and contribution guidelines
- **Changelog**: [CHANGELOG.md](CHANGELOG.md) - Release notes

### External Documentation

- [Microsoft Intune Win32 App Management](https://learn.microsoft.com/en-us/mem/intune/apps/apps-win32-app-management)
- [WinGet Package Repository](https://github.com/microsoft/winget-pkgs)
- [Microsoft Graph API Reference](https://learn.microsoft.com/en-us/graph/api/overview)
- [Proactive Remediations Documentation](https://learn.microsoft.com/en-us/mem/analytics/proactive-remediations)

## 🤝 Support & Contributing

### Getting Help

- **Bug Reports**: [GitHub Issues](https://github.com/jorgeasaurus/WingetIntunePublisher/issues)
- **Feature Requests**: [GitHub Discussions](https://github.com/jorgeasaurus/WingetIntunePublisher/discussions)
- **Security Issues**: Email security concerns privately to the maintainer

### Contributing

Contributions welcome via pull requests! Please:

1. Review [CLAUDE.md](CLAUDE.md) for architecture guidelines
2. Run `Invoke-Pester -Path ./Tests` and ensure all tests pass
3. Update README.md if adding user-facing features
4. Follow existing PowerShell style conventions

### License

This project is licensed under the GNU General Public License v3.0.

---

## 🎯 Development Status

**Current Version:** v0.2.0

### Recent Updates

Version 0.2.0 introduces enterprise security improvements, comprehensive CI/CD via GitHub Actions, declarative portfolio sync (`Sync-IntunePortfolio`) with GitOps-style YAML configuration, extensive bug fixes (pipeline leaks, error propagation, SAS URI renewal), and 106 Pester tests with cross-model code review verification.

See [CHANGELOG.md](CHANGELOG.md) for complete release notes.

---

**⭐ If this module helps your organization, please star the repository!**
