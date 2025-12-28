BeforeAll {
    $ModulePath = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'WingetIntunePublisher.psd1'
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Deploy-WinGetApp' {
    BeforeAll {
        # Create temp directory for tests
        $script:TestBasePath = Join-Path -Path $TestDrive -ChildPath 'DeploymentTests'
        New-Item -Path $script:TestBasePath -ItemType Directory -Force | Out-Null
    }

    Context 'Parameter Validation' {
        It 'requires AppId parameter' {
            InModuleScope WingetIntunePublisher {
                $command = Get-Command Deploy-WinGetApp
                $parameter = $command.Parameters['AppId']
                $parameter.Attributes.Mandatory | Should -Contain $true
            }
        }

        It 'requires AppName parameter' {
            InModuleScope WingetIntunePublisher {
                $command = Get-Command Deploy-WinGetApp
                $parameter = $command.Parameters['AppName']
                $parameter.Attributes.Mandatory | Should -Contain $true
            }
        }

        It 'requires BasePath parameter' {
            InModuleScope WingetIntunePublisher {
                $command = Get-Command Deploy-WinGetApp
                $parameter = $command.Parameters['BasePath']
                $parameter.Attributes.Mandatory | Should -Contain $true
            }
        }

        It 'validates AvailableInstall parameter with ValidateSet' {
            InModuleScope WingetIntunePublisher -ArgumentList $script:TestBasePath {
                param($TestPath)

                Mock -CommandName Test-ExistingIntuneApp { @{ Exists = $false } }
                Mock -CommandName Get-OrCreateAADGroup { 'group-id-123' }
                Mock -CommandName New-WinGetScript { 'script content' }
                Mock -CommandName Test-ProactiveRemediationLicense { $false }
                Mock -CommandName New-IntuneWinFile { }
                Mock -CommandName Get-AppIcon { $null }
                Mock -CommandName New-Win32App { @{ id = 'app-123' } }
                Mock -CommandName Grant-Win32AppAssignment { }

                { Deploy-WinGetApp -AppId 'Test.App' -AppName 'Test App' -BasePath $TestPath -AvailableInstall 'InvalidValue' } |
                    Should -Throw
            }
        }

        It 'accepts valid AvailableInstall values' {
            InModuleScope WingetIntunePublisher -ArgumentList $script:TestBasePath {
                param($TestPath)

                Mock -CommandName Test-ExistingIntuneApp { @{ Exists = $false } }
                Mock -CommandName Get-OrCreateAADGroup { 'group-id-123' }
                Mock -CommandName New-WinGetScript { 'script content' }
                Mock -CommandName Test-ProactiveRemediationLicense { $false }
                Mock -CommandName New-IntuneWinFile { }
                Mock -CommandName Get-AppIcon { $null }
                Mock -CommandName New-Win32App { @{ id = 'app-123' } }
                Mock -CommandName Grant-Win32AppAssignment { }

                foreach ($value in @('User', 'Device', 'Both', 'None')) {
                    { Deploy-WinGetApp -AppId 'Test.App' -AppName 'Test App' -BasePath $TestPath -AvailableInstall $value } |
                        Should -Not -Throw
                }
            }
        }
    }

    Context 'Existing App Detection' {
        It 'skips deployment when app exists and Force not specified' {
            InModuleScope WingetIntunePublisher -ArgumentList $script:TestBasePath {
                param($TestPath)

                Mock -CommandName Test-ExistingIntuneApp {
                    @{
                        Exists = $true
                        Apps = @(
                            @{ displayName = 'Test App'; id = 'existing-app-123' }
                        )
                    }
                }
                Mock -CommandName Get-OrCreateAADGroup { }
                Mock -CommandName New-Win32App { }

                Deploy-WinGetApp -AppId 'Test.App' -AppName 'Test App' -BasePath $TestPath

                Assert-MockCalled Test-ExistingIntuneApp -Times 1 -Exactly
                Assert-MockCalled Get-OrCreateAADGroup -Times 0
                Assert-MockCalled New-Win32App -Times 0
            }
        }

        It 'proceeds with deployment when app exists and Force is specified' {
            InModuleScope WingetIntunePublisher -ArgumentList $script:TestBasePath {
                param($TestPath)

                Mock -CommandName Test-ExistingIntuneApp {
                    @{
                        Exists = $true
                        Apps = @(
                            @{ displayName = 'Test App'; id = 'existing-app-123' }
                        )
                    }
                }
                Mock -CommandName Get-OrCreateAADGroup { 'group-id-123' }
                Mock -CommandName New-WinGetScript { 'script content' }
                Mock -CommandName Test-ProactiveRemediationLicense { $false }
                Mock -CommandName New-IntuneWinFile { }
                Mock -CommandName Get-AppIcon { $null }
                Mock -CommandName New-Win32App { @{ id = 'app-123' } }
                Mock -CommandName Grant-Win32AppAssignment { }

                Deploy-WinGetApp -AppId 'Test.App' -AppName 'Test App' -BasePath $TestPath -Force

                Assert-MockCalled Test-ExistingIntuneApp -Times 1 -Exactly
                Assert-MockCalled Get-OrCreateAADGroup -Times 2 -Exactly
                Assert-MockCalled New-Win32App -Times 1 -Exactly
            }
        }

        It 'proceeds with deployment when app does not exist' {
            InModuleScope WingetIntunePublisher -ArgumentList $script:TestBasePath {
                param($TestPath)
                Mock -CommandName Test-ExistingIntuneApp { @{ Exists = $false } }
                Mock -CommandName Get-OrCreateAADGroup { 'group-id-123' }
                Mock -CommandName New-WinGetScript { 'script content' }
                Mock -CommandName Test-ProactiveRemediationLicense { $false }
                Mock -CommandName New-IntuneWinFile { }
                Mock -CommandName Get-AppIcon { $null }
                Mock -CommandName New-Win32App { @{ id = 'app-123' } }
                Mock -CommandName Grant-Win32AppAssignment { }

                Deploy-WinGetApp -AppId 'Test.App' -AppName 'Test App' -BasePath $TestPath

                Assert-MockCalled Get-OrCreateAADGroup -Times 2 -Exactly
                Assert-MockCalled New-Win32App -Times 1 -Exactly
            }
        }
    }

    Context 'Directory Creation' {
        It 'creates app directory under BasePath' {
            InModuleScope WingetIntunePublisher -ArgumentList $script:TestBasePath {
                param($TestPath)
                Mock -CommandName Test-ExistingIntuneApp { @{ Exists = $false } }
                Mock -CommandName Get-OrCreateAADGroup { 'group-id-123' }
                Mock -CommandName New-WinGetScript { 'script content' }
                Mock -CommandName Test-ProactiveRemediationLicense { $false }
                Mock -CommandName New-IntuneWinFile { }
                Mock -CommandName Get-AppIcon { $null }
                Mock -CommandName New-Win32App { @{ id = 'app-123' } }
                Mock -CommandName Grant-Win32AppAssignment { }

                Deploy-WinGetApp -AppId 'Test.App' -AppName 'Test App' -BasePath $TestPath

                $expectedPath = Join-Path -Path $TestPath -ChildPath 'Test.App'
                Test-Path $expectedPath | Should -Be $true
            }
        }

        It 'sanitizes AppId for directory names' {
            InModuleScope WingetIntunePublisher -ArgumentList $script:TestBasePath {
                param($TestPath)
                Mock -CommandName Test-ExistingIntuneApp { @{ Exists = $false } }
                Mock -CommandName Get-OrCreateAADGroup { 'group-id-123' }
                Mock -CommandName New-WinGetScript { 'script content' }
                Mock -CommandName Test-ProactiveRemediationLicense { $false }
                Mock -CommandName New-IntuneWinFile { }
                Mock -CommandName Get-AppIcon { $null }
                Mock -CommandName New-Win32App { @{ id = 'app-123' } }
                Mock -CommandName Grant-Win32AppAssignment { }

                Deploy-WinGetApp -AppId 'Test@App#123' -AppName 'Test App' -BasePath $TestPath

                $expectedPath = Join-Path -Path $TestPath -ChildPath 'Test@App#123'
                Test-Path $expectedPath | Should -Be $true
            }
        }
    }

    Context 'Group Management' {
        It 'creates install group with correct parameters' {
            InModuleScope WingetIntunePublisher -ArgumentList $script:TestBasePath {
                param($TestPath)
                Mock -CommandName Test-ExistingIntuneApp { @{ Exists = $false } }
                Mock -CommandName Get-OrCreateAADGroup { 'group-id-123' }
                Mock -CommandName New-WinGetScript { 'script content' }
                Mock -CommandName Test-ProactiveRemediationLicense { $false }
                Mock -CommandName New-IntuneWinFile { }
                Mock -CommandName Get-AppIcon { $null }
                Mock -CommandName New-Win32App { @{ id = 'app-123' } }
                Mock -CommandName Grant-Win32AppAssignment { }

                Deploy-WinGetApp -AppId 'Test.App' -AppName 'Test App' -BasePath $TestPath

                Assert-MockCalled Get-OrCreateAADGroup -ParameterFilter {
                    $AppId -eq 'Test.App' -and
                    $AppName -eq 'Test App' -and
                    $GroupType -eq 'Install'
                } -Times 1 -Exactly
            }
        }

        It 'creates uninstall group with correct parameters' {
            InModuleScope WingetIntunePublisher -ArgumentList $script:TestBasePath {
                param($TestPath)
                Mock -CommandName Test-ExistingIntuneApp { @{ Exists = $false } }
                Mock -CommandName Get-OrCreateAADGroup { 'group-id-456' }
                Mock -CommandName New-WinGetScript { 'script content' }
                Mock -CommandName Test-ProactiveRemediationLicense { $false }
                Mock -CommandName New-IntuneWinFile { }
                Mock -CommandName Get-AppIcon { $null }
                Mock -CommandName New-Win32App { @{ id = 'app-123' } }
                Mock -CommandName Grant-Win32AppAssignment { }

                Deploy-WinGetApp -AppId 'Test.App' -AppName 'Test App' -BasePath $TestPath

                Assert-MockCalled Get-OrCreateAADGroup -ParameterFilter {
                    $AppId -eq 'Test.App' -and
                    $AppName -eq 'Test App' -and
                    $GroupType -eq 'Uninstall'
                } -Times 1 -Exactly
            }
        }

        It 'uses custom group names when provided' {
            InModuleScope WingetIntunePublisher -ArgumentList $script:TestBasePath {
                param($TestPath)
                Mock -CommandName Test-ExistingIntuneApp { @{ Exists = $false } }
                Mock -CommandName Get-OrCreateAADGroup { 'group-id-custom' }
                Mock -CommandName New-WinGetScript { 'script content' }
                Mock -CommandName Test-ProactiveRemediationLicense { $false }
                Mock -CommandName New-IntuneWinFile { }
                Mock -CommandName Get-AppIcon { $null }
                Mock -CommandName New-Win32App { @{ id = 'app-123' } }
                Mock -CommandName Grant-Win32AppAssignment { }

                Deploy-WinGetApp -AppId 'Test.App' -AppName 'Test App' -BasePath $TestPath `
                    -InstallGroupName 'Custom Install Group' -UninstallGroupName 'Custom Uninstall Group'

                Assert-MockCalled Get-OrCreateAADGroup -ParameterFilter {
                    $GroupName -eq 'Custom Install Group' -and $GroupType -eq 'Install'
                } -Times 1 -Exactly

                Assert-MockCalled Get-OrCreateAADGroup -ParameterFilter {
                    $GroupName -eq 'Custom Uninstall Group' -and $GroupType -eq 'Uninstall'
                } -Times 1 -Exactly
            }
        }
    }

    Context 'Script Generation' {
        It 'creates install script file' {
            InModuleScope WingetIntunePublisher -ArgumentList $script:TestBasePath {
                param($TestPath)
                Mock -CommandName Test-ExistingIntuneApp { @{ Exists = $false } }
                Mock -CommandName Get-OrCreateAADGroup { 'group-id-123' }
                Mock -CommandName New-WinGetScript { 'install script content' }
                Mock -CommandName Test-ProactiveRemediationLicense { $false }
                Mock -CommandName New-IntuneWinFile { }
                Mock -CommandName Get-AppIcon { $null }
                Mock -CommandName New-Win32App { @{ id = 'app-123' } }
                Mock -CommandName Grant-Win32AppAssignment { }

                Deploy-WinGetApp -AppId 'Test.App' -AppName 'Test App' -BasePath $TestPath

                Assert-MockCalled New-WinGetScript -ParameterFilter {
                    $AppId -eq 'Test.App' -and $ScriptType -eq 'Install'
                } -Times 1 -Exactly
            }
        }

        It 'creates uninstall script file' {
            InModuleScope WingetIntunePublisher -ArgumentList $script:TestBasePath {
                param($TestPath)
                Mock -CommandName Test-ExistingIntuneApp { @{ Exists = $false } }
                Mock -CommandName Get-OrCreateAADGroup { 'group-id-123' }
                Mock -CommandName New-WinGetScript { 'uninstall script content' }
                Mock -CommandName Test-ProactiveRemediationLicense { $false }
                Mock -CommandName New-IntuneWinFile { }
                Mock -CommandName Get-AppIcon { $null }
                Mock -CommandName New-Win32App { @{ id = 'app-123' } }
                Mock -CommandName Grant-Win32AppAssignment { }

                Deploy-WinGetApp -AppId 'Test.App' -AppName 'Test App' -BasePath $TestPath

                Assert-MockCalled New-WinGetScript -ParameterFilter {
                    $AppId -eq 'Test.App' -and $ScriptType -eq 'Uninstall'
                } -Times 1 -Exactly
            }
        }

        It 'creates detection script file' {
            InModuleScope WingetIntunePublisher -ArgumentList $script:TestBasePath {
                param($TestPath)
                Mock -CommandName Test-ExistingIntuneApp { @{ Exists = $false } }
                Mock -CommandName Get-OrCreateAADGroup { 'group-id-123' }
                Mock -CommandName New-WinGetScript { 'detection script content' }
                Mock -CommandName Test-ProactiveRemediationLicense { $false }
                Mock -CommandName New-IntuneWinFile { }
                Mock -CommandName Get-AppIcon { $null }
                Mock -CommandName New-Win32App { @{ id = 'app-123' } }
                Mock -CommandName Grant-Win32AppAssignment { }

                Deploy-WinGetApp -AppId 'Test.App' -AppName 'Test App' -BasePath $TestPath

                Assert-MockCalled New-WinGetScript -ParameterFilter {
                    $AppId -eq 'Test.App' -and $ScriptType -eq 'DetectionRemediation'
                } -Times 1 -Exactly
            }
        }

        It 'sanitizes AppId in script filenames' {
            InModuleScope WingetIntunePublisher -ArgumentList $script:TestBasePath {
                param($TestPath)
                Mock -CommandName Test-ExistingIntuneApp { @{ Exists = $false } }
                Mock -CommandName Get-OrCreateAADGroup { 'group-id-123' }
                Mock -CommandName New-WinGetScript { 'script content' }
                Mock -CommandName Test-ProactiveRemediationLicense { $false }
                Mock -CommandName New-IntuneWinFile { }
                Mock -CommandName Get-AppIcon { $null }
                Mock -CommandName New-Win32App { @{ id = 'app-123' } }
                Mock -CommandName Grant-Win32AppAssignment { }

                Deploy-WinGetApp -AppId 'Test@App#Special' -AppName 'Test App' -BasePath $TestPath

                $appPath = Join-Path -Path $TestPath -ChildPath 'Test@App#Special'
                $installScript = Join-Path -Path $appPath -ChildPath 'installTest_App_Special.ps1'
                Test-Path $installScript | Should -Be $true
            }
        }
    }

    Context 'Proactive Remediation' {
        It 'creates proactive remediation when licensed' {
            InModuleScope WingetIntunePublisher -ArgumentList $script:TestBasePath {
                param($TestPath)
                Mock -CommandName Test-ExistingIntuneApp { @{ Exists = $false } }
                Mock -CommandName Get-OrCreateAADGroup { 'group-id-123' }
                Mock -CommandName New-WinGetScript { 'script content' }
                Mock -CommandName Test-ProactiveRemediationLicense { $true }
                Mock -CommandName New-ProactiveRemediation { 'remediation-id-789' }
                Mock -CommandName New-IntuneWinFile { }
                Mock -CommandName Get-AppIcon { $null }
                Mock -CommandName New-Win32App { @{ id = 'app-123' } }
                Mock -CommandName Grant-Win32AppAssignment { }

                Deploy-WinGetApp -AppId 'Test.App' -AppName 'Test App' -BasePath $TestPath

                Assert-MockCalled Test-ProactiveRemediationLicense -Times 1 -Exactly
                Assert-MockCalled New-ProactiveRemediation -Times 1 -Exactly -ParameterFilter {
                    $AppId -eq 'Test.App' -and $AppName -eq 'Test App' -and $GroupId -eq 'group-id-123'
                }
            }
        }

        It 'skips proactive remediation when not licensed' {
            InModuleScope WingetIntunePublisher -ArgumentList $script:TestBasePath {
                param($TestPath)
                Mock -CommandName Test-ExistingIntuneApp { @{ Exists = $false } }
                Mock -CommandName Get-OrCreateAADGroup { 'group-id-123' }
                Mock -CommandName New-WinGetScript { 'script content' }
                Mock -CommandName Test-ProactiveRemediationLicense { $false }
                Mock -CommandName New-ProactiveRemediation { }
                Mock -CommandName New-IntuneWinFile { }
                Mock -CommandName Get-AppIcon { $null }
                Mock -CommandName New-Win32App { @{ id = 'app-123' } }
                Mock -CommandName Grant-Win32AppAssignment { }

                Deploy-WinGetApp -AppId 'Test.App' -AppName 'Test App' -BasePath $TestPath

                Assert-MockCalled Test-ProactiveRemediationLicense -Times 1 -Exactly
                Assert-MockCalled New-ProactiveRemediation -Times 0
            }
        }
    }

    Context 'IntuneWin Package Creation' {
        It 'creates IntuneWin package with correct parameters' {
            InModuleScope WingetIntunePublisher -ArgumentList $script:TestBasePath {
                param($TestPath)
                Mock -CommandName Test-ExistingIntuneApp { @{ Exists = $false } }
                Mock -CommandName Get-OrCreateAADGroup { 'group-id-123' }
                Mock -CommandName New-WinGetScript { 'script content' }
                Mock -CommandName Test-ProactiveRemediationLicense { $false }
                Mock -CommandName New-IntuneWinFile { }
                Mock -CommandName Get-AppIcon { $null }
                Mock -CommandName New-Win32App { @{ id = 'app-123' } }
                Mock -CommandName Grant-Win32AppAssignment { }

                Deploy-WinGetApp -AppId 'Test.App' -AppName 'Test App' -BasePath $TestPath

                Assert-MockCalled New-IntuneWinFile -ParameterFilter {
                    $appid -eq 'Test.App' -and
                    $appname -eq 'Test App' -and
                    $setupfilename -like 'install*.ps1' -and
                    $destpath -eq $TestPath
                } -Times 1 -Exactly
            }
        }
    }

    Context 'App Upload' {
        It 'uploads Win32 app with correct command lines' {
            InModuleScope WingetIntunePublisher -ArgumentList $script:TestBasePath {
                param($TestPath)
                Mock -CommandName Test-ExistingIntuneApp { @{ Exists = $false } }
                Mock -CommandName Get-OrCreateAADGroup { 'group-id-123' }
                Mock -CommandName New-WinGetScript { 'script content' }
                Mock -CommandName Test-ProactiveRemediationLicense { $false }
                Mock -CommandName New-IntuneWinFile { }
                Mock -CommandName Get-AppIcon { $null }
                Mock -CommandName New-Win32App { @{ id = 'app-123' } }
                Mock -CommandName Grant-Win32AppAssignment { }

                Deploy-WinGetApp -AppId 'Test.App' -AppName 'Test App' -BasePath $TestPath

                Assert-MockCalled New-Win32App -ParameterFilter {
                    $installcmd -like 'powershell.exe -ExecutionPolicy Bypass -File install*.ps1' -and
                    $uninstallcmd -like 'powershell.exe -ExecutionPolicy Bypass -File uninstall*.ps1'
                } -Times 1 -Exactly
            }
        }

        It 'assigns groups when upload succeeds' {
            InModuleScope WingetIntunePublisher -ArgumentList $script:TestBasePath {
                param($TestPath)
                Mock -CommandName Test-ExistingIntuneApp { @{ Exists = $false } }
                Mock -CommandName Get-OrCreateAADGroup { param($GroupType) if ($GroupType -eq 'Install') { 'install-group-id' } else { 'uninstall-group-id' } }
                Mock -CommandName New-WinGetScript { 'script content' }
                Mock -CommandName Test-ProactiveRemediationLicense { $false }
                Mock -CommandName New-IntuneWinFile { }
                Mock -CommandName Get-AppIcon { $null }
                Mock -CommandName New-Win32App { @{ id = 'app-123' } }
                Mock -CommandName Grant-Win32AppAssignment { }

                Deploy-WinGetApp -AppId 'Test.App' -AppName 'Test App' -BasePath $TestPath -AvailableInstall 'Both'

                Assert-MockCalled Grant-Win32AppAssignment -ParameterFilter {
                    $AppName -eq 'Test App' -and
                    $InstallGroupId -eq 'install-group-id' -and
                    $UninstallGroupId -eq 'uninstall-group-id' -and
                    $AvailableInstall -eq 'Both'
                } -Times 1 -Exactly
            }
        }

        It 'does not assign groups when upload fails' {
            InModuleScope WingetIntunePublisher -ArgumentList $script:TestBasePath {
                param($TestPath)
                Mock -CommandName Test-ExistingIntuneApp { @{ Exists = $false } }
                Mock -CommandName Get-OrCreateAADGroup { 'group-id-123' }
                Mock -CommandName New-WinGetScript { 'script content' }
                Mock -CommandName Test-ProactiveRemediationLicense { $false }
                Mock -CommandName New-IntuneWinFile { }
                Mock -CommandName Get-AppIcon { $null }
                Mock -CommandName New-Win32App { $null }
                Mock -CommandName Grant-Win32AppAssignment { }

                Deploy-WinGetApp -AppId 'Test.App' -AppName 'Test App' -BasePath $TestPath

                Assert-MockCalled Grant-Win32AppAssignment -Times 0
            }
        }
    }

    Context 'Error Handling' {
        It 'handles upload errors gracefully' {
            InModuleScope WingetIntunePublisher -ArgumentList $script:TestBasePath {
                param($TestPath)
                Mock -CommandName Test-ExistingIntuneApp { @{ Exists = $false } }
                Mock -CommandName Get-OrCreateAADGroup { 'group-id-123' }
                Mock -CommandName New-WinGetScript { 'script content' }
                Mock -CommandName Test-ProactiveRemediationLicense { $false }
                Mock -CommandName New-IntuneWinFile { }
                Mock -CommandName Get-AppIcon { $null }
                Mock -CommandName New-Win32App { throw 'Upload failed' }
                Mock -CommandName Grant-Win32AppAssignment { }

                { Deploy-WinGetApp -AppId 'Test.App' -AppName 'Test App' -BasePath $TestPath } | Should -Not -Throw

                Assert-MockCalled Grant-Win32AppAssignment -Times 0
            }
        }

        It 'continues to completion even with errors' {
            InModuleScope WingetIntunePublisher -ArgumentList $script:TestBasePath {
                param($TestPath)
                Mock -CommandName Test-ExistingIntuneApp { @{ Exists = $false } }
                Mock -CommandName Get-OrCreateAADGroup { 'group-id-123' }
                Mock -CommandName New-WinGetScript { 'script content' }
                Mock -CommandName Test-ProactiveRemediationLicense { $false }
                Mock -CommandName New-IntuneWinFile { }
                Mock -CommandName Get-AppIcon { $null }
                Mock -CommandName New-Win32App { throw 'Graph API error' }
                Mock -CommandName Grant-Win32AppAssignment { }

                Deploy-WinGetApp -AppId 'Test.App' -AppName 'Test App' -BasePath $TestPath

                # Verify function completed (mocks were called up to the error point)
                Assert-MockCalled Test-ExistingIntuneApp -Times 1 -Exactly
                Assert-MockCalled Get-OrCreateAADGroup -Times 2 -Exactly
                Assert-MockCalled New-WinGetScript -Times 3 -Exactly
            }
        }
    }

    Context 'Icon Handling' {
        It 'searches for app icon' {
            InModuleScope WingetIntunePublisher -ArgumentList $script:TestBasePath {
                param($TestPath)
                Mock -CommandName Test-ExistingIntuneApp { @{ Exists = $false } }
                Mock -CommandName Get-OrCreateAADGroup { 'group-id-123' }
                Mock -CommandName New-WinGetScript { 'script content' }
                Mock -CommandName Test-ProactiveRemediationLicense { $false }
                Mock -CommandName New-IntuneWinFile { }
                Mock -CommandName Get-AppIcon { @{ type = 'image/png'; value = 'base64string' } }
                Mock -CommandName New-Win32App { @{ id = 'app-123' } }
                Mock -CommandName Grant-Win32AppAssignment { }

                Deploy-WinGetApp -AppId 'Test.App' -AppName 'Test App' -BasePath $TestPath

                Assert-MockCalled Get-AppIcon -ParameterFilter {
                    $AppId -eq 'Test.App' -and $AppName -eq 'Test App'
                } -Times 1 -Exactly
            }
        }

        It 'proceeds without error when icon not found' {
            InModuleScope WingetIntunePublisher -ArgumentList $script:TestBasePath {
                param($TestPath)
                Mock -CommandName Test-ExistingIntuneApp { @{ Exists = $false } }
                Mock -CommandName Get-OrCreateAADGroup { 'group-id-123' }
                Mock -CommandName New-WinGetScript { 'script content' }
                Mock -CommandName Test-ProactiveRemediationLicense { $false }
                Mock -CommandName New-IntuneWinFile { }
                Mock -CommandName Get-AppIcon { $null }
                Mock -CommandName New-Win32App { @{ id = 'app-123' } }
                Mock -CommandName Grant-Win32AppAssignment { }

                { Deploy-WinGetApp -AppId 'Test.App' -AppName 'Test App' -BasePath $TestPath } | Should -Not -Throw

                Assert-MockCalled New-Win32App -ParameterFilter {
                    $largeIcon -eq $null
                } -Times 1 -Exactly
            }
        }
    }

    Context 'Complete Workflow' {
        It 'executes all steps in correct order for successful deployment' {
            InModuleScope WingetIntunePublisher -ArgumentList $script:TestBasePath {
                param($TestPath)
                $callOrder = [System.Collections.Generic.List[string]]::new()

                Mock -CommandName Test-ExistingIntuneApp { $callOrder.Add('Test-ExistingIntuneApp'); @{ Exists = $false } }
                Mock -CommandName Get-OrCreateAADGroup { $callOrder.Add("Get-OrCreateAADGroup-$GroupType"); 'group-id-123' }
                Mock -CommandName New-WinGetScript { $callOrder.Add("New-WinGetScript-$ScriptType"); 'script content' }
                Mock -CommandName Test-ProactiveRemediationLicense { $callOrder.Add('Test-ProactiveRemediationLicense'); $true }
                Mock -CommandName New-ProactiveRemediation { $callOrder.Add('New-ProactiveRemediation'); 'remediation-id' }
                Mock -CommandName New-IntuneWinFile { $callOrder.Add('New-IntuneWinFile') }
                Mock -CommandName Get-AppIcon { $callOrder.Add('Get-AppIcon'); $null }
                Mock -CommandName New-Win32App { $callOrder.Add('New-Win32App'); @{ id = 'app-123' } }
                Mock -CommandName Grant-Win32AppAssignment { $callOrder.Add('Grant-Win32AppAssignment') }

                Deploy-WinGetApp -AppId 'Test.App' -AppName 'Test App' -BasePath $TestPath

                # Verify order of operations
                $callOrder[0] | Should -Be 'Test-ExistingIntuneApp'
                $callOrder[1] | Should -Be 'Get-OrCreateAADGroup-Install'
                $callOrder[2] | Should -Be 'Get-OrCreateAADGroup-Uninstall'
                $callOrder[3] | Should -Be 'New-WinGetScript-Install'
                $callOrder[4] | Should -Be 'New-WinGetScript-Uninstall'
                $callOrder[5] | Should -Be 'New-WinGetScript-DetectionRemediation'
                $callOrder[6] | Should -Be 'Test-ProactiveRemediationLicense'
                $callOrder[7] | Should -Be 'New-ProactiveRemediation'
                $callOrder[8] | Should -Be 'New-IntuneWinFile'
                $callOrder[9] | Should -Be 'Get-AppIcon'
                $callOrder[10] | Should -Be 'New-Win32App'
                $callOrder[11] | Should -Be 'Grant-Win32AppAssignment'
            }
        }
    }
}
