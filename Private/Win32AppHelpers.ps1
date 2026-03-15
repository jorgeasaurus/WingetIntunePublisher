# Win32AppHelpers.ps1
# Win32 App creation and management functions

# Configuration variables
$sleep = 30

# Icon repository configuration - search both folders
$script:IconRepoPaths = @(
    "https://raw.githubusercontent.com/jorgeasaurus/IntuneIcons/main/icons",
    "https://raw.githubusercontent.com/jorgeasaurus/IntuneIcons/main/companyportal"
)

function Get-AppIcon {
    <#
    .SYNOPSIS
    Searches for and downloads an app icon from the IntuneIcons GitHub repository.
    .DESCRIPTION
    Attempts to match a Winget AppId to an icon file using multiple naming patterns.
    Returns the icon as a base64-encoded object suitable for Intune.
    .PARAMETER AppId
    The Winget package ID (e.g., "Google.Chrome", "Notepad++.Notepad++").
    .PARAMETER AppName
    The display name of the application (used as fallback for matching).
    .OUTPUTS
    Returns a hashtable with Type and Value properties, or $null if no icon found.
    #>
    [cmdletbinding()]
    param(
        [Parameter(Mandatory = $true)] [string]$AppId,
        [Parameter(Mandatory = $false)] [string]$AppName
    )

    # Generate potential icon filenames from AppId
    # AppId format is typically "Publisher.ProductName" (e.g., "Google.Chrome")
    $nameCandidates = @()

    # Split AppId into parts
    $parts = $AppId -split '\.'

    if ($parts.Count -ge 2) {
        $publisher = $parts[0]
        $product = ($parts[1..($parts.Count - 1)] -join '-')

        # Primary patterns based on repo naming convention (Vendor-Product.png)
        $nameCandidates += "$publisher-$product"           # Google-Chrome
        $nameCandidates += $product                         # Chrome
        $nameCandidates += "$publisher$product"             # GoogleChrome
    }

    # Add AppId with dots replaced by hyphens
    $nameCandidates += ($AppId -replace '\.', '-')          # Google-Chrome or Notepad++-Notepad++

    # Add AppName-based candidates if provided
    if ($AppName) {
        $cleanAppName = $AppName -replace '\s+', '-' -replace '[^a-zA-Z0-9\-]', ''
        $nameCandidates += $cleanAppName
        $nameCandidates += ($AppName -replace '\s+', '')
    }

    # Add just the product part without special chars
    if ($parts.Count -ge 2) {
        $cleanProduct = $parts[-1] -replace '[^a-zA-Z0-9]', ''
        $nameCandidates += $cleanProduct                    # NotepadPlusPlus for Notepad++
    }

    # Add pattern with ++ replaced by PP (common abbreviation, e.g., notepadPP)
    if ($AppId -match '\+\+') {
        $ppVariant = ($parts[-1] -replace '\+\+', 'PP') -replace '[^a-zA-Z0-9]', ''
        $nameCandidates += $ppVariant.ToLower()             # notepadPP
        $nameCandidates += $ppVariant                       # NotepadPP
    }

    # Remove duplicates and empty entries
    $nameCandidates = $nameCandidates | Where-Object { $_ } | Select-Object -Unique

    Write-Verbose "Searching for icon with candidates: $($nameCandidates -join ', ')"
    Write-Verbose "Searching for icon for $AppId"

    foreach ($repoPath in $script:IconRepoPaths) {
        foreach ($candidate in $nameCandidates) {
            $iconUrl = "$repoPath/$candidate.png"

            try {
                Write-Verbose "Trying icon URL: $iconUrl"

                $webClient = New-Object System.Net.WebClient
                $iconBytes = $webClient.DownloadData($iconUrl)
                $iconBase64 = [Convert]::ToBase64String($iconBytes)

                Write-Host "Found icon for $AppId at: $candidate.png" -ForegroundColor Green
                Write-Verbose "Found icon for $AppId`: $candidate.png"

                return @{
                    "@odata.type" = "#microsoft.graph.mimeContent"
                    type          = "image/png"
                    value         = $iconBase64
                }
            }
            catch {
                Write-Verbose "Icon not found at: $iconUrl"
                continue
            }
        }
    }

    Write-Host "No icon found for $AppId in repository" -ForegroundColor Yellow
    Write-Verbose "No icon found for $AppId"
    return $null
}

