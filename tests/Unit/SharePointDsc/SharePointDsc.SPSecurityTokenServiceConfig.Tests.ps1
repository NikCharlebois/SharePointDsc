[CmdletBinding()]
param
(
    [Parameter()]
    [string]
    $SharePointCmdletModule = (Join-Path -Path $PSScriptRoot `
            -ChildPath "..\Stubs\SharePoint\15.0.4805.1000\Microsoft.SharePoint.PowerShell.psm1" `
            -Resolve)
)

$script:DSCModuleName = 'SharePointDsc'
$script:DSCResourceName = 'SPSecurityTokenServiceConfig'
$script:DSCResourceFullName = 'MSFT_' + $script:DSCResourceName

function Invoke-TestSetup
{
    try
    {
        Import-Module -Name DscResource.Test -Force

        Import-Module -Name (Join-Path -Path $PSScriptRoot `
                -ChildPath "..\UnitTestHelper.psm1" `
                -Resolve)

        $Global:SPDscHelper = New-SPDscUnitTestHelper -SharePointStubModule $SharePointCmdletModule `
            -DscResource $script:DSCResourceName
    }
    catch [System.IO.FileNotFoundException]
    {
        throw 'DscResource.Test module dependency not found. Please run ".\build.ps1 -Tasks build" first.'
    }

    $script:testEnvironment = Initialize-TestEnvironment `
        -DSCModuleName $script:DSCModuleName `
        -DSCResourceName $script:DSCResourceFullName `
        -ResourceType 'Mof' `
        -TestType 'Unit'
}

function Invoke-TestCleanup
{
    Restore-TestEnvironment -TestEnvironment $script:testEnvironment
}

Invoke-TestSetup

try
{
    InModuleScope -ModuleName $script:DSCResourceFullName -ScriptBlock {
        Describe -Name $Global:SPDscHelper.DescribeHeader -Fixture {
            BeforeAll {
                Invoke-Command -ScriptBlock $Global:SPDscHelper.InitializeScript -NoNewScope

                function Add-SPDscEvent
                {
                    param (
                        [Parameter(Mandatory = $true)]
                        [System.String]
                        $Message,

                        [Parameter(Mandatory = $true)]
                        [System.String]
                        $Source,

                        [Parameter()]
                        [ValidateSet('Error', 'Information', 'FailureAudit', 'SuccessAudit', 'Warning')]
                        [System.String]
                        $EntryType,

                        [Parameter()]
                        [System.UInt32]
                        $EventID
                    )
                }
            }

            Context -Name "When the Security Token Service is null" -Fixture {
                BeforeAll {
                    Mock -CommandName Get-SPSecurityTokenServiceConfig -MockWith {
                        return $null
                    }

                    $testParams = @{
                        IsSingleInstance = "Yes"
                        Name             = "Security Token Service"
                    }
                }

                It "Should return false when the Test method is called" {
                    Test-TargetResource @testParams | Should -Be $false
                }
            }

            Context -Name "When setting the configurations for the Security Token Service" {
                BeforeAll {
                    $params = @{
                        IsSingleInstance = "Yes"
                        Name             = "New name"
                        Ensure           = "Present"
                    }
                    Mock -CommandName Get-SPSecurityTokenServiceConfig -MockWith {
                        return @{
                            Name                  = "Security Token Service"
                            NameIdentifier        = "12345-12345-12345-12345@12345-12345"
                            UseSessionCookies     = $false
                            AllowOAuthOverHttp    = $false
                            AllowMetadataOverHttp = $false
                        } | Add-Member ScriptMethod Update {
                            $Global:UpdatedCalled = $true
                        } -PassThru
                    }
                }

                It "Should properly configure the security token service" {
                    Set-TargetResource @params
                }

                It "Should return ensure equals Present" {
                    (Get-TargetResource @params).Ensure | Should -Be "Present"
                }

                It "Should throw an error when trying to set to Absent" {
                    $params.Ensure = "Absent"
                    { Set-TargetResource @params } | Should -Throw ("This resource cannot undo Security " + `
                            "Token Service Configuration changes. Please set Ensure to Present or omit the resource")
                }
            }
        }
    }
}
finally
{
    Invoke-TestCleanup
}
