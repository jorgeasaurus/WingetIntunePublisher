$moduleNames = @(
    'Microsoft.Graph.Authentication',
    'SvRooij.ContentPrep.Cmdlet'
)

foreach ($name in $moduleNames) {
    if (-not (Get-Module -ListAvailable -Name $name)) {
        New-Module -Name $name -ScriptBlock {
            function Connect-MgGraph { param($Scopes, $TenantId, $ClientSecretCredential, [switch]$NoWelcome) }
            function Get-MgContext {}
            function Invoke-MgGraphRequest { param($Uri, $Method, $Body, $OutputType, [switch]$SkipHttpErrorCheck) }
            function Disconnect-MgGraph {}
        } | Import-Module -Force
    }
}

$ModulePath = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'WingetIntunePublisher.psd1'
Import-Module $ModulePath -Force -ErrorAction Stop

BeforeAll {
    $moduleRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
    . "$moduleRoot/Private/PortfolioHelpers.ps1"
    . "$moduleRoot/Public/UtilityFunctions.ps1"

    # Set the publisher tag as the module would
    $script:PublisherTag = "Imported with Winget Intune Publisher - github.com/jorgeasaurus/WingetIntunePublisher"
}

Describe 'Read-PortfolioFile' {
    BeforeAll {
        $testDir = Join-Path ([System.IO.Path]::GetTempPath()) "portfolio-tests-$(Get-Random)"
        New-Item -Path $testDir -ItemType Directory -Force | Out-Null
    }

    AfterAll {
        if (Test-Path $testDir) {
            Remove-Item -Path $testDir -Recurse -Force
        }
    }

    It 'parses a valid portfolio YAML file' {
        $yaml = @"
defaults:
  availableInstall: Device
apps:
  - id: Google.Chrome
    name: Google Chrome
  - id: 7zip.7zip
"@
        $file = Join-Path $testDir "valid.yml"
        Set-Content -Path $file -Value $yaml

        $result = Read-PortfolioFile -Path $file
        $result | Should -HaveCount 2
        $result[0].Id | Should -Be 'Google.Chrome'
        $result[0].Name | Should -Be 'Google Chrome'
        $result[0].AvailableInstall | Should -Be 'Device'
        $result[1].Id | Should -Be '7zip.7zip'
        $result[1].Name | Should -BeNullOrEmpty
        $result[1].AvailableInstall | Should -Be 'Device'
    }

    It 'applies per-app overrides over defaults' {
        $yaml = @"
defaults:
  availableInstall: User
apps:
  - id: Google.Chrome
    availableInstall: Both
  - id: Mozilla.Firefox
"@
        $file = Join-Path $testDir "overrides.yml"
        Set-Content -Path $file -Value $yaml

        $result = Read-PortfolioFile -Path $file
        $result[0].AvailableInstall | Should -Be 'Both'
        $result[1].AvailableInstall | Should -Be 'User'
    }

    It 'parses custom group names' {
        $yaml = @"
apps:
  - id: Microsoft.Teams
    groups:
      install: Custom-Install-Group
      uninstall: Custom-Uninstall-Group
"@
        $file = Join-Path $testDir "groups.yml"
        Set-Content -Path $file -Value $yaml

        $result = Read-PortfolioFile -Path $file
        $result[0].InstallGroupName | Should -Be 'Custom-Install-Group'
        $result[0].UninstallGroupName | Should -Be 'Custom-Uninstall-Group'
    }

    It 'defaults to User when no defaults specified' {
        $yaml = @"
apps:
  - id: Google.Chrome
"@
        $file = Join-Path $testDir "nodefaults.yml"
        Set-Content -Path $file -Value $yaml

        $result = Read-PortfolioFile -Path $file
        $result[0].AvailableInstall | Should -Be 'User'
    }

    It 'throws on empty apps list' {
        $yaml = @"
apps: []
"@
        $file = Join-Path $testDir "empty.yml"
        Set-Content -Path $file -Value $yaml

        { Read-PortfolioFile -Path $file } | Should -Throw '*no apps*'
    }

    It 'throws on missing app id' {
        $yaml = @"
apps:
  - name: Google Chrome
"@
        $file = Join-Path $testDir "noid.yml"
        Set-Content -Path $file -Value $yaml

        { Read-PortfolioFile -Path $file } | Should -Throw "*'id' field*"
    }

    It 'throws on duplicate app IDs' {
        $yaml = @"
apps:
  - id: Google.Chrome
  - id: Google.Chrome
"@
        $file = Join-Path $testDir "dupes.yml"
        Set-Content -Path $file -Value $yaml

        { Read-PortfolioFile -Path $file } | Should -Throw '*Duplicate*'
    }

    It 'throws on invalid availableInstall value' {
        $yaml = @"
defaults:
  availableInstall: Invalid
apps:
  - id: Google.Chrome
"@
        $file = Join-Path $testDir "invalid.yml"
        Set-Content -Path $file -Value $yaml

        { Read-PortfolioFile -Path $file } | Should -Throw '*Invalid*'
    }

    It 'parses the example portfolio file' {
        $examplePath = Join-Path $moduleRoot "examples/portfolio.yml"
        if (Test-Path $examplePath) {
            $result = Read-PortfolioFile -Path $examplePath
            $result.Count | Should -BeGreaterThan 0
            $result | ForEach-Object { $_.Id | Should -Not -BeNullOrEmpty }
        } else {
            Set-ItResult -Skipped -Because "Example portfolio file not found"
        }
    }
}