function Get-Win32AppBody {
    param
    (
        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$displayName,

        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$publisher,

        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$description,

        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$filename,

        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SetupFileName,

        [parameter(Mandatory = $true)]
        [ValidateSet('system', 'user')]
        $installExperience,

        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        $installCommandLine,

        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        $uninstallCommandLine,

        [parameter(Mandatory = $false)]
        [hashtable]$largeIcon
    )

    $body = @{
        "@odata.type"                      = "#microsoft.graph.win32LobApp"
        description                        = $description
        developer                          = ""
        displayName                        = $displayName
        fileName                           = $filename
        installCommandLine                 = "$installCommandLine"
        installExperience                  = @{ "runAsAccount" = "$installExperience" }
        informationUrl                     = $null
        isFeatured                         = $false
        minimumSupportedOperatingSystem    = @{ "v10_1607" = $true }
        msiInformation                     = $null
        notes                              = ""
        owner                              = ""
        privacyInformationUrl              = $null
        publisher                          = $publisher
        runAs32bit                         = $false
        setupFilePath                      = $SetupFileName
        uninstallCommandLine               = "$uninstallCommandLine"
    }
    if ($largeIcon) { $body.largeIcon = $largeIcon }

    $body
}

function Get-AppFileBody($name, $size, $sizeEncrypted, $manifest) {
    $body = @{ "@odata.type" = "#microsoft.graph.mobileAppContentFile" }
    $body.name = $name
    $body.size = $size
    $body.sizeEncrypted = $sizeEncrypted
    $body.manifest = $manifest
    $body.isDependency = $false
    $body
}

function Get-AppCommitBody($contentVersionId, $LobType) {
    $body = @{ "@odata.type" = "#$LobType" }
    $body.committedContentVersion = $contentVersionId
    $body
}

function Test-SourceFile {
    param
    (
        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        $SourceFile
    )

    if (!(Test-Path "$SourceFile")) {
        throw "Source File '$SourceFile' doesn't exist"
    }
}

function New-DetectionRule {
    [cmdletbinding()]
    param
    (
        [parameter(Mandatory = $true)]
        [Switch]$PowerShell,

        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]$ScriptFile,

        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        $enforceSignatureCheck,

        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        $runAs32Bit
    )

    if (!(Test-Path "$ScriptFile")) {
        throw "Could not find detection script file '$ScriptFile'"
    }

    $ScriptContent = [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes("$ScriptFile"))

    @{
        "@odata.type"       = "#microsoft.graph.win32LobAppPowerShellScriptDetection"
        enforceSignatureCheck = $enforceSignatureCheck
        runAs32Bit            = $runAs32Bit
        scriptContent         = "$ScriptContent"
    }
}

function Get-DefaultReturnCodes {
    <#
    .SYNOPSIS
    Returns the default return codes for Win32 apps in Intune
    #>
    @(
        @{ returnCode = 0;    type = "success" }
        @{ returnCode = 1707; type = "success" }
        @{ returnCode = 3010; type = "softReboot" }
        @{ returnCode = 1641; type = "hardReboot" }
        @{ returnCode = 1618; type = "retry" }
    )
}

