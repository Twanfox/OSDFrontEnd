<#
    .SYNOPSIS
        OSDFrontEnd.ps1 is a dynamic front end to be used during OSD Deployments. 
    .DESCRIPTION
        OSDFrontEnd.ps1 is a new way of handling the front end of OSD Deployments.
        The ability of PowerShell coupled with the layout style of Xaml meet for a
        powerful combination of form and function. Added to this is the ability to
        import code and content panels dynamically allow for a fast-to-update model
        that will improve the deployment experience.
    .PARAMETER XamlFile
        The XamlFile parameter is the main window that the OSDFrontEnd is to load.
    .PARAMETER Uri
        The Uri parameter is the web location of the additional content to be downloaded
    .PARAMETER ManifestName
        This is the name of the manifest file at the Uri location to be downloaded first.
        This file must exist for any additional files to exist, and the elements within it
        must be cryptographically signed before the OSD Front End code will incorporate them.
    .NOTES
        Operating System Deployment Menu for SCCM 2012
        Authored by Chris Wroten
        Inspired by Taylor Harris
        Last Updated: 4/13/2017
    .EXAMPLE
        .\OSDFrontEnd.ps1

        This example launches the OSD Front End with the defaults defined in the parameters.
#>

Param(
    [string] $XamlFile = 'OSDFrontEndForm.xaml',
    [string] $Uri = 'http://dc1-w-osdmgt1p.dvuadmin.net/OSDFrontEnd',
    [string] $ManifestName = 'Manifest.xml',
    [switch] $TestMode
)

# Required to use XAML GUI components
$LoadedAssemblies = [AppDomain]::CurrentDomain.GetAssemblies()
if (($LoadedAssemblies | Where-Object { $_.FullName -match "PresentationFramework"}).Count -eq 0) {
    [void][System.Reflection.Assembly]::LoadWithPartialName('presentationframework')
}

# Objects for interacting with Task Sequence environment
try {
    $TSEnv = New-Object -COMObject Microsoft.SMS.TSEnvironment -ErrorAction Stop
} catch {
    # $TSEnv = New-Object PSObject
}

# Below line is only needed if launching AFTER a Task Sequence is started.
# $TSProgressUI = New-Object -COMObject Microsoft.SMS.TSProgressUI

. '.\OSDFrontEnd.Functions.ps1'

#===========================================================================
# Parse XAML into Nodes to be converted into PowerShell objects
#===========================================================================

$WindowXaml = Get-Content $XamlFile

# Loads Parsed XAML into a .NET Form object container
$Form = Load-XamlFile $WindowXaml -LoadVariables 

#===========================================================================
# This is a safety net, in case we fail to download the manifest or
# other files later. Get out of jail free card.
#===========================================================================

$Form.Add_Loaded(
    {
        Start-RunspaceManager
    }
)

$Form.Add_Closed(
    {
        Stop-RunspaceManager
    }
)

$PreLoadCancelButton.Add_Click(
    {
        if (-not [string]::IsNullOrEmpty($TSEnv)) {
            Restart-Computer
        }

        $Form.Close()
    }
)

#===========================================================================
# Logic to pre-populate certain elements and controls of the GUI
#===========================================================================

$IsError = $False

$CertificateList = Import-VerificationCertificates

if ($CertificateList.Count -eq 0) {
    $ErrorMessageText.Text = "Failed to load our certificate(s) for verification. Cannot continue."
    $IsError = $True
}

$CodeFiles = @()

if ($IsError -ne $True) {
	if (Request-OSDFrontEndFile -URL $Uri -FileName $ManifestName -TestMode:$TestMode) {
		[xml] $ManifestXml = Get-Content $ManifestName

		foreach ($FileXml in $ManifestXml.SelectNodes("/ContentPanelManifest/*")) {
			if (-not (Request-OSDFrontEndFile -Url $Uri -FileName $FileXml.Name -TestMode:$TestMode)) {
				# Problem. Failed to download a file specified in the Manifest. Cannot continue.
				$ErrorMessageText.Text = $ErrorMessageText.Text, "Failed to retrieve file $($FileXml.Name) as specified in the manifest." -join " "
				$IsError = $True
			}

			if ($CertificateList.ContainsKey($FileXml.Thumbprint)) {
				$Certificate = $CertificateList[$FileXml.Thumbprint]

				if (-not (Test-FileSignature -Certificate $Certificate -FileName $FileXml.Name -Signature $FileXml.FileSignature)) {
					# Double problem. Got file, but the signature is bad.
					Remove-Item $FileXml.Name
					$ErrorMessageText.Text = $ErrorMessageText.Text, "Failed to verify the signature of file $($FileXml.Name), verification failure." -join " "
					$IsError = $True
				}

				$CodeFiles += $FileXml.Name
			} else {
                # Oops. We don't have a certificate to validate this signature anymore.
				$ErrorMessageText.Text = $ErrorMessageText.Text, "Failed to verify the signature of file $($FileXml.Name), certificate not found." -join " "
				$IsError = $True
			}
		}
	} else {
		$ErrorMessageText.Text = $ErrorMessageText.Text, "Failed to retrieve manifest file $ManifestName. Verify connectivity by connecting another machine to this subnet and browsing to $Uri" -join " "
		$IsError = $True
	}
}

if ($IsError -ne $True) {
    foreach ($FileName in $CodeFiles) {
        $File = Get-Item -Path $FileName

        if ($File.Extension -eq '.xaml') {
            if ($ContentGrid -ne $null -and (Test-Path $File.FullName) -eq $true) {
                $ContentXaml = Get-Content $File.FullName

                [xml] $ContentXml = $ContentXaml

                Write-Host "Testing import Xaml for a $($ContentXml.DocumentElement.Name)"
                if ($ContentXml.DocumentElement.Name -eq 'UserControl' -and ($ContentXml.DocumentElement.Attributes | where Name -like 'x:Class').Value -like '*.ContentPanel') {
                    Write-Host "Loading content panel $(($ContentXml.DocumentElement.Attributes | where Name -like 'x:Class').Value)"

                    $ContentControls = Load-XamlFile $ContentXaml -LoadVariables

                    $ContentGrid.Children.Clear() | Out-Null
                    $ContentGrid.Children.Add($ContentControls) | Out-Null
                } else {
                    Write-Host "Skipping panel '$(($ContentXml.DocumentElement.Attributes | where Name -like 'x:Class').Value)'"
                }
            }
        }
    }

    # We need to do this last to ensure all of our 'layout grids' have been successfully loaded.
    foreach ($FileName in $CodeFiles) {
        $File = Get-Item -Path $FileName

        if ($File.Extension -eq '.ps1') {
            if ((Test-Path $File.FullName) -eq $True) {
                . $File.FullName
            }
        }
    }
}

#===========================================================================
# Displays/Initiates GUI and interacts with TS Environment visual elements
#===========================================================================

# Hides Task Sequence progress bar until the menu exits and process resumes
# $TSProgressUI.CloseProgressDialog()
# $TSProgressUI = $null

# Displays the actual menu for user interaction
Initialize-DisplayPanels

if ($TestMode -eq $true) {
    $Form.Height = 768
    $Form.Width = 1024
    $Form.WindowStyle='SingleBorderWindow'
    $Form.WindowState='Normal'
}

$Form.ShowDialog() | Out-Null

if ($TestMode -eq $true) {
    
    foreach ($FileXml in $ManifestXml.SelectNodes("/ContentPanelManifest/*")) {
        if (Test-Path $FileXml.Name) {
            Remove-Item $FileXml.Name
        }
    }

    Remove-Item $ManifestName
}
