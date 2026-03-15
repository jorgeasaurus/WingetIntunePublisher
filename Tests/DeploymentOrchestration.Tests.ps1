BeforeAll {
    $ModulePath = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'WingetIntunePublisher.psd1'
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe 'Deploy-WinGetApp' {
    BeforeAll {
        $script:TestBasePath = Join-Path -Path $TestDrive -ChildPath 'DeploymentTests'
        New-Item -Path $script:TestBasePath -ItemType Directory -Force | Out-Null
    }

    Context 'Parameter Validation' {
        It 'requires AppId parameter' {
            InModuleScope WingetIntunePublisher {
                $command = Get-Command Deploy-WinGetApp
                $command.Parameters['AppId'].Attributes.Mandatory | Should -Contain $true
            }
        }

        It 'requires AppName parameter' {
            InModuleScope WingetIntunePublisher {
                $command = Get-Command Deploy-WinGetApp
                $command.Parameters['AppName'].Attributes.Mandatory | Should -Contain $true
            }
        }

        It 'requires BasePath parameter' {
            InModuleScope WingetIntunePublisher {
                $command = Get-Command Deploy-WinGetApp
                $command.Parameters['BasePath'].Attributes.Mandatory | Should -Contain $true
            }
        }

        It 'validates AvailableInstall parameter with ValidateSet' {
            InModuleScope WingetIntunePublisher -ArgumentList $script:TestBasePath {
                param($TestPath)
                Mock Test-ExistingIntuneApp { @{ Exists = $false } }
                Mock Get-OrCreateAADGroup { 'g1' }
                Mock New-WinGetScript { 'x' }
                Mock Test-ProactiveRemediationLicense { $false }
                Mock New-IntuneWinFile { }
                Mock Get-AppIcon { $null }
                Mock New-Win32App { @{ id = 'a1' } }
                Mock Grant-Win32AppAssignment { }

                { Deploy-WinGetApp -AppId 'Test.App' -AppName 'Test App' -BasePath $TestPath -AvailableInstall 'InvalidValue' } |
                    Should -Throw
            }
        }

        It 'accepts valid AvailableInstall values' {
            InModuleScope WingetIntunePublisher -ArgumentList $script:TestBasePath {
                param($TestPath)
                Mock Test-ExistingIntuneApp { @{ Exists = $false } }
                Mock Get-OrCreateAADGroup { 'g1' }
                Mock New-WinGetScript { 'x' }
                Mock Test-ProactiveRemediationLicense { $false }
                Mock New-IntuneWinFile { }
                Mock Get-AppIcon { $null }
                Mock New-Win32App { @{ id = 'a1' } }
                Mock Grant-Win32AppAssignment { }

                foreach ($val in @('User', 'Device', 'Both', 'None')) {
                    { Deploy-WinGetApp -AppId 'Test.App' -AppName 'Test App' -BasePath $TestPath -AvailableInstall $val } |
                        Should -Not -Throw
                }
            }
        }
    }

    Context 'Existing App Detection' {
        It 'skips deployment when app exists and Force not specified' {
            InModuleScope WingetIntunePublisher -ArgumentList $script:TestBasePath {
                param($TestPath)
                Mock Test-ExistingIntuneApp { @{ Exists = $true; Apps = @(@{ displayName = 'Test App'; id = 'e1' }) } }
                Mock Get-OrCreateAADGroup { 'g1' }
                Mock New-Win32App { @{ id = 'a1' } }

                Deploy-WinGetApp -AppId 'Test.App' -AppName 'Test App' -BasePath $TestPath

                Should -Invoke Test-ExistingIntuneApp -Times 1 -Exactly
                Should -Invoke Get-OrCreateAADGroup -Times 0
                Should -Invoke New-Win32App -Times 0
            }
        }

        It 'proceeds with deployment when app exists and Force is specified' {
            InModuleScope WingetIntunePublisher -ArgumentList $script:TestBasePath {
                param($TestPath)
                Mock Test-ExistingIntuneApp { @{ Exists = $true; Apps = @(@{ displayName = 'Test App'; id = 'e1' }) } }
                Mock Invoke-MgGraphRequest { @{ value = @() } }
                Mock Get-OrCreateAADGroup { 'g1' }
                Mock New-WinGetScript { 'x' }
                Mock Test-ProactiveRemediationLicense { $false }
                Mock New-IntuneWinFile { }
                Mock Get-AppIcon { $null }
                Mock New-Win32App { @{ id = 'a1' } }
                Mock Grant-Win32AppAssignment { }

                Deploy-WinGetApp -AppId 'Test.App' -AppName 'Test App' -BasePath $TestPath -Force

                Should -Invoke Test-ExistingIntuneApp -Times 1 -Exactly
                # Verify old app is deleted before creating new one
                Should -Invoke Invoke-MgGraphRequest -ParameterFilter { $Method -eq 'DELETE' -and $Uri -like '*mobileApps/e1*' } -Times 1
                Should -Invoke Get-OrCreateAADGroup -Times 2 -Exactly
                Should -Invoke New-Win32App -Times 1 -Exactly
            }
        }

        It 'proceeds with deployment when app does not exist' {
            InModuleScope WingetIntunePublisher -ArgumentList $script:TestBasePath {
                param($TestPath)
                Mock Test-ExistingIntuneApp { @{ Exists = $false } }
                Mock Get-OrCreateAADGroup { 'g1' }
                Mock New-WinGetScript { 'x' }
                Mock Test-ProactiveRemediationLicense { $false }
                Mock New-IntuneWinFile { }
                Mock Get-AppIcon { $null }
                Mock New-Win32App { @{ id = 'a1' } }
                Mock Grant-Win32AppAssignment { }

                Deploy-WinGetApp -AppId 'Test.App' -AppName 'Test App' -BasePath $TestPath

                Should -Invoke Get-OrCreateAADGroup -Times 2 -Exactly
                Should -Invoke New-Win32App -Times 1 -Exactly
            }
        }
    }

    Context 'Directory Creation' {
        It 'creates app directory under BasePath' {
            InModuleScope WingetIntunePublisher -ArgumentList $script:TestBasePath {
                param($TestPath)
                Mock Test-ExistingIntuneApp { @{ Exists = $false } }
                Mock Get-OrCreateAADGroup { 'g1' }
                Mock New-WinGetScript { 'x' }
                Mock Test-ProactiveRemediationLicense { $false }
                Mock New-IntuneWinFile { }
                Mock Get-AppIcon { $null }
                Mock New-Win32App { @{ id = 'a1' } }
                Mock Grant-Win32AppAssignment { }

                Deploy-WinGetApp -AppId 'Test.App' -AppName 'Test App' -BasePath $TestPath

                Join-Path $TestPath 'Test.App' | Test-Path | Should -Be $true
            }
        }

        It 'sanitizes AppId for directory names' {
            InModuleScope WingetIntunePublisher -ArgumentList $script:TestBasePath {
                param($TestPath)
                Mock Test-ExistingIntuneApp { @{ Exists = $false } }
                Mock Get-OrCreateAADGroup { 'g1' }
                Mock New-WinGetScript { 'x' }
                Mock Test-ProactiveRemediationLicense { $false }
                Mock New-IntuneWinFile { }
                Mock Get-AppIcon { $null }
                Mock New-Win32App { @{ id = 'a1' } }
                Mock Grant-Win32AppAssignment { }

                Deploy-WinGetApp -AppId 'Test@App#123' -AppName 'Test App' -BasePath $TestPath

                Join-Path $TestPath 'Test@App#123' | Test-Path | Should -Be $true
            }
        }
    }

    Context 'Group Management' {
        It 'creates install group with correct parameters' {
            InModuleScope WingetIntunePublisher -ArgumentList $script:TestBasePath {
                param($TestPath)
                Mock Test-ExistingIntuneApp { @{ Exists = $false } }
                Mock Get-OrCreateAADGroup { 'g1' }
                Mock New-WinGetScript { 'x' }
                Mock Test-ProactiveRemediationLicense { $false }
                Mock New-IntuneWinFile { }
                Mock Get-AppIcon { $null }
                Mock New-Win32App { @{ id = 'a1' } }
                Mock Grant-Win32AppAssignment { }

                Deploy-WinGetApp -AppId 'Test.App' -AppName 'Test App' -BasePath $TestPath

                Should -Invoke Get-OrCreateAADGroup -ParameterFilter {
                    $AppId -eq 'Test.App' -and $AppName -eq 'Test App' -and $GroupType -eq 'Install'
                } -Times 1 -Exactly
            }
        }

        It 'creates uninstall group with correct parameters' {
            InModuleScope WingetIntunePublisher -ArgumentList $script:TestBasePath {
                param($TestPath)
                Mock Test-ExistingIntuneApp { @{ Exists = $false } }
                Mock Get-OrCreateAADGroup { 'g1' }
                Mock New-WinGetScript { 'x' }
                Mock Test-ProactiveRemediationLicense { $false }
                Mock New-IntuneWinFile { }
                Mock Get-AppIcon { $null }
                Mock New-Win32App { @{ id = 'a1' } }
                Mock Grant-Win32AppAssignment { }

                Deploy-WinGetApp -AppId 'Test.App' -AppName 'Test App' -BasePath $TestPath

                Should -Invoke Get-OrCreateAADGroup -ParameterFilter {
                    $AppId -eq 'Test.App' -and $AppName -eq 'Test App' -and $GroupType -eq 'Uninstall'
                } -Times 1 -Exactly
            }
        }

        It 'uses custom group names when provided' {
            InModuleScope WingetIntunePublisher -ArgumentList $script:TestBasePath {
                param($TestPath)
                Mock Test-ExistingIntuneApp { @{ Exists = $false } }
                Mock Get-OrCreateAADGroup { 'g1' }
                Mock New-WinGetScript { 'x' }
                Mock Test-ProactiveRemediationLicense { $false }
                Mock New-IntuneWinFile { }
                Mock Get-AppIcon { $null }
                Mock New-Win32App { @{ id = 'a1' } }
                Mock Grant-Win32AppAssignment { }

                Deploy-WinGetApp -AppId 'Test.App' -AppName 'Test App' -BasePath $TestPath `
                    -InstallGroupName 'Custom Install Group' -UninstallGroupName 'Custom Uninstall Group'

                Should -Invoke Get-OrCreateAADGroup -ParameterFilter {
                    $GroupName -eq 'Custom Install Group' -and $GroupType -eq 'Install'
                } -Times 1 -Exactly

                Should -Invoke Get-OrCreateAADGroup -ParameterFilter {
                    $GroupName -eq 'Custom Uninstall Group' -and $GroupType -eq 'Uninstall'
                } -Times 1 -Exactly
            }
        }
    }

    Context 'Script Generation' {
        It 'creates install script file' {
            InModuleScope WingetIntunePublisher -ArgumentList $script:TestBasePath {
                param($TestPath)
                Mock Test-ExistingIntuneApp { @{ Exists = $false } }
                Mock Get-OrCreateAADGroup { 'g1' }
                Mock New-WinGetScript { 'x' }
                Mock Test-ProactiveRemediationLicense { $false }
                Mock New-IntuneWinFile { }
                Mock Get-AppIcon { $null }
                Mock New-Win32App { @{ id = 'a1' } }
                Mock Grant-Win32AppAssignment { }

                Deploy-WinGetApp -AppId 'Test.App' -AppName 'Test App' -BasePath $TestPath

                Should -Invoke New-WinGetScript -ParameterFilter {
                    $AppId -eq 'Test.App' -and $ScriptType -eq 'Install'
                } -Times 1 -Exactly
            }
        }

        It 'creates uninstall script file' {
            InModuleScope WingetIntunePublisher -ArgumentList $script:TestBasePath {
                param($TestPath)
                Mock Test-ExistingIntuneApp { @{ Exists = $false } }
                Mock Get-OrCreateAADGroup { 'g1' }
                Mock New-WinGetScript { 'x' }
                Mock Test-ProactiveRemediationLicense { $false }
                Mock New-IntuneWinFile { }
                Mock Get-AppIcon { $null }
                Mock New-Win32App { @{ id = 'a1' } }
                Mock Grant-Win32AppAssignment { }

                Deploy-WinGetApp -AppId 'Test.App' -AppName 'Test App' -BasePath $TestPath

                Should -Invoke New-WinGetScript -ParameterFilter {
                    $AppId -eq 'Test.App' -and $ScriptType -eq 'Uninstall'
                } -Times 1 -Exactly
            }
        }

        It 'creates detection script file' {
            InModuleScope WingetIntunePublisher -ArgumentList $script:TestBasePath {
                param($TestPath)
                Mock Test-ExistingIntuneApp { @{ Exists = $false } }
                Mock Get-OrCreateAADGroup { 'g1' }
                Mock New-WinGetScript { 'x' }
                Mock Test-ProactiveRemediationLicense { $false }
                Mock New-IntuneWinFile { }
                Mock Get-AppIcon { $null }
                Mock New-Win32App { @{ id = 'a1' } }
                Mock Grant-Win32AppAssignment { }

                Deploy-WinGetApp -AppId 'Test.App' -AppName 'Test App' -BasePath $TestPath

                Should -Invoke New-WinGetScript -ParameterFilter {
                    $AppId -eq 'Test.App' -and $ScriptType -eq 'DetectionRemediation'
                } -Times 1 -Exactly
            }
        }

        It 'sanitizes AppId in script filenames' {
            InModuleScope WingetIntunePublisher -ArgumentList $script:TestBasePath {
                param($TestPath)
                Mock Test-ExistingIntuneApp { @{ Exists = $false } }
                Mock Get-OrCreateAADGroup { 'g1' }
                Mock New-WinGetScript { 'x' }
                Mock Test-ProactiveRemediationLicense { $false }
                Mock New-IntuneWinFile { }
                Mock Get-AppIcon { $null }
                Mock New-Win32App { @{ id = 'a1' } }
                Mock Grant-Win32AppAssignment { }

                Deploy-WinGetApp -AppId 'Test@App#Special' -AppName 'Test App' -BasePath $TestPath

                $appPath = Join-Path $TestPath 'Test@App#Special'
                Join-Path $appPath 'installTest_App_Special.ps1' | Test-Path | Should -Be $true
            }
        }
    }

    Context 'Proactive Remediation' {
        It 'creates proactive remediation when licensed' {
            InModuleScope WingetIntunePublisher -ArgumentList $script:TestBasePath {
                param($TestPath)
                Mock Test-ExistingIntuneApp { @{ Exists = $false } }
                Mock Get-OrCreateAADGroup { 'g1' }
                Mock New-WinGetScript { 'x' }
                Mock Test-ProactiveRemediationLicense { $true }
                Mock New-ProactiveRemediation { 'rem-789' }
                Mock New-IntuneWinFile { }
                Mock Get-AppIcon { $null }
                Mock New-Win32App { @{ id = 'a1' } }
                Mock Grant-Win32AppAssignment { }

                Deploy-WinGetApp -AppId 'Test.App' -AppName 'Test App' -BasePath $TestPath

                Should -Invoke Test-ProactiveRemediationLicense -Times 1 -Exactly
                Should -Invoke New-ProactiveRemediation -Times 1 -Exactly -ParameterFilter {
                    $AppId -eq 'Test.App' -and $AppName -eq 'Test App' -and $GroupId -eq 'g1'
                }
            }
        }

        It 'skips proactive remediation when not licensed' {
            InModuleScope WingetIntunePublisher -ArgumentList $script:TestBasePath {
                param($TestPath)
                Mock Test-ExistingIntuneApp { @{ Exists = $false } }
                Mock Get-OrCreateAADGroup { 'g1' }
                Mock New-WinGetScript { 'x' }
                Mock Test-ProactiveRemediationLicense { $false }
                Mock New-ProactiveRemediation { }
                Mock New-IntuneWinFile { }
                Mock Get-AppIcon { $null }
                Mock New-Win32App { @{ id = 'a1' } }
                Mock Grant-Win32AppAssignment { }

                Deploy-WinGetApp -AppId 'Test.App' -AppName 'Test App' -BasePath $TestPath

                Should -Invoke Test-ProactiveRemediationLicense -Times 1 -Exactly
                Should -Invoke New-ProactiveRemediation -Times 0
            }
        }
    }

    Context 'IntuneWin Package Creation' {
        It 'creates IntuneWin package with correct parameters' {
            InModuleScope WingetIntunePublisher -ArgumentList $script:TestBasePath {
                param($TestPath)
                Mock Test-ExistingIntuneApp { @{ Exists = $false } }
                Mock Get-OrCreateAADGroup { 'g1' }
                Mock New-WinGetScript { 'x' }
                Mock Test-ProactiveRemediationLicense { $false }
                Mock New-IntuneWinFile { }
                Mock Get-AppIcon { $null }
                Mock New-Win32App { @{ id = 'a1' } }
                Mock Grant-Win32AppAssignment { }

                Deploy-WinGetApp -AppId 'Test.App' -AppName 'Test App' -BasePath $TestPath

                Should -Invoke New-IntuneWinFile -ParameterFilter {
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
                Mock Test-ExistingIntuneApp { @{ Exists = $false } }
                Mock Get-OrCreateAADGroup { 'g1' }
                Mock New-WinGetScript { 'x' }
                Mock Test-ProactiveRemediationLicense { $false }
                Mock New-IntuneWinFile { }
                Mock Get-AppIcon { $null }
                Mock New-Win32App { @{ id = 'a1' } }
                Mock Grant-Win32AppAssignment { }

                Deploy-WinGetApp -AppId 'Test.App' -AppName 'Test App' -BasePath $TestPath

                Should -Invoke New-Win32App -ParameterFilter {
                    $installcmd -like 'powershell.exe -ExecutionPolicy Bypass -File install*.ps1' -and
                    $uninstallcmd -like 'powershell.exe -ExecutionPolicy Bypass -File uninstall*.ps1'
                } -Times 1 -Exactly
            }
        }

        It 'assigns groups when upload succeeds' {
            InModuleScope WingetIntunePublisher -ArgumentList $script:TestBasePath {
                param($TestPath)
                Mock Test-ExistingIntuneApp { @{ Exists = $false } }
                Mock Get-OrCreateAADGroup {
                    param($GroupType)
                    if ($GroupType -eq 'Install') { 'install-gid' } else { 'uninstall-gid' }
                }
                Mock New-WinGetScript { 'x' }
                Mock Test-ProactiveRemediationLicense { $false }
                Mock New-IntuneWinFile { }
                Mock Get-AppIcon { $null }
                Mock New-Win32App { @{ id = 'a1' } }
                Mock Grant-Win32AppAssignment { }

                Deploy-WinGetApp -AppId 'Test.App' -AppName 'Test App' -BasePath $TestPath -AvailableInstall 'Both'

                Should -Invoke Grant-Win32AppAssignment -ParameterFilter {
                    $AppName -eq 'Test App' -and
                    $InstallGroupId -eq 'install-gid' -and
                    $UninstallGroupId -eq 'uninstall-gid' -and
                    $AvailableInstall -eq 'Both'
                } -Times 1 -Exactly
            }
        }

        It 'does not assign groups when upload returns null' {
            InModuleScope WingetIntunePublisher -ArgumentList $script:TestBasePath {
                param($TestPath)
                Mock Test-ExistingIntuneApp { @{ Exists = $false } }
                Mock Get-OrCreateAADGroup { 'g1' }
                Mock New-WinGetScript { 'x' }
                Mock Test-ProactiveRemediationLicense { $false }
                Mock New-IntuneWinFile { }
                Mock Get-AppIcon { $null }
                Mock New-Win32App { $null }
                Mock Grant-Win32AppAssignment { }

                { Deploy-WinGetApp -AppId 'Test.App' -AppName 'Test App' -BasePath $TestPath } | Should -Throw

                Should -Invoke Grant-Win32AppAssignment -Times 0
            }
        }
    }

    Context 'Error Handling' {
        It 'propagates upload errors to caller' {
            InModuleScope WingetIntunePublisher -ArgumentList $script:TestBasePath {
                param($TestPath)
                Mock Test-ExistingIntuneApp { @{ Exists = $false } }
                Mock Get-OrCreateAADGroup { 'g1' }
                Mock New-WinGetScript { 'x' }
                Mock Test-ProactiveRemediationLicense { $false }
                Mock New-IntuneWinFile { }
                Mock Get-AppIcon { $null }
                Mock New-Win32App { throw 'Upload failed' }
                Mock Grant-Win32AppAssignment { }

                { Deploy-WinGetApp -AppId 'Test.App' -AppName 'Test App' -BasePath $TestPath } | Should -Throw

                Should -Invoke Grant-Win32AppAssignment -Times 0
            }
        }

        It 'executes prerequisite steps before upload failure' {
            InModuleScope WingetIntunePublisher -ArgumentList $script:TestBasePath {
                param($TestPath)
                Mock Test-ExistingIntuneApp { @{ Exists = $false } }
                Mock Get-OrCreateAADGroup { 'g1' }
                Mock New-WinGetScript { 'x' }
                Mock Test-ProactiveRemediationLicense { $false }
                Mock New-IntuneWinFile { }
                Mock Get-AppIcon { $null }
                Mock New-Win32App { throw 'Graph API error' }
                Mock Grant-Win32AppAssignment { }

                try { Deploy-WinGetApp -AppId 'Test.App' -AppName 'Test App' -BasePath $TestPath } catch {}

                Should -Invoke Test-ExistingIntuneApp -Times 1 -Exactly
                Should -Invoke Get-OrCreateAADGroup -Times 2 -Exactly
                Should -Invoke New-WinGetScript -Times 3 -Exactly
            }
        }
    }

    Context 'Icon Handling' {
        It 'searches for app icon' {
            InModuleScope WingetIntunePublisher -ArgumentList $script:TestBasePath {
                param($TestPath)
                Mock Test-ExistingIntuneApp { @{ Exists = $false } }
                Mock Get-OrCreateAADGroup { 'g1' }
                Mock New-WinGetScript { 'x' }
                Mock Test-ProactiveRemediationLicense { $false }
                Mock New-IntuneWinFile { }
                Mock Get-AppIcon { @{ type = 'image/png'; value = 'base64string' } }
                Mock New-Win32App { @{ id = 'a1' } }
                Mock Grant-Win32AppAssignment { }

                Deploy-WinGetApp -AppId 'Test.App' -AppName 'Test App' -BasePath $TestPath

                Should -Invoke Get-AppIcon -ParameterFilter {
                    $AppId -eq 'Test.App' -and $AppName -eq 'Test App'
                } -Times 1 -Exactly
            }
        }

        It 'proceeds without error when icon not found' {
            InModuleScope WingetIntunePublisher -ArgumentList $script:TestBasePath {
                param($TestPath)
                Mock Test-ExistingIntuneApp { @{ Exists = $false } }
                Mock Get-OrCreateAADGroup { 'g1' }
                Mock New-WinGetScript { 'x' }
                Mock Test-ProactiveRemediationLicense { $false }
                Mock New-IntuneWinFile { }
                Mock Get-AppIcon { $null }
                Mock New-Win32App { @{ id = 'a1' } }
                Mock Grant-Win32AppAssignment { }

                { Deploy-WinGetApp -AppId 'Test.App' -AppName 'Test App' -BasePath $TestPath } | Should -Not -Throw

                Should -Invoke New-Win32App -ParameterFilter {
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

                Mock Test-ExistingIntuneApp { $callOrder.Add('Test-ExistingIntuneApp'); @{ Exists = $false } }
                Mock Get-OrCreateAADGroup { $callOrder.Add("Get-OrCreateAADGroup-$GroupType"); 'g1' }
                Mock New-WinGetScript { $callOrder.Add("New-WinGetScript-$ScriptType"); 'x' }
                Mock Test-ProactiveRemediationLicense { $callOrder.Add('Test-ProactiveRemediationLicense'); $true }
                Mock New-ProactiveRemediation { $callOrder.Add('New-ProactiveRemediation'); 'rem-id' }
                Mock New-IntuneWinFile { $callOrder.Add('New-IntuneWinFile') }
                Mock Get-AppIcon { $callOrder.Add('Get-AppIcon'); $null }
                Mock New-Win32App { $callOrder.Add('New-Win32App'); @{ id = 'a1' } }
                Mock Grant-Win32AppAssignment { $callOrder.Add('Grant-Win32AppAssignment') }

                Deploy-WinGetApp -AppId 'Test.App' -AppName 'Test App' -BasePath $TestPath

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