function Get-IntuneWinXML {
    param
    (
        [Parameter(Mandatory = $true)]
        $SourceFile,

        [Parameter(Mandatory = $true)]
        $fileName,

        [Parameter(Mandatory = $false)]
        [ValidateSet("false", "true")]
        [string]$removeitem = "true"
    )

    Test-SourceFile "$SourceFile"

    $Directory = [System.IO.Path]::GetDirectoryName("$SourceFile")

    Add-Type -Assembly System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead("$SourceFile")

    $zip.Entries | Where-Object { $_.Name -like "$filename" } | ForEach-Object {
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($_, "$Directory\$filename", $true)
    }

    $zip.Dispose()

    [xml]$IntuneWinXML = Get-Content "$Directory\$filename"

    if ($removeitem -eq "true") { Remove-Item "$Directory\$filename" }

    return $IntuneWinXML
}

function Get-IntuneWinFile {
    param
    (
        [Parameter(Mandatory = $true)]
        $SourceFile,

        [Parameter(Mandatory = $true)]
        $fileName,

        [Parameter(Mandatory = $false)]
        [string]$Folder = "win32"
    )

    $Directory = [System.IO.Path]::GetDirectoryName("$SourceFile")

    if (!(Test-Path "$Directory\$folder")) {
        New-Item -ItemType Directory -Path "$Directory" -Name "$folder" | Out-Null
    }

    Add-Type -Assembly System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead("$SourceFile")

    $zip.Entries | Where-Object { $_.Name -like "$filename" } | ForEach-Object {
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($_, "$Directory\$folder\$filename", $true)
    }

    $zip.Dispose()

    return "$Directory\$folder\$filename"
}

