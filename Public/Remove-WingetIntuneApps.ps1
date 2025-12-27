function Remove-WingetIntuneApps {
    <#
    .SYNOPSIS
        Removes Intune apps deployed via WingetIntunePublisher along with their assignment groups and remediations.

    .DESCRIPTION
        This function identifies and removes Win32 apps in Microsoft Intune that were deployed using
        WingetIntunePublisher (identified by their description). It also removes associated Azure AD groups
        and Proactive Remediations.

    .PARAMETER AppName
        Optional filter for app display name (supports wildcards). If not specified, processes all WingetIntunePublisher apps.

    .PARAMETER WhatIf
        Shows what would be deleted without actually performing the deletion.

    .PARAMETER Confirm
        Prompts for confirmation before deleting each app.

    .EXAMPLE
        Remove-WingetIntuneApps
        Removes all apps deployed via WingetIntunePublisher (prompts for confirmation).

    .EXAMPLE
        Remove-WingetIntuneApps -AppName "Google Chrome"
        Removes only Google Chrome if it was deployed via WingetIntunePublisher.

    .EXAMPLE
        Remove-WingetIntuneApps -AppName "*Adobe*" -WhatIf
        Shows what Adobe apps would be removed without actually deleting them.

    .EXAMPLE
        Remove-WingetIntuneApps -Confirm:$false
        Removes all WingetIntunePublisher apps without confirmation prompts.

    .NOTES
        Requires: Microsoft.Graph.Authentication module
        Permissions: DeviceManagementApps.ReadWrite.All, Group.ReadWrite.All, DeviceManagementConfiguration.ReadWrite.All
    #>

    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $false)]
        [string]$AppName = "*"
    )

    Write-Host "`n=== WingetIntunePublisher App Removal ===" -ForegroundColor Cyan
    Write-Host "This will remove apps and their associated groups and remediations.`n" -ForegroundColor Yellow

    # Define the identifier for WingetIntunePublisher apps
    $wingetPublisherTag = "Imported with Winget Intune Publisher - github.com/jorgeasaurus/WingetIntunePublisher"

    # Fetch all Win32 apps
    Write-Host "Fetching Win32 apps from Intune..." -ForegroundColor Cyan
    try {
        $uri = "beta/deviceAppManagement/mobileApps?`$filter=isof('microsoft.graph.win32LobApp')"
        $allApps = (Invoke-MgGraphRequest -Uri $uri -Method GET).value
        Write-Host "Found $($allApps.Count) Win32 apps in Intune" -ForegroundColor Gray
    } catch {
        Write-Error "Failed to fetch apps: $_"
        return
    }

    # Filter for WingetIntunePublisher apps
    $wingetApps = $allApps | Where-Object {
        $_.description -and $_.description -match [regex]::Escape($wingetPublisherTag)
    }

    if (-not $wingetApps) {
        Write-Host "`nNo apps found that were deployed via WingetIntunePublisher." -ForegroundColor Yellow
        return
    }

    # Further filter by app name if specified
    if ($AppName -ne "*") {
        $wingetApps = $wingetApps | Where-Object { $_.displayName -like $AppName }
    }

    if (-not $wingetApps) {
        Write-Host "`nNo apps found matching: $AppName" -ForegroundColor Yellow
        return
    }

    Write-Host "`nFound $($wingetApps.Count) WingetIntunePublisher apps to process:" -ForegroundColor Yellow
    $wingetApps | ForEach-Object {
        Write-Host "  - $($_.displayName)" -ForegroundColor Gray
    }

    $deletedApps = 0
    $deletedGroups = 0
    $deletedRemediations = 0
    $failedItems = @()

    foreach ($app in $wingetApps) {
        if ($PSCmdlet.ShouldProcess($app.displayName, "Remove app, groups, and remediations")) {
            Write-Host "`n=== Processing: $($app.displayName) ===" -ForegroundColor Cyan

            # 1. Find and delete associated groups
            Write-Host "Searching for associated groups..." -ForegroundColor Yellow
            try {
                # Groups have display names: "{AppName} Required" or "{AppName} Uninstall"
                # Groups have descriptions: "Install group for {AppName} - ..." or "Uninstall group for {AppName} - ..."
                $installGroupName = "$($app.displayName) Required"
                $uninstallGroupName = "$($app.displayName) Uninstall"

                $escapedInstallName = $installGroupName.Replace("'", "''")
                $escapedUninstallName = $uninstallGroupName.Replace("'", "''")

                $groupsUri = "beta/groups?`$filter=displayName eq '$escapedInstallName' or displayName eq '$escapedUninstallName'"
                $groups = (Invoke-MgGraphRequest -Uri $groupsUri -Method GET).value

                foreach ($group in $groups) {
                    try {
                        $deleteGroupUri = "beta/groups/$($group.id)"
                        Invoke-MgGraphRequest -Uri $deleteGroupUri -Method DELETE | Out-Null
                        Write-Host "  Deleted group: $($group.displayName)" -ForegroundColor Green
                        $deletedGroups++
                    } catch {
                        Write-Warning "Failed to delete group $($group.displayName): $_"
                        $failedItems += "Group: $($group.displayName)"
                    }
                }
            } catch {
                Write-Warning "Error searching for groups: $_"
            }

            # 2. Find and delete associated Proactive Remediation
            Write-Host "Searching for associated Proactive Remediation..." -ForegroundColor Yellow
            try {
                # Remediations have display names: "{AppName} Proactive Update"
                # Remediations have descriptions: "Auto-update remediation for {AppName} - ..."
                $remediationName = "$($app.displayName) Proactive Update"
                $escapedRemediationName = $remediationName.Replace("'", "''")
                $remediationsUri = "beta/deviceManagement/deviceHealthScripts?`$filter=displayName eq '$escapedRemediationName'"
                $remediations = (Invoke-MgGraphRequest -Uri $remediationsUri -Method GET).value

                foreach ($remediation in $remediations) {
                    try {
                        $deleteRemediationUri = "beta/deviceManagement/deviceHealthScripts/$($remediation.id)"
                        Invoke-MgGraphRequest -Uri $deleteRemediationUri -Method DELETE | Out-Null
                        Write-Host "  Deleted remediation: $($remediation.displayName)" -ForegroundColor Green
                        $deletedRemediations++
                    } catch {
                        Write-Warning "Failed to delete remediation $($remediation.displayName): $_"
                        $failedItems += "Remediation: $($remediation.displayName)"
                    }
                }
            } catch {
                Write-Warning "Error searching for remediations: $_"
            }

            # 3. Delete the app
            Write-Host "Deleting app..." -ForegroundColor Yellow
            try {
                $deleteAppUri = "beta/deviceAppManagement/mobileApps/$($app.id)"
                Invoke-MgGraphRequest -Uri $deleteAppUri -Method DELETE | Out-Null
                Write-Host "  Deleted app: $($app.displayName)" -ForegroundColor Green
                $deletedApps++
            } catch {
                Write-Error "Failed to delete app $($app.displayName): $_"
                $failedItems += "App: $($app.displayName)"
            }
        }
    }

    # Summary
    Write-Host "`n=== Deletion Summary ===" -ForegroundColor Cyan
    Write-Host "Apps deleted: $deletedApps" -ForegroundColor $(if ($deletedApps -gt 0) { "Green" } else { "Gray" })
    Write-Host "Groups deleted: $deletedGroups" -ForegroundColor $(if ($deletedGroups -gt 0) { "Green" } else { "Gray" })
    Write-Host "Remediations deleted: $deletedRemediations" -ForegroundColor $(if ($deletedRemediations -gt 0) { "Green" } else { "Gray" })

    if ($failedItems.Count -gt 0) {
        Write-Host "`nFailed deletions: $($failedItems.Count)" -ForegroundColor Red
        $failedItems | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    } else {
        Write-Host "`nAll items deleted successfully!`n" -ForegroundColor Green
    }
}
