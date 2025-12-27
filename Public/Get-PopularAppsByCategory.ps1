function Get-PopularAppsByCategory {
    <#
    .SYNOPSIS
    Returns a list of popular applications organized by category.

    .DESCRIPTION
    This function provides curated lists of popular applications commonly deployed in enterprise environments,
    organized by category. Each app includes the WinGet package ID and a display name suitable for Intune deployment.

    .PARAMETER Category
    The category of applications to return. Valid categories include:
    - Browsers: Web browsers (Chrome, Firefox, Edge, Brave, etc.)
    - Productivity: Office productivity tools (Office, Adobe Reader, Notepad++, etc.)
    - Communication: Chat and collaboration tools (Teams, Zoom, Slack, Discord, etc.)
    - Development: Developer tools (VS Code, Git, Python, Node.js, etc.)
    - Media: Media players and editors (VLC, Spotify, Audacity, etc.)
    - Utilities: System utilities (7-Zip, WinRAR, Everything, TreeSize, etc.)
    - Security: Security and VPN tools (BitDefender, NordVPN, KeePass, etc.)
    - Graphics: Graphics and design tools (GIMP, Inkscape, Paint.NET, etc.)
    - Remote: Remote access tools (TeamViewer, AnyDesk, Chrome Remote Desktop, etc.)
    - All: Returns all categories

    .PARAMETER ReturnAsObject
    If specified, returns objects with AppId and AppName properties instead of a hashtable.

    .EXAMPLE
    Get-PopularAppsByCategory -Category Browsers
    Returns a hashtable of popular web browsers with their WinGet IDs and display names.

    .EXAMPLE
    Get-PopularAppsByCategory -Category Development -ReturnAsObject
    Returns an array of objects containing popular development tools.

    .EXAMPLE
    Get-PopularAppsByCategory -Category All
    Returns all popular apps across all categories.

    .EXAMPLE
    $devApps = Get-PopularAppsByCategory -Category Productivity -ReturnAsObject
    Invoke-WingetIntunePublisher -appid $devApps.AppId
    Deploy all development tools to Intune with a single authentication session.
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet(
            'Browsers',
            'Productivity',
            'Communication',
            'Development',
            'Media',
            'Utilities',
            'Security',
            'Graphics',
            'Remote',
            'All'
        )]
        [string]$Category,

        [Parameter(Mandatory = $false)]
        [switch]$ReturnAsObject
    )

    # Define popular apps by category
    $popularApps = @{
        Browsers = @{
            'Google.Chrome' = 'Google Chrome'
            'Mozilla.Firefox' = 'Mozilla Firefox'
            'Microsoft.Edge' = 'Microsoft Edge'
            'BraveSoftware.BraveBrowser' = 'Brave Browser'
            'Opera.Opera' = 'Opera'
            'Vivaldi.Vivaldi' = 'Vivaldi'
            'LibreWolf.LibreWolf' = 'LibreWolf'
            'Chromium.Chromium' = 'Chromium'
        }

        Productivity = @{
            'Adobe.Acrobat.Reader.64-bit' = 'Adobe Acrobat Reader'
            'Notepad++.Notepad++' = 'Notepad++'
            'Microsoft.Office' = 'Microsoft Office'
            'TheDocumentFoundation.LibreOffice' = 'LibreOffice'
            'Notion.Notion' = 'Notion'
            'Obsidian.Obsidian' = 'Obsidian'
            'Microsoft.PowerToys' = 'PowerToys'
            'Foxit.FoxitReader' = 'Foxit Reader'
            'SumatraPDF.SumatraPDF' = 'Sumatra PDF'
            'Evernote.Evernote' = 'Evernote'
        }

        Communication = @{
            'Microsoft.Teams' = 'Microsoft Teams'
            'Zoom.Zoom' = 'Zoom'
            'SlackTechnologies.Slack' = 'Slack'
            'Discord.Discord' = 'Discord'
            'Cisco.CiscoWebexMeetings' = 'Cisco Webex'
            'RingCentral.RingCentral' = 'RingCentral'
            'Microsoft.Skype' = 'Skype'
            'Telegram.TelegramDesktop' = 'Telegram Desktop'
            'WhatsApp.WhatsApp' = 'WhatsApp'
        }

        Development = @{
            'Microsoft.VisualStudioCode' = 'Visual Studio Code'
            'Git.Git' = 'Git'
            'GitHub.GitHubDesktop' = 'GitHub Desktop'
            'Python.Python.3.12' = 'Python 3.12'
            'OpenJS.NodeJS' = 'Node.js'
            'Microsoft.VisualStudio.2022.Community' = 'Visual Studio 2022 Community'
            'JetBrains.IntelliJIDEA.Community' = 'IntelliJ IDEA Community'
            'Docker.DockerDesktop' = 'Docker Desktop'
            'Postman.Postman' = 'Postman'
            'Microsoft.WindowsTerminal' = 'Windows Terminal'
            'WinSCP.WinSCP' = 'WinSCP'
            'PuTTY.PuTTY' = 'PuTTY'
            'CoreyButler.NVMforWindows' = 'NVM for Windows'
            'Microsoft.PowerShell' = 'PowerShell'
        }

        Media = @{
            'VideoLAN.VLC' = 'VLC Media Player'
            'Spotify.Spotify' = 'Spotify'
            'Audacity.Audacity' = 'Audacity'
            'HandBrake.HandBrake' = 'HandBrake'
            'OBSProject.OBSStudio' = 'OBS Studio'
            'Apple.iTunes' = 'iTunes'
            'AIMP.AIMP' = 'AIMP'
            'clsid2.mpc-hc' = 'MPC-HC'
            'Kodi.Kodi' = 'Kodi'
        }

        Utilities = @{
            '7zip.7zip' = '7-Zip'
            'RARLab.WinRAR' = 'WinRAR'
            'voidtools.Everything' = 'Everything Search'
            'JAMSoftware.TreeSize.Free' = 'TreeSize Free'
            'Greenshot.Greenshot' = 'Greenshot'
            'ShareX.ShareX' = 'ShareX'
            'Piriform.CCleaner' = 'CCleaner'
            'Microsoft.Sysinternals.PsTools' = 'Sysinternals PsTools'
            'Sysinternals.ProcessExplorer' = 'Process Explorer'
            'Sysinternals.Autoruns' = 'Autoruns'
            'WinDirStat.WinDirStat' = 'WinDirStat'
            'Rufus.Rufus' = 'Rufus'
            'Balena.Etcher' = 'Balena Etcher'
        }

        Security = @{
            'KeePassXCTeam.KeePassXC' = 'KeePassXC'
            'Bitwarden.Bitwarden' = 'Bitwarden'
            '1Password.1Password' = '1Password'
            'NordVPN.NordVPN' = 'NordVPN'
            'ProtonTechnologies.ProtonVPN' = 'Proton VPN'
            'Malwarebytes.Malwarebytes' = 'Malwarebytes'
            'GnuPG.Gpg4win' = 'Gpg4win'
            'VeraCrypt.VeraCrypt' = 'VeraCrypt'
        }

        Graphics = @{
            'GIMP.GIMP' = 'GIMP'
            'Inkscape.Inkscape' = 'Inkscape'
            'dotPDN.PaintDotNet' = 'Paint.NET'
            'Blender.Blender' = 'Blender'
            'IrfanSkiljan.IrfanView' = 'IrfanView'
            'XnSoft.XnViewMP' = 'XnView MP'
            'Figma.Figma' = 'Figma'
            'Canva.Canva' = 'Canva'
        }

        Remote = @{
            'TeamViewer.TeamViewer' = 'TeamViewer'
            'AnyDeskSoftwareGmbH.AnyDesk' = 'AnyDesk'
            'Google.ChromeRemoteDesktop' = 'Chrome Remote Desktop'
            'RealVNC.VNCViewer' = 'VNC Viewer'
            'Microsoft.RemoteDesktopClient' = 'Microsoft Remote Desktop'
            'Parsec.Parsec' = 'Parsec'
            'TightVNC.TightVNC' = 'TightVNC'
        }
    }

    # Return the requested category
    if ($Category -eq 'All') {
        $result = @{}
        foreach ($cat in $popularApps.Keys) {
            foreach ($app in $popularApps[$cat].GetEnumerator()) {
                if (-not $result.ContainsKey($app.Key)) {
                    $result[$app.Key] = $app.Value
                }
            }
        }
    } else {
        $result = $popularApps[$Category]
    }

    # Convert to object array if requested
    if ($ReturnAsObject) {
        $objectArray = @()
        foreach ($app in $result.GetEnumerator()) {
            $objectArray += [PSCustomObject]@{
                AppId = $app.Key
                AppName = $app.Value
            }
        }
        return $objectArray
    }

    return $result
}