Describe 'Compare-PortfolioState' {
    BeforeAll {
        $tag = $script:PublisherTag
    }

    It 'identifies apps to deploy when Intune is empty' {
        $desired = @(
            [PSCustomObject]@{ Id = 'Google.Chrome'; Name = 'Google Chrome'; AvailableInstall = 'User'; Force = $false }
        )
        $current = @()

        $result = Compare-PortfolioState -DesiredApps $desired -CurrentApps $current
        $result.ToDeploy | Should -HaveCount 1
        $result.UpToDate | Should -HaveCount 0
        $result.ToRemove | Should -HaveCount 0
    }

    It 'identifies up-to-date apps by display name' {
        $desired = @(
            [PSCustomObject]@{ Id = 'Google.Chrome'; Name = 'Google Chrome'; AvailableInstall = 'User'; Force = $false }
        )
        $current = @(
            [PSCustomObject]@{ displayName = 'Google Chrome'; id = 'abc-123'; description = "Chrome browser. $tag" }
        )

        $result = Compare-PortfolioState -DesiredApps $desired -CurrentApps $current
        $result.ToDeploy | Should -HaveCount 0
        $result.UpToDate | Should -HaveCount 1
    }

    It 'ignores non-managed apps in Intune' {
        $desired = @(
            [PSCustomObject]@{ Id = 'Google.Chrome'; Name = 'Google Chrome'; AvailableInstall = 'User'; Force = $false }
        )
        $current = @(
            [PSCustomObject]@{ displayName = 'Some Other App'; id = 'xyz-789'; description = 'Manually deployed' }
        )

        $result = Compare-PortfolioState -DesiredApps $desired -CurrentApps $current
        $result.ToDeploy | Should -HaveCount 1
        $result.ToRemove | Should -HaveCount 0
    }

    It 'identifies orphaned managed apps for removal' {
        $desired = @(
            [PSCustomObject]@{ Id = 'Google.Chrome'; Name = 'Google Chrome'; AvailableInstall = 'User'; Force = $false }
        )
        $current = @(
            [PSCustomObject]@{ displayName = 'Google Chrome'; id = 'abc-123'; description = "Chrome. $tag" },
            [PSCustomObject]@{ displayName = 'Old App'; id = 'def-456'; description = "Legacy app. $tag" }
        )

        $result = Compare-PortfolioState -DesiredApps $desired -CurrentApps $current
        $result.UpToDate | Should -HaveCount 1
        $result.ToRemove | Should -HaveCount 1
        $result.ToRemove[0].DisplayName | Should -Be 'Old App'
    }

    It 'forces redeployment when Force is set on app entry' {
        $desired = @(
            [PSCustomObject]@{ Id = 'Google.Chrome'; Name = 'Google Chrome'; AvailableInstall = 'User'; Force = $true }
        )
        $current = @(
            [PSCustomObject]@{ displayName = 'Google Chrome'; id = 'abc-123'; description = "Chrome. $tag" }
        )

        $result = Compare-PortfolioState -DesiredApps $desired -CurrentApps $current
        $result.ToDeploy | Should -HaveCount 1
        $result.UpToDate | Should -HaveCount 0
    }

    It 'matches apps by app ID in description' {
        $desired = @(
            [PSCustomObject]@{ Id = 'Google.Chrome'; Name = 'Different Name'; AvailableInstall = 'User'; Force = $false }
        )
        $current = @(
            [PSCustomObject]@{ displayName = 'Chrome Enterprise'; id = 'abc-123'; description = "Google.Chrome deployed via $tag" }
        )

        $result = Compare-PortfolioState -DesiredApps $desired -CurrentApps $current
        $result.UpToDate | Should -HaveCount 1
        $result.ToDeploy | Should -HaveCount 0
    }
}