function Invoke-UploadWin32Lob {
    <#
        .SYNOPSIS
        This function is used to upload a Win32 Application to the Intune Service
        .DESCRIPTION
        This function is used to upload a Win32 Application to the Intune Service
        .EXAMPLE
        Invoke-UploadWin32Lob "C:\Packages\package.intunewin" -publisher "Microsoft" -description "Package"
        This example uses all parameters required to add an intunewin File into the Intune Service
        .NOTES
        NAME: Invoke-UploadWin32Lob
        #>

    [cmdletbinding()]

    param
    (
        [parameter(Mandatory = $true, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [string]$SourceFile,

        [parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$displayName,

        [parameter(Mandatory = $true, Position = 2)]
        [ValidateNotNullOrEmpty()]
        [string]$publisher,

        [parameter(Mandatory = $true, Position = 3)]
        [ValidateNotNullOrEmpty()]
        [string]$description,

        [parameter(Mandatory = $true, Position = 4)]
        [ValidateNotNullOrEmpty()]
        $detectionRules,

        [parameter(Mandatory = $true, Position = 5)]
        [ValidateNotNullOrEmpty()]
        $returnCodes,

        [parameter(Mandatory = $false, Position = 6)]
        [ValidateNotNullOrEmpty()]
        [string]$installCmdLine,

        [parameter(Mandatory = $false, Position = 7)]
        [ValidateNotNullOrEmpty()]
        [string]$uninstallCmdLine,

        [parameter(Mandatory = $false, Position = 8)]
        [ValidateSet('system', 'user')]
        $installExperience = "system",

        [parameter(Mandatory = $false, Position = 9)]
        [hashtable]$largeIcon
    )

    try	{
        $LOBType = "microsoft.graph.win32LobApp"

        Write-Verbose "Testing if SourceFile '$SourceFile' Path is valid..."
        Test-SourceFile "$SourceFile"

        Write-Verbose "Creating JSON data to pass to the service..."
        $DetectionXML = Get-IntuneWinXML "$SourceFile" -fileName "detection.xml"

        if ($displayName) { $DisplayName = $displayName }
        else { $DisplayName = $DetectionXML.ApplicationInfo.Name }

        $FileName = $DetectionXML.ApplicationInfo.FileName
        $SetupFileName = $DetectionXML.ApplicationInfo.SetupFile
        $Ext = [System.IO.Path]::GetExtension($SetupFileName)

        $mobileAppBody = Get-Win32AppBody -displayName "$DisplayName" -publisher "$publisher" `
            -description $description -filename $FileName -SetupFileName "$SetupFileName" `
            -installExperience $installExperience -installCommandLine $installCmdLine `
            -uninstallCommandLine $uninstallcmdline -largeIcon $largeIcon

        if ($DetectionRules.'@odata.type' -contains "#microsoft.graph.win32LobAppPowerShellScriptDetection" -and @($DetectionRules).'@odata.type'.Count -gt 1) {
            throw "Detection rules cannot mix script-based and manual rules"
        }

        $mobileAppBody | Add-Member -MemberType NoteProperty -Name 'detectionRules' -Value $detectionRules

        if (-not $returnCodes) {
            Write-Warning "ReturnCodes required. Use Get-DefaultReturnCodes for defaults."
            break
        }
        $mobileAppBody | Add-Member -MemberType NoteProperty -Name 'returnCodes' -Value @($returnCodes)

        Write-Verbose "Creating application in Intune..."
        $mobileApp = Invoke-MgGraphRequest -Method POST -Uri "beta/deviceAppManagement/mobileApps/" -Body ($mobileAppBody | ConvertTo-Json) -ContentType "application/json" -OutputType PSObject -ErrorAction Stop

        if (-not $mobileApp -or -not $mobileApp.id) {
            throw "Graph API returned null response or missing app ID"
        }

        Write-Verbose "Creating Content Version in the service..."
        $appId = $mobileApp.id
        $contentVersionUri = "beta/deviceAppManagement/mobileApps/$appId/$LOBType/contentVersions"
        $contentVersion = Invoke-MgGraphRequest -Method POST -Uri $contentVersionUri -Body "{}" -ErrorAction Stop

        Write-Verbose "Getting Encryption Information for '$SourceFile'..."
        $encInfo = $DetectionXML.ApplicationInfo.EncryptionInfo
        $encryptionInfo = @{
            encryptionKey        = $encInfo.EncryptionKey
            macKey               = $encInfo.macKey
            initializationVector = $encInfo.initializationVector
            mac                  = $encInfo.mac
            profileIdentifier    = "ProfileVersion1"
            fileDigest           = $encInfo.fileDigest
            fileDigestAlgorithm  = $encInfo.fileDigestAlgorithm
        }
        $fileEncryptionInfo = @{ fileEncryptionInfo = $encryptionInfo }

        $IntuneWinFile = Get-IntuneWinFile "$SourceFile" -fileName "$filename"
        [int64]$Size = $DetectionXML.ApplicationInfo.UnencryptedContentSize
        $EncrySize = (Get-Item "$IntuneWinFile").Length

        Write-Verbose "Creating file entry in Azure for upload..."
        $contentVersionId = $contentVersion.id
        $fileBody = Get-AppFileBody "$FileName" $Size $EncrySize $null
        $filesUri = "beta/deviceAppManagement/mobileApps/$appId/$LOBType/contentVersions/$contentVersionId/files"
        $file = Invoke-MgGraphRequest -Method POST -Uri $filesUri -Body ($fileBody | ConvertTo-Json) -ErrorAction Stop

        Write-Verbose "Waiting for file entry URI..."
        $fileId = $file.id
        $fileUri = "beta/deviceAppManagement/mobileApps/$appId/$LOBType/contentVersions/$contentVersionId/files/$fileId"
        $file = Wait-FileProcessing $fileUri "AzureStorageUriRequest"

        Write-Verbose "Uploading file to Azure Storage..."
        Invoke-AzureStorageUpload $file.azureStorageUri "$IntuneWinFile" $fileUri

        Remove-Item "$IntuneWinFile" -Force

        Write-Verbose "Committing file..."
        $commitFileUri = "beta/deviceAppManagement/mobileApps/$appId/$LOBType/contentVersions/$contentVersionId/files/$fileId/commit"
        Invoke-MgGraphRequest -Uri $commitFileUri -Method POST -Body ($fileEncryptionInfo | ConvertTo-Json) -ErrorAction Stop | Out-Null

        Write-Verbose "Waiting for commit processing..."
        $file = Wait-FileProcessing $fileUri "CommitFile"

        Write-Verbose "Committing app version..."
        $commitAppUri = "beta/deviceAppManagement/mobileApps/$appId"
        $commitAppBody = Get-AppCommitBody $contentVersionId $LOBType
        Invoke-MgGraphRequest -Method PATCH -Uri $commitAppUri -Body ($commitAppBody | ConvertTo-Json) -ErrorAction Stop | Out-Null

        foreach ($i in 0..$sleep) {
            Write-Progress -Activity "Sleeping for $($sleep-$i) seconds" -PercentComplete ($i / $sleep * 100) -SecondsRemaining ($sleep - $i)
            Start-Sleep -s 1
        }

        return $mobileApp
    }
    catch {
        Write-Error "Aborting with exception: $($_.Exception.ToString())"
        throw
    }
}

function Wait-AppPublishing {
    <#
    .SYNOPSIS
    Waits for a Win32 app to be published in Intune.
    .PARAMETER AppId
    The ID of the application to wait for.
    .PARAMETER MaxRetries
    Maximum number of retries (default 30, each retry waits 10 seconds).
    #>
    param
    (
        [Parameter(Mandatory = $true)] [string]$AppId,
        [int]$MaxRetries = 30
    )

    Write-Host "Waiting for app to be published..." -ForegroundColor Yellow
    $retryCount = 0
    $isPublished = $false
    
    while (-not $isPublished -and $retryCount -lt $MaxRetries) {
        try {
            $app = Invoke-MgGraphRequest -Uri "beta/deviceAppManagement/mobileApps/$AppId" -Method GET -ErrorAction Stop

            if ($app.publishingState -eq "published") {
                $isPublished = $true
                Write-Host "App is now published" -ForegroundColor Green
            }
            else {
                Write-Host "App publishing state: $($app.publishingState). Waiting..." -ForegroundColor Yellow
                Start-Sleep -Seconds 10
                $retryCount++
            }
        }
        catch {
            Write-Host "Error checking app status: $_" -ForegroundColor Red
            Start-Sleep -Seconds 10
            $retryCount++
        }
    }
    
    if (-not $isPublished) {
        Write-Warning "App did not become published after $($MaxRetries * 10) seconds"
    }
    
    return $isPublished
}

function Grant-Win32AppAssignment {
    <#
    .SYNOPSIS
    Assigns a Win32 app to install and uninstall groups, with optional available deployment.
    .PARAMETER AppName
    The display name of the application in Intune.
    .PARAMETER InstallGroupId
    The Azure AD group ID for required installation.
    .PARAMETER UninstallGroupId
    The Azure AD group ID for uninstallation.
    .PARAMETER AvailableInstall
    Optional available deployment: Device, User, Both, or None (default).
    #>
    param
    (
        [Parameter(Mandatory = $true)] [string]$AppName,
        [Parameter(Mandatory = $true)] [string]$InstallGroupId,
        [Parameter(Mandatory = $true)] [string]$UninstallGroupId,
        [ValidateSet("Device", "User", "Both", "None")] [string]$AvailableInstall = "None"
    )

    $Application = Get-IntuneApplication | Where-Object { $_.displayName -eq $AppName -and $_.description -like "*Winget*" } | Select-Object -First 1
    if (-not $Application) {
        Write-Error "Application '$AppName' not found in Intune"
        return
    }

    # Wait for app to be published before assigning
    $isPublished = Wait-AppPublishing -AppId $Application.id
    if (-not $isPublished) {
        Write-Error "Application '$AppName' is not published. Cannot assign groups."
        return
    }

    # Helper to create assignment object
    function New-Assignment($intent, $targetType, $groupId = $null) {
        $assignment = @{
            "@odata.type" = "#microsoft.graph.mobileAppAssignment"
            intent        = $intent
            target        = @{ "@odata.type" = $targetType }
        }
        if ($groupId) {
            $assignment.target.groupId = $groupId
        }
        if ($intent -eq "available") {
            $assignment.settings = @{
                "@odata.type"                = "#microsoft.graph.win32LobAppAssignmentSettings"
                deliveryOptimizationPriority = "foreground"
                notifications                = "showAll"
                installTimeSettings          = $null
                restartSettings              = $null
            }
        }
        return $assignment
    }

    # Build assignments array
    $assignments = @(
        New-Assignment -intent "required" -targetType "#microsoft.graph.groupAssignmentTarget" -groupId $InstallGroupId
        New-Assignment -intent "uninstall" -targetType "#microsoft.graph.groupAssignmentTarget" -groupId $UninstallGroupId
    )

    # Add available assignments based on parameter
    switch ($AvailableInstall) {
        "Device" {
            Write-Host "Making available for devices"
            $assignments += New-Assignment -intent "available" -targetType "#microsoft.graph.allDevicesAssignmentTarget"
        }
        "User" {
            Write-Host "Making available for users"
            $assignments += New-Assignment -intent "available" -targetType "#microsoft.graph.allLicensedUsersAssignmentTarget"
        }
        "Both" {
            Write-Host "Making available for users and devices"
            $assignments += New-Assignment -intent "available" -targetType "#microsoft.graph.allLicensedUsersAssignmentTarget"
            $assignments += New-Assignment -intent "available" -targetType "#microsoft.graph.allDevicesAssignmentTarget"
        }
    }

    $body = @{ mobileAppAssignments = $assignments }
    Invoke-MgGraphRequest -Uri "beta/deviceAppManagement/mobileApps/$($Application.id)/assign" -Method POST -Body ($body | ConvertTo-Json -Depth 10) -ErrorAction Stop | Out-Null
}

function New-Win32App {
    [cmdletbinding()]
    param
    (
        $appid,
        $appname,
        $appfile,
        $installcmd,
        $uninstallcmd,
        $detectionfile,
        [hashtable]$largeIcon
    )
    # Defining Intunewin32 detectionRules
    $PSRule = New-DetectionRule -PowerShell -ScriptFile $detectionfile -enforceSignatureCheck $false -runAs32Bit $false

    # Creating Array for detection Rule
    $DetectionRule = @($PSRule)

    $ReturnCodes = Get-DefaultReturnCodes

    # Win32 Application Upload
    $uploadParams = @{
        SourceFile       = "$appfile"
        DisplayName      = "$appname"
        publisher        = "Winget"
        description      = "$appname $script:PublisherTag"
        detectionRules   = $DetectionRule
        returnCodes      = $ReturnCodes
        installCmdLine   = "$installcmd"
        uninstallCmdLine = "$uninstallcmd"
    }
    if ($largeIcon) { $uploadParams.largeIcon = $largeIcon }

    $appupload = Invoke-UploadWin32Lob @uploadParams

    return $appupload
}

function Test-ExistingIntuneApp {
    <#
    .SYNOPSIS
    Checks if an app already exists in Intune by name
    .PARAMETER AppName
    The display name of the application to check
    .RETURNS
    Hashtable with Exists (bool) and Apps (array) properties
    #>
    param(
        [Parameter(Mandatory = $true)] [string]$AppName
    )
    
    $existingApps = Get-IntuneApplication -AppName $AppName | Where-Object {
        $_.displayName -eq $AppName -or
        ($_.displayName -like "$AppName*" -and $_.description -like "*Winget*")
    }
    
    if ($existingApps) {
        return @{
            Exists = $true
            Apps = @($existingApps)
        }
    }
    
    return @{
        Exists = $false
        Apps = $null
    }
}

function New-IntuneWinFile {
    param
    (
        $appid,
        $appname,
        $apppath,
        $setupfilename,
        $destpath
    )
    New-IntuneWinPackage -SourcePath "$apppath" -SetupFile "$setupfilename" -DestinationPath "$destpath" | Out-Null
}
