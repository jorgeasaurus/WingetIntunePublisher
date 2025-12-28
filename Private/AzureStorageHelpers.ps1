# AzureStorageHelpers.ps1
# Azure Storage and blob upload helper functions

# Configuration variables
$azureStorageUploadChunkSizeInMb = 6l
$azureStorageRenewSasUriBackOffTimeInSeconds = 5

function Invoke-BlobChunkUpload {
    <#
    .SYNOPSIS
    Uploads a single chunk to Azure Blob Storage.
    #>
    param
    (
        [Parameter(Mandatory = $true)] [string]$SasUri,
        [Parameter(Mandatory = $true)] [string]$BlockId,
        [Parameter(Mandatory = $true)] [byte[]]$Body
    )

    $uri = "$SasUri&comp=block&blockid=$BlockId"
    $headers = @{
        "x-ms-blob-type" = "BlockBlob"
        "Content-Type"   = "application/octet-stream"
    }

    Write-Verbose "PUT $uri"
    try {
        Invoke-WebRequest $uri -Method Put -Headers $headers -Body $Body -UseBasicParsing | Out-Null
    } catch {
        Write-Error "Blob chunk upload failed: $_"
        throw
    }
}

function Complete-BlobUpload {
    <#
    .SYNOPSIS
    Finalizes a chunked blob upload by committing the block list.
    #>
    param
    (
        [Parameter(Mandatory = $true)] [string]$SasUri,
        [Parameter(Mandatory = $true)] [string[]]$BlockIds
    )

    $uri = "$SasUri&comp=blocklist"
    $xml = '<?xml version="1.0" encoding="utf-8"?><BlockList>' +
    (($BlockIds | ForEach-Object { "<Latest>$_</Latest>" }) -join '') +
    '</BlockList>'

    Write-Verbose "PUT $uri"
    Write-Verbose $xml
    try {
        Invoke-RestMethod $uri -Method Put -Body $xml | Out-Null
    } catch {
        Write-Error "Blob finalization failed: $_"
        throw
    }
}

function Invoke-AzureStorageUpload {
    param(
        [Parameter(Mandatory = $true)] $sasUri, 
        [Parameter(Mandatory = $true)] $filepath, 
        [Parameter(Mandatory = $true)] $fileUri
    )
    
      $chunkSizeInBytes = 1024l * 1024l * $azureStorageUploadChunkSizeInMb
    $sasRenewalTimer = [System.Diagnostics.Stopwatch]::StartNew()

    $fileSize = (Get-Item $filepath).length
    $chunks = [Math]::Ceiling($fileSize / $chunkSizeInBytes)
    $reader = $null
    $blockIds = @()

    try {
        $reader = New-Object System.IO.BinaryReader([System.IO.File]::Open($filepath, [System.IO.FileMode]::Open))

        for ($chunk = 0; $chunk -lt $chunks; $chunk++) {
            $blockId = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($chunk.ToString("0000")))
            $blockIds += $blockId

            $length = [Math]::Min($chunkSizeInBytes, $fileSize - ($chunk * $chunkSizeInBytes))
            $bytes = $reader.ReadBytes($length)
            $currentChunk = $chunk + 1

            Write-Progress -Activity "Uploading File to Azure Storage" -Status "Uploading chunk $currentChunk of $chunks" `
                -PercentComplete ($currentChunk / $chunks * 100)

            Invoke-BlobChunkUpload -SasUri $sasUri -BlockId $blockId -Body $bytes

            # Renew SAS URI if 7 minutes elapsed
            if ($currentChunk -lt $chunks -and $sasRenewalTimer.ElapsedMilliseconds -ge 450000) {
                Update-AzureStorageUpload $fileUri
                $sasRenewalTimer.Restart()
            }
        }

        Write-Progress -Completed -Activity "Uploading File to Azure Storage"
    } finally {
        if ($reader) { $reader.Dispose() }
    }

    Complete-BlobUpload -SasUri $sasUri -BlockIds $blockIds
}

function Update-AzureStorageUpload {
    param(
        [Parameter(Mandatory = $true)] $fileUri
    )
    
    $renewalUri = "$fileUri/renewUpload"
    $actionBody = ""
    Invoke-MgGraphRequest -Method POST -Uri $renewalUri -Body $actionBody -ErrorAction Stop

    Wait-FileProcessing $fileUri "AzureStorageUriRenewal" $azureStorageRenewSasUriBackOffTimeInSeconds
}

function Wait-FileProcessing {
    param(
        [Parameter(Mandatory = $true)] $fileUri, 
        [Parameter(Mandatory = $true)] $stage,
        [Parameter()] $backOffTimeInSeconds = 5
    )

    $attempts = 600
    $successState = "$($stage)Success"
    $pendingState = "$($stage)Pending"
    $failedState = "$($stage)Failed"
    $timedOutState = "$($stage)TimedOut"

    $file = $null
    while ($attempts -gt 0) {
        $file = Invoke-MgGraphRequest -Method GET -Uri $fileUri -ErrorAction Stop

        if ($file.uploadState -eq $successState) {
            break
        } elseif ($file.uploadState -ne $pendingState) {
            throw "File upload state is not pending or success: $($file.uploadState)"
        }

        Start-Sleep $backOffTimeInSeconds
        $attempts--
    }

    if ($null -eq $file -or $file.uploadState -ne $successState) {
        throw "File request did not complete in the allotted time."
    }
    
    $file
}
