# GraphHelpers.ps1
# Graph API and authentication helper functions

function Connect-ToGraph {
    <#
.SYNOPSIS
Authenticates to the Graph API via the Microsoft.Graph.Authentication module.

.DESCRIPTION
The Connect-ToGraph cmdlet is a wrapper cmdlet that helps authenticate to the Intune Graph API using the Microsoft.Graph.Authentication module. It leverages an Azure AD app ID and app secret for authentication or user-based auth.

.PARAMETER Tenant
Specifies the tenant (e.g. contoso.onmicrosoft.com) to which to authenticate.

.PARAMETER AppId
Specifies the Azure AD app ID (GUID) for the application that will be used to authenticate.

.PARAMETER AppSecret
Specifies the Azure AD app secret corresponding to the app ID that will be used to authenticate.

.PARAMETER Scopes
Specifies the user scopes for interactive authentication.

.EXAMPLE
Connect-ToGraph -TenantId $tenantID -AppId $app -AppSecret $secret

-#>
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $false)] [string]$Tenant,
        [Parameter(Mandatory = $false)] [string]$AppId,
        [Parameter(Mandatory = $false)] [string]$AppSecret,
        [Parameter(Mandatory = $false)] [string]$scopes
    )

    process {
        Import-Module Microsoft.Graph.Authentication

        # Guard: use interactive auth if no AppId provided
        if (-not $AppId) {
            try {
                Connect-MgGraph -Scopes $scopes -NoWelcome -ErrorAction Stop
                $context = Get-MgContext
                if (-not $context) {
                    throw "Failed to establish Graph connection - no context returned"
                }
                Write-Host "Connected to Intune tenant $($context.TenantId)" -ForegroundColor Green
                Write-IntuneLog "Connected to Intune tenant $($context.TenantId)"
            } catch {
                Write-Host "Failed to connect to Microsoft Graph: $_" -ForegroundColor Red
                Write-IntuneLog "Failed to connect to Microsoft Graph: $_"
                throw
            }
            return
        }

        # App-based authentication using client credentials
        try {
            $clientSecretSecure = ConvertTo-SecureString -String $AppSecret -AsPlainText -Force
            $credential = New-Object System.Management.Automation.PSCredential($AppId, $clientSecretSecure)
            Connect-MgGraph -TenantId $Tenant -ClientSecretCredential $credential -NoWelcome -ErrorAction Stop
            $context = Get-MgContext
            if (-not $context) {
                throw "Failed to establish Graph connection - no context returned"
            }
            Write-Host "Connected to Intune tenant $($context.TenantId) using app-based authentication" -ForegroundColor Green
            Write-IntuneLog "Connected to Intune tenant $($context.TenantId) using app-based authentication"
        } catch {
            Write-Host "Failed to connect to Microsoft Graph: $_" -ForegroundColor Red
            Write-IntuneLog "Failed to connect to Microsoft Graph: $_"
            throw
        }
    }
}

function Invoke-GraphPaged {
    <#
    .SYNOPSIS
    Performs paginated Graph API requests with efficient array handling.
    .PARAMETER Uri
    The Graph API URI to query.
    .PARAMETER Method
    HTTP method (default: GET).
    #>
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $true)] [string]$Uri,
        [string]$Method = "GET"
    )

    # Use List<T> instead of array += for better performance
    $results = [System.Collections.Generic.List[object]]::new()
    $response = Invoke-MgGraphRequest -Uri $Uri -Method $Method -OutputType PSObject

    if ($response.value) {
        $results.AddRange([array]$response.value)
    } else {
        $results.Add($response)
    }

    while ($response.'@odata.nextLink') {
        $response = Invoke-MgGraphRequest -Uri $response.'@odata.nextLink' -Method $Method -OutputType PSObject
        if ($response.value) {
            $results.AddRange([array]$response.value)
        }
    }

    return $results.ToArray()
}

function Get-IntuneApplication {
    <#
    .SYNOPSIS
    Gets applications from the Intune Graph API with optional filtering.
    .PARAMETER AppName
    Filter by application display name (exact match).
    .PARAMETER Filter
    OData filter string for custom filtering.
    .EXAMPLE
    Get-IntuneApplication -AppName "Google Chrome"
    Returns the specific app matching "Google Chrome"
    .EXAMPLE
    Get-IntuneApplication -Filter "startswith(displayName,'Microsoft')"
    Returns all apps starting with "Microsoft"
    .EXAMPLE
    Get-IntuneApplication
    Returns all applications configured in Intune
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$AppName,

        [Parameter(Mandatory = $false)]
        [string]$Filter
    )

    if ($AppName) {
        # Escape single quotes in the app name and build filter
        $escapedName = $AppName.Replace("'", "''")
        $filterString = "displayName eq '$escapedName'"
        $uri = "beta/deviceAppManagement/mobileApps?`$filter=$([uri]::EscapeDataString($filterString))"
    }
    elseif ($Filter) {
        $uri = "beta/deviceAppManagement/mobileApps?`$filter=$([uri]::EscapeDataString($Filter))"
    }
    else {
        $uri = "beta/deviceAppManagement/mobileApps/"
    }

    return Invoke-GraphPaged -Uri $uri
}