Describe 'Format-PortfolioReport' {
    It 'runs without error' {
        $diff = [PSCustomObject]@{
            ToDeploy = @([PSCustomObject]@{ Id = 'Google.Chrome'; Name = 'Chrome'; Force = $false })
            UpToDate = @([PSCustomObject]@{ Id = '7zip.7zip'; Name = '7-Zip' })
            ToRemove = @([PSCustomObject]@{ IntuneId = 'x'; DisplayName = 'Old App' })
        }

        { Format-PortfolioReport -DiffResult $diff } | Should -Not -Throw
    }

    It 'shows force label for forced apps' {
        $diff = [PSCustomObject]@{
            ToDeploy = @([PSCustomObject]@{ Id = 'Google.Chrome'; Name = 'Chrome'; Force = $true })
            UpToDate = @()
            ToRemove = @()
        }

        { Format-PortfolioReport -DiffResult $diff } | Should -Not -Throw
    }

    It 'handles empty diff without error' {
        $diff = [PSCustomObject]@{
            ToDeploy = @()
            UpToDate = @()
            ToRemove = @()
        }

        { Format-PortfolioReport -DiffResult $diff } | Should -Not -Throw
    }
}

# ─────────────────────────────────────────────────────────────
# Sync-IntunePortfolio (public cmdlet) integration tests
# ─────────────────────────────────────────────────────────────

