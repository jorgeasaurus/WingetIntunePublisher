# Win32AppHelpers.ps1
# Win32 App creation and management functions

# Configuration variables
$azureStorageUploadChunkSizeInMb = 6l
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
    Write-IntuneLog "Searching for icon for $AppId"

    foreach ($repoPath in $script:IconRepoPaths) {
        foreach ($candidate in $nameCandidates) {
            $iconUrl = "$repoPath/$candidate.png"

            try {
                Write-Verbose "Trying icon URL: $iconUrl"

                $webClient = New-Object System.Net.WebClient
                $iconBytes = $webClient.DownloadData($iconUrl)
                $iconBase64 = [Convert]::ToBase64String($iconBytes)

                Write-Host "Found icon for $AppId at: $candidate.png" -ForegroundColor Green
                Write-IntuneLog "Found icon for $AppId`: $candidate.png"

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
    Write-IntuneLog "No icon found for $AppId"
    return $null
}

function Get-Win32AppBody {
    param
    (
        [parameter(Mandatory = $true, ParameterSetName = "MSI", Position = 1)]
        [Switch]$MSI,

        [parameter(Mandatory = $true, ParameterSetName = "EXE", Position = 1)]
        [Switch]$EXE,

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

        [parameter(Mandatory = $true, ParameterSetName = "EXE")]
        [ValidateNotNullOrEmpty()]
        $installCommandLine,

        [parameter(Mandatory = $true, ParameterSetName = "EXE")]
        [ValidateNotNullOrEmpty()]
        $uninstallCommandLine,

        [parameter(Mandatory = $false)]
        [hashtable]$largeIcon,

        [parameter(Mandatory = $true, ParameterSetName = "MSI")]
        [ValidateNotNullOrEmpty()]
        $MsiPackageType,

        [parameter(Mandatory = $true, ParameterSetName = "MSI")]
        [ValidateNotNullOrEmpty()]
        $MsiProductCode,

        [parameter(Mandatory = $false, ParameterSetName = "MSI")]
        $MsiProductName,

        [parameter(Mandatory = $true, ParameterSetName = "MSI")]
        [ValidateNotNullOrEmpty()]
        $MsiProductVersion,

        [parameter(Mandatory = $false, ParameterSetName = "MSI")]
        $MsiPublisher,

        [parameter(Mandatory = $true, ParameterSetName = "MSI")]
        [ValidateNotNullOrEmpty()]
        $MsiRequiresReboot,

        [parameter(Mandatory = $true, ParameterSetName = "MSI")]
        [ValidateNotNullOrEmpty()]
        $MsiUpgradeCode
    )

    if ($MSI) {
        $body = @{ "@odata.type" = "#microsoft.graph.win32LobApp" }
        $body.applicableArchitectures = "x64,x86"
        $body.description = $description
        $body.developer = ""
        $body.displayName = $displayName
        $body.fileName = $filename
        $body.installCommandLine = "msiexec /i `"$SetupFileName`""
        $body.installExperience = @{"runAsAccount" = "$installExperience" }
        $body.informationUrl = $null
        $body.isFeatured = $false
        $body.minimumSupportedOperatingSystem = @{"v10_1607" = $true }
        $body.msiInformation = @{
            "packageType"    = "$MsiPackageType"
            "productCode"    = "$MsiProductCode"
            "productName"    = "$MsiProductName"
            "productVersion" = "$MsiProductVersion"
            "publisher"      = "$MsiPublisher"
            "requiresReboot" = "$MsiRequiresReboot"
            "upgradeCode"    = "$MsiUpgradeCode"
        }
        $body.notes = ""
        $body.owner = ""
        $body.privacyInformationUrl = $null
        $body.publisher = $publisher
        $body.runAs32bit = $false
        $body.setupFilePath = $SetupFileName
        $body.uninstallCommandLine = "msiexec /x `"$MsiProductCode`""
        if ($largeIcon) { $body.largeIcon = $largeIcon }
    }
    elseif ($EXE) {
        $body = @{ "@odata.type" = "#microsoft.graph.win32LobApp" }
        $body.description = $description
        $body.developer = ""
        $body.displayName = $displayName
        $body.fileName = $filename
        $body.installCommandLine = "$installCommandLine"
        $body.installExperience = @{"runAsAccount" = "$installExperience" }
        $body.informationUrl = $null
        $body.isFeatured = $false
        $body.minimumSupportedOperatingSystem = @{"v10_1607" = $true }
        $body.msiInformation = $null
        $body.notes = ""
        $body.owner = ""
        $body.privacyInformationUrl = $null
        $body.publisher = $publisher
        $body.runAs32bit = $false
        $body.setupFilePath = $SetupFileName
        $body.uninstallCommandLine = "$uninstallCommandLine"
        if ($largeIcon) { $body.largeIcon = $largeIcon }
    }

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

    try {
        if (!(Test-Path "$SourceFile")) {
            Write-Error "Source File '$SourceFile' doesn't exist..."
            throw
        }
    }
    catch {
        Write-Error $_.Exception.Message
        break
    }
}

function New-DetectionRule {
    [cmdletbinding()]
    param
    (
        [parameter(Mandatory = $true, ParameterSetName = "PowerShell", Position = 1)]
        [Switch]$PowerShell,

        [parameter(Mandatory = $true, ParameterSetName = "MSI", Position = 1)]
        [Switch]$MSI,

        [parameter(Mandatory = $true, ParameterSetName = "File", Position = 1)]
        [Switch]$File,

        [parameter(Mandatory = $true, ParameterSetName = "Registry", Position = 1)]
        [Switch]$Registry,

        [parameter(Mandatory = $true, ParameterSetName = "PowerShell")]
        [ValidateNotNullOrEmpty()]
        [String]$ScriptFile,

        [parameter(Mandatory = $true, ParameterSetName = "PowerShell")]
        [ValidateNotNullOrEmpty()]
        $enforceSignatureCheck,

        [parameter(Mandatory = $true, ParameterSetName = "PowerShell")]
        [ValidateNotNullOrEmpty()]
        $runAs32Bit,

        [parameter(Mandatory = $true, ParameterSetName = "MSI")]
        [ValidateNotNullOrEmpty()]
        [String]$MSIproductCode,

        [parameter(Mandatory = $true, ParameterSetName = "File")]
        [ValidateNotNullOrEmpty()]
        [String]$Path,

        [parameter(Mandatory = $true, ParameterSetName = "File")]
        [ValidateNotNullOrEmpty()]
        [string]$FileOrFolderName,

        [parameter(Mandatory = $true, ParameterSetName = "File")]
        [ValidateSet("notConfigured", "exists", "modifiedDate", "createdDate", "version", "sizeInMB")]
        [string]$FileDetectionType,

        [parameter(Mandatory = $false, ParameterSetName = "File")]
        $FileDetectionValue = $null,

        [parameter(Mandatory = $true, ParameterSetName = "File")]
        [ValidateSet("True", "False")]
        [string]$check32BitOn64System = "False",

        [parameter(Mandatory = $true, ParameterSetName = "Registry")]
        [ValidateNotNullOrEmpty()]
        [String]$RegistryKeyPath,

        [parameter(Mandatory = $true, ParameterSetName = "Registry")]
        [ValidateSet("notConfigured", "exists", "doesNotExist", "string", "integer", "version")]
        [string]$RegistryDetectionType,

        [parameter(Mandatory = $false, ParameterSetName = "Registry")]
        [ValidateNotNullOrEmpty()]
        [String]$RegistryValue,

        [parameter(Mandatory = $true, ParameterSetName = "Registry")]
        [ValidateSet("True", "False")]
        [string]$check32BitRegOn64System = "False"
    )

    if ($PowerShell) {
        if (!(Test-Path "$ScriptFile")) {
            Write-Error "Could not find file '$ScriptFile'..."
            Write-Error "Script can't continue..."
            break
        }

        $ScriptContent = [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes("$ScriptFile"))

        $DR = @{ "@odata.type" = "#microsoft.graph.win32LobAppPowerShellScriptDetection" }
        $DR.enforceSignatureCheck = $false
        $DR.runAs32Bit = $false
        $DR.scriptContent = "$ScriptContent"
    }
    elseif ($MSI) {
        $DR = @{ "@odata.type" = "#microsoft.graph.win32LobAppProductCodeDetection" }
        $DR.productVersionOperator = "notConfigured"
        $DR.productCode = "$MsiProductCode"
        $DR.productVersion = $null
    }
    elseif ($File) {
        $DR = @{ "@odata.type" = "#microsoft.graph.win32LobAppFileSystemDetection" }
        $DR.check32BitOn64System = "$check32BitOn64System"
        $DR.detectionType = "$FileDetectionType"
        $DR.detectionValue = $FileDetectionValue
        $DR.fileOrFolderName = "$FileOrFolderName"
        $DR.operator = "notConfigured"
        $DR.path = "$Path"
    }
    elseif ($Registry) {
        $DR = @{ "@odata.type" = "#microsoft.graph.win32LobAppRegistryDetection" }
        $DR.check32BitOn64System = "$check32BitRegOn64System"
        $DR.detectionType = "$RegistryDetectionType"
        $DR.detectionValue = ""
        $DR.keyPath = "$RegistryKeyPath"
        $DR.operator = "notConfigured"
        $DR.valueName = "$RegistryValue"
    }

    return $DR
}

function Get-DefaultReturnCode {
    @{"returnCode" = 0; "type" = "success" }, `
    @{"returnCode" = 1707; "type" = "success" }, `
    @{"returnCode" = 3010; "type" = "softReboot" }, `
    @{"returnCode" = 1641; "type" = "hardReboot" }, `
    @{"returnCode" = 1618; "type" = "retry" }
}

function New-ReturnCode {
    param
    (
        [parameter(Mandatory = $true)]
        [int]$returnCode,
        [parameter(Mandatory = $true)]
        [ValidateSet('success', 'softReboot', 'hardReboot', 'retry')]
        $type
    )

    @{"returnCode" = $returnCode; "type" = "$type" }
}

function Get-DefaultReturnCodes {
    <#
    .SYNOPSIS
    Returns the default return codes for Win32 apps in Intune
    .DESCRIPTION
    Creates an array of default return code objects for standard Win32 app deployments
    #>
    
    $returnCodes = @(
        New-ReturnCode -returnCode 0 -type "success"
        New-ReturnCode -returnCode 1707 -type "success"
        New-ReturnCode -returnCode 3010 -type "softReboot"
        New-ReturnCode -returnCode 1641 -type "hardReboot"
        New-ReturnCode -returnCode 1618 -type "retry"
    )
    
    return $returnCodes
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

    return $IntuneWinXML

    if ($removeitem -eq "true") { Remove-Item "$Directory\$filename" }
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

    if ($removeitem -eq "true") { Remove-Item "$Directory\$filename" }
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

        # Funciton to read Win32LOB file
        $DetectionXML = Get-IntuneWinXML "$SourceFile" -fileName "detection.xml"

        # If displayName input don't use Name from detection.xml file
        if ($displayName) { $DisplayName = $displayName }
        else { $DisplayName = $DetectionXML.ApplicationInfo.Name }

        $FileName = $DetectionXML.ApplicationInfo.FileName

        $SetupFileName = $DetectionXML.ApplicationInfo.SetupFile

        $Ext = [System.IO.Path]::GetExtension($SetupFileName)

        if ((($Ext).contains("msi") -or ($Ext).contains("Msi")) -and (!$installCmdLine -or !$uninstallCmdLine)) {

            # MSI
            $MsiExecutionContext = $DetectionXML.ApplicationInfo.MsiInfo.MsiExecutionContext
            $MsiPackageType = "DualPurpose"
            if ($MsiExecutionContext -eq "System") { $MsiPackageType = "PerMachine" }
            elseif ($MsiExecutionContext -eq "User") { $MsiPackageType = "PerUser" }

            $MsiProductCode = $DetectionXML.ApplicationInfo.MsiInfo.MsiProductCode
            $MsiProductVersion = $DetectionXML.ApplicationInfo.MsiInfo.MsiProductVersion
            $MsiPublisher = $DetectionXML.ApplicationInfo.MsiInfo.MsiPublisher
            $MsiRequiresReboot = $DetectionXML.ApplicationInfo.MsiInfo.MsiRequiresReboot
            $MsiUpgradeCode = $DetectionXML.ApplicationInfo.MsiInfo.MsiUpgradeCode

            if ($MsiRequiresReboot -eq "false") { $MsiRequiresReboot = $false }
            elseif ($MsiRequiresReboot -eq "true") { $MsiRequiresReboot = $true }

            $mobileAppBody = Get-Win32AppBody `
                -MSI `
                -displayName "$DisplayName" `
                -publisher "$publisher" `
                -description $description `
                -filename $FileName `
                -SetupFileName "$SetupFileName" `
                -installExperience $installExperience `
                -MsiPackageType $MsiPackageType `
                -MsiProductCode $MsiProductCode `
                -MsiProductName $displayName `
                -MsiProductVersion $MsiProductVersion `
                -MsiPublisher $MsiPublisher `
                -MsiRequiresReboot $MsiRequiresReboot `
                -MsiUpgradeCode $MsiUpgradeCode `
                -largeIcon $largeIcon

        }
        else {
            $mobileAppBody = Get-Win32AppBody -EXE -displayName "$DisplayName" -publisher "$publisher" `
                -description $description -filename $FileName -SetupFileName "$SetupFileName" `
                -installExperience $installExperience -installCommandLine $installCmdLine `
                -uninstallCommandLine $uninstallcmdline -largeIcon $largeIcon
        }

        if ($DetectionRules.'@odata.type' -contains "#microsoft.graph.win32LobAppPowerShellScriptDetection" -and @($DetectionRules).'@odata.type'.Count -gt 1) {
            Write-Warning "A Detection Rule can either be 'Manually configure detection rules' or 'Use a custom detection script'"
            Write-Warning "It can't include both..."
            break
        }
        else {
            $mobileAppBody | Add-Member -MemberType NoteProperty -Name 'detectionRules' -Value $detectionRules
        }

        #ReturnCodes

        if ($returnCodes) {
            $mobileAppBody | Add-Member -MemberType NoteProperty -Name 'returnCodes' -Value @($returnCodes)
        }
        else {
            Write-Warning "Intunewin file requires ReturnCodes to be specified"
            Write-Warning "If you want to use the default ReturnCode run 'Get-DefaultReturnCodes'"
            break
        }

        Write-Verbose "Creating application in Intune..."
        Write-IntuneLog "Creating application in Intune..."

        $mobileApp = Invoke-MgGraphRequest -Method POST -Uri "beta/deviceAppManagement/mobileApps/" -Body ($mobileAppBody | ConvertTo-Json) -ContentType "application/json" -OutputType PSObject -ErrorAction Stop

        if (-not $mobileApp -or -not $mobileApp.id) {
            throw "Graph API returned null response or missing app ID"
        }

        # Get the content version for the new app (this will always be 1 until the new app is committed).
        Write-Verbose "Creating Content Version in the service for the application..."
        Write-IntuneLog "Creating Content Version in the service for the application..."

        $appId = $mobileApp.id
        $contentVersionUri = "beta/deviceAppManagement/mobileApps/$appId/$LOBType/contentVersions"
        $contentVersion = Invoke-MgGraphRequest -Method POST -Uri $contentVersionUri -Body "{}" -ErrorAction Stop

        # Encrypt file and Get File Information
        Write-Verbose "Getting Encryption Information for '$SourceFile'..."
        Write-IntuneLog "Getting Encryption Information for '$SourceFile'..."

        $encryptionInfo = @{}
        $encryptionInfo.encryptionKey = $DetectionXML.ApplicationInfo.EncryptionInfo.EncryptionKey
        $encryptionInfo.macKey = $DetectionXML.ApplicationInfo.EncryptionInfo.macKey
        $encryptionInfo.initializationVector = $DetectionXML.ApplicationInfo.EncryptionInfo.initializationVector
        $encryptionInfo.mac = $DetectionXML.ApplicationInfo.EncryptionInfo.mac
        $encryptionInfo.profileIdentifier = "ProfileVersion1"
        $encryptionInfo.fileDigest = $DetectionXML.ApplicationInfo.EncryptionInfo.fileDigest
        $encryptionInfo.fileDigestAlgorithm = $DetectionXML.ApplicationInfo.EncryptionInfo.fileDigestAlgorithm

        $fileEncryptionInfo = @{}
        $fileEncryptionInfo.fileEncryptionInfo = $encryptionInfo

        # Extracting encrypted file
        $IntuneWinFile = Get-IntuneWinFile "$SourceFile" -fileName "$filename"

        [int64]$Size = $DetectionXML.ApplicationInfo.UnencryptedContentSize
        $EncrySize = (Get-Item "$IntuneWinFile").Length

        # Create a new file for the app.
        Write-Verbose "Creating a new file entry in Azure for the upload..."
        Write-IntuneLog "Creating a new file entry in Azure for the upload..."

        $contentVersionId = $contentVersion.id
        $fileBody = Get-AppFileBody "$FileName" $Size $EncrySize $null
        $filesUri = "beta/deviceAppManagement/mobileApps/$appId/$LOBType/contentVersions/$contentVersionId/files"
        $file = Invoke-MgGraphRequest -Method POST -Uri $filesUri -Body ($fileBody | ConvertTo-Json) -ErrorAction Stop

        # Wait for the service to process the new file request.
        Write-Verbose "Waiting for the file entry URI to be created..."
        Write-IntuneLog "Waiting for the file entry URI to be created..."

        $fileId = $file.id
        $fileUri = "beta/deviceAppManagement/mobileApps/$appId/$LOBType/contentVersions/$contentVersionId/files/$fileId"
        $file = Wait-FileProcessing $fileUri "AzureStorageUriRequest"

        # Upload the content to Azure Storage.
        Write-Verbose "Uploading file to Azure Storage..."
        Write-IntuneLog "Uploading file to Azure Storage..."

        Invoke-AzureStorageUpload $file.azureStorageUri "$IntuneWinFile" $fileUri

        # Need to Add removal of IntuneWin file
        Remove-Item "$IntuneWinFile" -Force

        # Commit the file.
        Write-Verbose "Committing the file into Azure Storage..."
        Write-IntuneLog "Committing the file into Azure Storage..."

        $commitFileUri = "beta/deviceAppManagement/mobileApps/$appId/$LOBType/contentVersions/$contentVersionId/files/$fileId/commit"
        Invoke-MgGraphRequest -Uri $commitFileUri -Method POST -Body ($fileEncryptionInfo | ConvertTo-Json) -ErrorAction Stop

        # Wait for the service to process the commit file request.
        Write-Verbose "Waiting for the service to process the commit file request..."
        Write-IntuneLog "Waiting for the service to process the commit file request..."

        $file = Wait-FileProcessing $fileUri "CommitFile"

        # Commit the app.
        Write-Verbose "Committing the file into Azure Storage..."
        Write-IntuneLog "Committing the file into Azure Storage..."

        $commitAppUri = "beta/deviceAppManagement/mobileApps/$appId"
        $commitAppBody = Get-AppCommitBody $contentVersionId $LOBType
        Invoke-MgGraphRequest -Method PATCH -Uri $commitAppUri -Body ($commitAppBody | ConvertTo-Json) -ErrorAction Stop

        foreach ($i in 0..$sleep) {
            Write-Progress -Activity "Sleeping for $($sleep-$i) seconds" -PercentComplete ($i / $sleep * 100) -SecondsRemaining ($sleep - $i)
            Start-Sleep -s 1
        }
    }
    catch {
        Write-Error "Aborting with exception: $($_.Exception.ToString())"
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

    $Application = Get-IntuneApplication | Where-Object { $_.displayName -eq $AppName -and $_.description -like "*Winget*" }
    if (-not $Application) {
        Write-Error "Application '$AppName' not found in Intune"
        return
    }
    
    if (-not $Application.id) {
        Write-Error "Application '$AppName' found but has no ID"
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
    Invoke-MgGraphRequest -Uri "beta/deviceAppManagement/mobileApps/$($Application.id)/assign" -Method POST -Body ($body | ConvertTo-Json -Depth 10) -ErrorAction Stop
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
        description      = "$appname Imported with Winget Intune Publisher - github.com/jorgeasaurus/WingetIntunePublisher"
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
    Boolean indicating if app exists, and the app object if found
    #>
    param(
        [Parameter(Mandatory = $true)] [string]$AppName
    )
    
    $existingApps = Get-IntuneApplication | Where-Object { 
        $_.displayName -eq $AppName -or 
        ($_.displayName -like "$AppName*" -and $_.description -like "*Winget*")
    }
    
    if ($existingApps) {
        return @{
            Exists = $true
            Apps = $existingApps
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
    New-IntuneWinPackage -SourcePath "$apppath" -SetupFile "$setupfilename" -DestinationPath "$destpath"
}