Describe 'Sync-IntunePortfolio' {
    BeforeAll {
        $script:PortfolioTestDir = Join-Path ([System.IO.Path]::GetTempPath()) "sync-tests-$(Get-Random)"
        New-Item -Path $script:PortfolioTestDir -ItemType Directory -Force | Out-Null

        # Standard valid portfolio YAML used across tests
        $script:ValidYaml = @"
defaults:
  availableInstall: User
apps:
  - id: Google.Chrome
    name: Google Chrome
  - id: 7zip.7zip
    name: 7-Zip
"@
        $script:ValidPortfolioFile = Join-Path $script:PortfolioTestDir "portfolio.yml"
        Set-Content -Path $script:ValidPortfolioFile -Value $script:ValidYaml
    }

    AfterAll {
        if (Test-Path $script:PortfolioTestDir) {
            Remove-Item -Path $script:PortfolioTestDir -Recurse -Force
        }
    }

    Context 'Parameter Validation' {
        It 'has Path parameter marked Mandatory' {
            $command = Get-Command Sync-IntunePortfolio
            $command.Parameters['Path'].Attributes.Mandatory | Should -Contain $true
        }

        It 'supports ShouldProcess (WhatIf)' {
            $command = Get-Command Sync-IntunePortfolio
            $command.Parameters.Keys | Should -Contain 'WhatIf'
        }

        It 'has Force switch parameter' {
            $command = Get-Command Sync-IntunePortfolio
            $command.Parameters['Force'].SwitchParameter | Should -BeTrue
        }

        It 'has RemoveAbsent switch parameter' {
            $command = Get-Command Sync-IntunePortfolio
            $command.Parameters['RemoveAbsent'].SwitchParameter | Should -BeTrue
        }

        It 'validates Tenant parameter format' {
            $command = Get-Command Sync-IntunePortfolio
            $patterns = $command.Parameters['Tenant'].Attributes | Where-Object { $_ -is [System.Management.Automation.ValidatePatternAttribute] }
            $patterns | Should -Not -BeNullOrEmpty
        }

        It 'validates ClientId parameter format (GUID)' {
            $command = Get-Command Sync-IntunePortfolio
            $patterns = $command.Parameters['ClientId'].Attributes | Where-Object { $_ -is [System.Management.Automation.ValidatePatternAttribute] }
            $patterns | Should -Not -BeNullOrEmpty
        }

        It 'rejects non-existent Path' {
            InModuleScope WingetIntunePublisher {
                { Sync-IntunePortfolio -Path '/nonexistent/portfolio.yml' -Confirm:$false } | Should -Throw
            }
        }
    }

    Context 'WhatIf mode (drift detection)' {
        It 'skips all deployments and returns skipped results' {
            InModuleScope WingetIntunePublisher -ArgumentList $script:ValidPortfolioFile {
                param($PortfolioFile)
                Mock Connect-ToGraph {}
                Mock Get-IntuneApplication { @() }
                Mock Deploy-WinGetApp {}
                Mock Find-WinGetPackage { [PSCustomObject]@{ Name = 'MockApp' } }

                $results = Sync-IntunePortfolio -Path $PortfolioFile -WhatIf

                Should -Invoke Deploy-WinGetApp -Times 0
                $results.Deployed.Count | Should -Be 0
                $results.Skipped.Count | Should -Be 2
                $results.Skipped | ForEach-Object { $_.Reason | Should -Be 'WhatIf' }
            }
        }
    }

    Context 'Deployment flow' {
        It 'deploys new apps when Intune is empty' {
            InModuleScope WingetIntunePublisher -ArgumentList $script:ValidPortfolioFile {
                param($PortfolioFile)
                Mock Connect-ToGraph {}
                Mock Get-IntuneApplication { @() }
                Mock Deploy-WinGetApp {}
                Mock Find-WinGetPackage { [PSCustomObject]@{ Name = 'MockApp' } }

                $results = Sync-IntunePortfolio -Path $PortfolioFile -Confirm:$false

                Should -Invoke Deploy-WinGetApp -Times 2 -Exactly
                $results.Deployed.Count | Should -Be 2
            }
        }

        It 'skips up-to-date apps' {
            InModuleScope WingetIntunePublisher -ArgumentList $script:ValidPortfolioFile {
                param($PortfolioFile)
                $tag = $script:PublisherTag
                Mock Connect-ToGraph {}
                Mock Get-IntuneApplication {
                    @(
                        [PSCustomObject]@{ displayName = 'Google Chrome'; id = 'abc-123'; description = "Chrome. $tag" },
                        [PSCustomObject]@{ displayName = '7-Zip'; id = 'def-456'; description = "Zip tool. $tag" }
                    )
                }
                Mock Deploy-WinGetApp {}

                $results = Sync-IntunePortfolio -Path $PortfolioFile -Confirm:$false

                Should -Invoke Deploy-WinGetApp -Times 0
                $results.Skipped.Count | Should -Be 2
                $results.Skipped | ForEach-Object { $_.Reason | Should -Be 'Already deployed' }
            }
        }

        It 'deploys only missing apps when some exist' {
            InModuleScope WingetIntunePublisher -ArgumentList $script:ValidPortfolioFile {
                param($PortfolioFile)
                $tag = $script:PublisherTag
                Mock Connect-ToGraph {}
                Mock Get-IntuneApplication {
                    @(
                        [PSCustomObject]@{ displayName = 'Google Chrome'; id = 'abc-123'; description = "Chrome. $tag" }
                    )
                }
                Mock Deploy-WinGetApp {}
                Mock Find-WinGetPackage { [PSCustomObject]@{ Name = '7-Zip' } }

                $results = Sync-IntunePortfolio -Path $PortfolioFile -Confirm:$false

                Should -Invoke Deploy-WinGetApp -Times 1 -Exactly
                $results.Deployed.Count | Should -Be 1
                $results.Deployed[0].AppId | Should -Be '7zip.7zip'
                $results.Skipped.Count | Should -Be 1
            }
        }

        It 'uses app name from portfolio when specified' {
            InModuleScope WingetIntunePublisher -ArgumentList $script:ValidPortfolioFile {
                param($PortfolioFile)
                Mock Connect-ToGraph {}
                Mock Get-IntuneApplication { @() }
                Mock Deploy-WinGetApp {}
                Mock Find-WinGetPackage {}

                Sync-IntunePortfolio -Path $PortfolioFile -Confirm:$false

                # Should NOT call Find-WinGetPackage since both apps have names in the YAML
                Should -Invoke Find-WinGetPackage -Times 0
            }
        }

        It 'resolves app name from WinGet when not in YAML' {
            InModuleScope WingetIntunePublisher -ArgumentList $script:PortfolioTestDir {
                param($TestDir)
                $yaml = @"
apps:
  - id: Some.App
"@
                $file = Join-Path $TestDir "noname.yml"
                Set-Content -Path $file -Value $yaml

                Mock Connect-ToGraph {}
                Mock Get-IntuneApplication { @() }
                Mock Deploy-WinGetApp {}
                Mock Find-WinGetPackage { [PSCustomObject]@{ Name = 'Resolved Name' } }

                $results = Sync-IntunePortfolio -Path $file -Confirm:$false

                Should -Invoke Find-WinGetPackage -Times 1 -Exactly
                $results.Deployed[0].Name | Should -Be 'Resolved Name'
            }
        }

        It 'falls back to app ID when WinGet lookup returns nothing' {
            InModuleScope WingetIntunePublisher -ArgumentList $script:PortfolioTestDir {
                param($TestDir)
                $yaml = @"
apps:
  - id: Unknown.App
"@
                $file = Join-Path $TestDir "fallback.yml"
                Set-Content -Path $file -Value $yaml

                Mock Connect-ToGraph {}
                Mock Get-IntuneApplication { @() }
                Mock Deploy-WinGetApp {}
                Mock Find-WinGetPackage { $null }

                $results = Sync-IntunePortfolio -Path $file -Confirm:$false

                $results.Deployed[0].Name | Should -Be 'Unknown.App'
            }
        }
    }

    Context 'Force flag' {
        It 'redeploys all apps when -Force is set' {
            InModuleScope WingetIntunePublisher -ArgumentList $script:ValidPortfolioFile {
                param($PortfolioFile)
                $tag = $script:PublisherTag
                Mock Connect-ToGraph {}
                Mock Get-IntuneApplication {
                    @(
                        [PSCustomObject]@{ displayName = 'Google Chrome'; id = 'abc-123'; description = "Chrome. $tag" },
                        [PSCustomObject]@{ displayName = '7-Zip'; id = 'def-456'; description = "7-Zip. $tag" }
                    )
                }
                Mock Deploy-WinGetApp {}

                $results = Sync-IntunePortfolio -Path $PortfolioFile -Force -Confirm:$false

                Should -Invoke Deploy-WinGetApp -Times 2 -Exactly
                $results.Deployed.Count | Should -Be 2
                $results.Skipped.Count | Should -Be 0
            }
        }
    }

    Context 'RemoveAbsent flag' {
        It 'does not remove orphans when RemoveAbsent is not set' {
            InModuleScope WingetIntunePublisher -ArgumentList $script:ValidPortfolioFile {
                param($PortfolioFile)
                $tag = $script:PublisherTag
                Mock Connect-ToGraph {}
                Mock Get-IntuneApplication {
                    @(
                        [PSCustomObject]@{ displayName = 'Google Chrome'; id = 'abc-123'; description = "Chrome. $tag" },
                        [PSCustomObject]@{ displayName = '7-Zip'; id = 'def-456'; description = "7-Zip. $tag" },
                        [PSCustomObject]@{ displayName = 'Orphaned App'; id = 'zzz-999'; description = "Old. $tag" }
                    )
                }
                Mock Remove-WingetIntuneApps {}

                $results = Sync-IntunePortfolio -Path $PortfolioFile -Confirm:$false

                Should -Invoke Remove-WingetIntuneApps -Times 0
                $results.Removed.Count | Should -Be 0
            }
        }

        It 'removes orphaned apps when RemoveAbsent is set' {
            InModuleScope WingetIntunePublisher -ArgumentList $script:ValidPortfolioFile {
                param($PortfolioFile)
                $tag = $script:PublisherTag
                Mock Connect-ToGraph {}
                Mock Get-IntuneApplication {
                    @(
                        [PSCustomObject]@{ displayName = 'Google Chrome'; id = 'abc-123'; description = "Chrome. $tag" },
                        [PSCustomObject]@{ displayName = '7-Zip'; id = 'def-456'; description = "7-Zip. $tag" },
                        [PSCustomObject]@{ displayName = 'Orphaned App'; id = 'zzz-999'; description = "Old. $tag" }
                    )
                }
                Mock Remove-WingetIntuneApps {}

                $results = Sync-IntunePortfolio -Path $PortfolioFile -RemoveAbsent -Confirm:$false

                Should -Invoke Remove-WingetIntuneApps -Times 1 -Exactly
                $results.Removed.Count | Should -Be 1
                $results.Removed[0].Name | Should -Be 'Orphaned App'
            }
        }
    }

    Context 'Error handling' {
        It 'records failed deployments without stopping the pipeline' {
            InModuleScope WingetIntunePublisher -ArgumentList $script:ValidPortfolioFile {
                param($PortfolioFile)
                Mock Connect-ToGraph {}
                Mock Get-IntuneApplication { @() }
                Mock Deploy-WinGetApp { throw "Deployment exploded" }
                Mock Find-WinGetPackage { [PSCustomObject]@{ Name = 'MockApp' } }

                $results = Sync-IntunePortfolio -Path $PortfolioFile -Confirm:$false -WarningAction SilentlyContinue

                $results.Failed.Count | Should -Be 2
                $results.Failed[0].Error | Should -Match 'Deployment exploded'
                $results.Deployed.Count | Should -Be 0
            }
        }

        It 'records failed removal without stopping the pipeline' {
            InModuleScope WingetIntunePublisher -ArgumentList $script:ValidPortfolioFile {
                param($PortfolioFile)
                $tag = $script:PublisherTag
                Mock Connect-ToGraph {}
                Mock Get-IntuneApplication {
                    @(
                        [PSCustomObject]@{ displayName = 'Google Chrome'; id = 'abc-123'; description = "Chrome. $tag" },
                        [PSCustomObject]@{ displayName = '7-Zip'; id = 'def-456'; description = "7-Zip. $tag" },
                        [PSCustomObject]@{ displayName = 'BadOrphan'; id = 'zzz'; description = "Old. $tag" }
                    )
                }
                Mock Remove-WingetIntuneApps { throw "Removal exploded" }

                $results = Sync-IntunePortfolio -Path $PortfolioFile -RemoveAbsent -Confirm:$false -WarningAction SilentlyContinue

                $results.Failed.Count | Should -Be 1
                $results.Failed[0].Action | Should -Be 'RemoveFailed'
                $results.Failed[0].Error | Should -Match 'Removal exploded'
            }
        }

        It 'throws when Graph authentication fails' {
            InModuleScope WingetIntunePublisher -ArgumentList $script:ValidPortfolioFile {
                param($PortfolioFile)
                Mock Connect-ToGraph { throw "Auth failed" }

                { Sync-IntunePortfolio -Path $PortfolioFile -Confirm:$false } | Should -Throw '*Graph authentication failed*'
            }
        }

        It 'throws when Intune query fails' {
            InModuleScope WingetIntunePublisher -ArgumentList $script:ValidPortfolioFile {
                param($PortfolioFile)
                Mock Connect-ToGraph {}
                Mock Get-IntuneApplication { throw "Graph 503" }

                { Sync-IntunePortfolio -Path $PortfolioFile -Confirm:$false } | Should -Throw '*Failed to query Intune*'
            }
        }

        It 'throws when portfolio file is invalid' {
            InModuleScope WingetIntunePublisher -ArgumentList $script:PortfolioTestDir {
                param($TestDir)
                $file = Join-Path $TestDir "bad.yml"
                Set-Content -Path $file -Value "apps: []"

                { Sync-IntunePortfolio -Path $file -Confirm:$false } | Should -Throw '*Failed to read portfolio*'
            }
        }
    }

    Context 'Result object shape' {
        It 'returns object with Deployed, Skipped, Removed, Failed lists' {
            InModuleScope WingetIntunePublisher -ArgumentList $script:ValidPortfolioFile {
                param($PortfolioFile)
                Mock Connect-ToGraph {}
                Mock Get-IntuneApplication { @() }
                Mock Deploy-WinGetApp {}
                Mock Find-WinGetPackage { [PSCustomObject]@{ Name = 'MockApp' } }

                $results = Sync-IntunePortfolio -Path $PortfolioFile -Confirm:$false

                $results.PSObject.Properties.Name | Should -Contain 'Deployed'
                $results.PSObject.Properties.Name | Should -Contain 'Skipped'
                $results.PSObject.Properties.Name | Should -Contain 'Removed'
                $results.PSObject.Properties.Name | Should -Contain 'Failed'
            }
        }

        It 'populates deployed entries with AppId, Name, and Action' {
            InModuleScope WingetIntunePublisher -ArgumentList $script:ValidPortfolioFile {
                param($PortfolioFile)
                Mock Connect-ToGraph {}
                Mock Get-IntuneApplication { @() }
                Mock Deploy-WinGetApp {}

                $results = Sync-IntunePortfolio -Path $PortfolioFile -Confirm:$false

                $entry = $results.Deployed[0]
                $entry.AppId | Should -Not -BeNullOrEmpty
                $entry.Name | Should -Not -BeNullOrEmpty
                $entry.Action | Should -Be 'Deployed'
            }
        }
    }

    Context 'Deploy-WinGetApp parameter passing' {
        It 'passes custom group names to Deploy-WinGetApp' {
            InModuleScope WingetIntunePublisher -ArgumentList $script:PortfolioTestDir {
                param($TestDir)
                $yaml = @"
apps:
  - id: Microsoft.Teams
    name: Teams
    groups:
      install: Custom-Install
      uninstall: Custom-Uninstall
"@
                $file = Join-Path $TestDir "groups.yml"
                Set-Content -Path $file -Value $yaml

                Mock Connect-ToGraph {}
                Mock Get-IntuneApplication { @() }
                Mock Deploy-WinGetApp {}

                Sync-IntunePortfolio -Path $file -Confirm:$false

                Should -Invoke Deploy-WinGetApp -ParameterFilter {
                    $InstallGroupName -eq 'Custom-Install' -and $UninstallGroupName -eq 'Custom-Uninstall'
                } -Times 1
            }
        }

        It 'passes availableInstall override to Deploy-WinGetApp' {
            InModuleScope WingetIntunePublisher -ArgumentList $script:PortfolioTestDir {
                param($TestDir)
                $yaml = @"
defaults:
  availableInstall: User
apps:
  - id: Some.App
    name: Some App
    availableInstall: Both
"@
                $file = Join-Path $TestDir "avail.yml"
                Set-Content -Path $file -Value $yaml

                Mock Connect-ToGraph {}
                Mock Get-IntuneApplication { @() }
                Mock Deploy-WinGetApp {}

                Sync-IntunePortfolio -Path $file -Confirm:$false

                Should -Invoke Deploy-WinGetApp -ParameterFilter {
                    $AvailableInstall -eq 'Both'
                } -Times 1
            }
        }

        It 'passes Force to Deploy-WinGetApp when app-level force is set' {
            InModuleScope WingetIntunePublisher -ArgumentList $script:PortfolioTestDir {
                param($TestDir)
                $yaml = @"
apps:
  - id: Force.App
    name: Force App
    force: true
"@
                $file = Join-Path $TestDir "force-app.yml"
                Set-Content -Path $file -Value $yaml

                Mock Connect-ToGraph {}
                Mock Get-IntuneApplication { @() }
                Mock Deploy-WinGetApp {}

                Sync-IntunePortfolio -Path $file -Confirm:$false

                Should -Invoke Deploy-WinGetApp -ParameterFilter {
                    $Force -eq $true
                } -Times 1
            }
        }
    }
}
