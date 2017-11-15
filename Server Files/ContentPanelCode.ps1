$Script:RunningTools = @()

Function Show-Process {
    Param(
        $Process,
        [Switch]
        $Maximize
    )

    $Sig = '
        [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
        [DllImport("user32.dll")] public static extern int SetForegroundWindow(IntPtr hwnd);
    '

    if ($Maximize) { $Mode = 3 } else { $Mode = 4 }
    $Type = Add-Type -MemberDefinition $Sig -Name WindowAPI -PassThru
    $hwnd = $Process.MainWindowHandle
    $null = $Type::ShowWindowAsync($hwnd, $Mode)
    $null = $Type::SetForegroundWindow($hwnd)
}

$PopulateAppSelector = {
    $Param = $SyncHash.Argument
    $Creds = new-object -typename System.Management.Automation.PSCredential -argumentlist $Param.UserName, $Param.Password

    $Packages = Get-WmiObject -ComputerName $Param.Server -Query 'SELECT PackageID, ProgramName FROM SMS_Program WHERE ProgramName LIKE "%_OSD_%" ORDER BY ProgramName' -Namespace "ROOT\SMS\SITE_$($Param.SiteCode)" -Credential $Creds
    $PackageFailureMessage = [string]::Empty

    if (-not [string]::IsNullOrEmpty($Packages)) {
        $SelectedAttributes = @('PackageID', 'ProgramName')

        $ManifestXml = New-Object System.Xml.XmlDocument
        $ManifestXml.AppendChild($ManifestXml.CreateXmlDeclaration('1.0', 'utf-8', $null)) | Out-Null
        $ManifestXml.AppendChild($ManifestXml.CreateElement("PackageList")) | Out-Null
        $ManifestXml.LastChild.Attributes.Append($ManifestXml.CreateAttribute("xmlns")) | Out-Null

        Foreach ($Pkg in $Packages) {
            $PackageXml = $ManifestXml.CreateElement("Package")
            foreach ($Attribute in $SelectedAttributes) {
                $PackageXml.AppendChild($ManifestXml.CreateElement($Attribute)) | Out-Null
                if ($Pkg."$Attribute" -ne $null) {
                    $Value = $Pkg."$Attribute".ToString() -replace "_OSD_", ""
                    $PackageXml.LastChild.AppendChild($ManifestXml.CreateTextNode($Value)) | Out-Null
                }
            }
            $PackageXml.AppendChild($ManifestXml.CreateElement("PackageVariableTag")) | Out-Null
            $PackageTag = "{0}:{1}" -f $Pkg.PackageId, $Pkg.ProgramName
            $PackageXml.LastChild.AppendChild($ManifestXml.CreateTextNode($PackageTag)) | Out-Null
            $ManifestXml.DocumentElement.AppendChild($PackageXml) | Out-Null
        }
    } else {
        $PackageFailureMessage = "Cannot look up packages from SCCM. Reason: $($Error[0].Exception.Message)"
    }

    if (-not [string]::IsNullOrEmpty($PackageFailureMessage)) {
        [action] $OutputAction = { 
            $SyncHash.Output.Content = "<Label>$PackageFailureMessage</Label>" 
        }
    } else {
        [action] $OutputAction = {
            $SyncHash.Output.DataContext = $ManifestXml
            $AppSelectorBinding = New-Object System.Windows.Data.Binding
            $AppSelectorBinding.XPath = '/PackageList/*'
            $SyncHash.Output.SetBinding([System.Windows.Controls.ListView]::ItemsSourceProperty, $AppSelectorBinding) | Out-Null
        }
    }
    $SyncHash.Parent.Dispatcher.Invoke($OutputAction)
}

Function Check-DriveAvailability {
    [Array] $FixedDisks = (Get-Disk | Where BusType -in @('ATA', 'SATA', 'SAS'))

    if ($FixedDisks.Count -eq 0) {
        return $False
    }

    return $True
}

Function Perform-PreflightChecks {
    $LaunchBuild = $True

    if (-not (Check-PowerStatus)) {

        if ([System.Windows.MessageBox]::Show("System is running on battery power. Do you want to continue?", "Power Preflight", [System.Windows.MessageBoxButton]::OkCancel) `
             -eq [System.Windows.MessageBoxResult]::Cancel) {
            $LaunchBuild = $false
        }
    }

    if ($LaunchBuild -and -not (Check-DriveAvailability)) {
        [void][System.Windows.MessageBox]::Show("No fixed drives detected, please verify hardware before attempting to image.", "Drive Availability Preflight", [System.Windows.MessageBoxButton]::OK)
        $LaunchBuild = $false
    }

    if ($TimeZoneSelect.SelectedItem -eq $null) {
        [void][System.Windows.MessageBox]::Show("Please select a time zone before continuing.", "Configuration Preflight", [System.Windows.MessageBoxButton]::OK)
        $LaunchBuild = $false
    }

    Write-Output $LaunchBuild
}

Function Filter-OrganizationalUnits {
    Param(
        [xml] $OUList,
        [string] $Domain
    )

    $FilteredList = New-Object System.Collections.ArrayList
    $OUList.SelectNodes("//OrganizationalUnit[Name = '$Domain']") | Foreach { 
        $NewOU = New-Object PSObject -Property @{DisplayName=$_.DisplayName; Value=$_.Value; Default=$false}
        If (($_ | Get-Member -MemberType Property | Select -Expand Name) -contains 'Default') {
            $NewOU.Default = $true
        }
        [void]$FilteredList.Add($NewOU)
    }
    Write-Output $FilteredList
}

Function Initialize-CoreControls {
    if (Test-Path '.\ContentPanelConfiguration.xml') {
        $CPConfig = [xml] (Get-Content '.\ContentPanelConfiguration.xml')

        $Global:SCCMServer = $CPConfig.SelectSingleNode('/Configuration/SCCM/Server')."#Text"
        $Global:SCCMSiteCode = $CPConfig.SelectSingleNode('/Configuration/SCCM/SiteCode')."#Text"
        $Global:SCCMUserName = $CPConfig.SelectSingleNode('/Configuration/SCCM/ReadOnlyUser/UserName')."#Text"
        $Global:SCCMPassword = ($CPConfig.SelectSingleNode('/Configuration/SCCM/ReadOnlyUser/Password')."#Text" | ConvertTo-SecureString -AsPlainText -Force)

        $Global:ToolsPassword = $CPConfig.SelectSingleNode('/Configuration/AdvancedTools/Password')."#Text"
    }

    if (Test-Path '.\TimeZones.xml') {
        $Global:TZXmlData = $ContentInnerGrid.FindResource('TZXmlData')
        $TZXmlData.Source = (Resolve-Path '.\TimeZones.xml').ProviderPath
    }

    if (Test-Path '.\OUStructuralMap.xml') {
        $Global:OUXmlData = $ContentInnerGrid.FindResource('OUXmlData')
        $OUXmlData.Source = (Resolve-Path '.\OUStructuralMap.xml').ProviderPath

        $DomainSelect.SelectedIndex = 0
    }

    # Pre-populates PC name text box with last known SCCM client name if available
    if (-not [string]::IsNullOrEmpty($TSEnv)) {
        $HostNameBox.Text = $TSEnv.Value("_SMSTSMachineName")
    } 

    $Creds = new-object -typename System.Management.Automation.PSCredential -argumentlist $Global:SCCMUserName, $Global:SCCMPassword

    $DiscoveredUuid = (Get-WmiObject uuid -Namespace root\cimv2 -class win32_computersystemproduct).uuid
    $DiscoveredMac = (@() + ((get-ciminstance win32_networkadapter -property Name,MacAddress,AdapterType | where adaptertype -eq "Ethernet 802.3").MACAddress))[0]

    $SCCMObjectData = Get-WMIObject -ComputerName $Global:SCCMServer -Namespace "root\sms\site_$Global:SCCMSiteCode" -Query "select * from sms_r_system where macaddresses like '$DiscoveredMac' or smbiosguid = '$DiscoveredUuid'" -Credential $Creds

    if ($SCCMObjectData -ne $null) {
        New-DisplayPanelEntry -Label 'ResourceId' -Description 'SCCM Resource ID' -Value $SCCMObjectData.ResourceId
    } else {
        New-DisplayPanelEntry -Label 'ResourceId' -Description 'SCCM Resource ID' -Value "Not Found"
    }

    #####
    #
    # Event handlers. Code them up here in our 'Codebehind' way.
    #
    #####
    $Script:PrevButton = [string]::Empty

    $ContentControls.Add_Loaded(
        {
            Fixup-MainForm
            $AppSelectorArgument = New-Object PSObject -Property @{
                Server = $Global:SCCMServer
                SiteCode = $Global:SCCMSiteCode
                UserName = $Global:SCCMUserName
                Password = $Global:SCCMPassword
            }

            Start-Worker -ScriptBlock $PopulateAppSelector -ParentControl $ContentGrid.Children[0] -OutputControl 'AppSelector' -Argument $AppSelectorArgument | Out-Null
        }
    )

    $DomainSelect.Add_SelectionChanged(
        {
            # Clear the old Values
            [System.Windows.Data.BindingOperations]::ClearBinding($OUTreeSelector, [System.Windows.Controls.TreeView]::ItemsSourceProperty)
            $OUSelect.Text = [string]::Empty

            # Set the binding so we can select a new one
            $OUBinding = New-Object System.Windows.Data.Binding
            $OUBinding.Source = $OUXmlData
            $OUBinding.XPath = "/OrganizationalUnitMap/OrganizationalUnit[Name = '$($DomainSelect.SelectedValue.ToString())']"
            [void]$OUTreeSelector.SetBinding([System.Windows.Controls.TreeView]::ItemsSourceProperty, $OUBinding)
        }
    )

    $OUSelect.Add_PreviewMouseUp(
        {
            if ($OUPopup.IsOpen -eq $True) {
				$OUPopup.IsOpen = $False
            } else {
                # $OUPopup.VerticalOffset = $OUSelect.Height
				$OUPopup.IsOpen = $True
            }
        }
    )
	
	$OUPopup.Add_Opened(
		{
			[System.Windows.Input.FocusManager]::SetFocusedElement([System.Windows.Input.FocusManager]::GetFocusScope($OUTreeSelector), $OUTreeSelector)	
		}
	)
	
    $OUTreeSelector.Add_SelectedItemChanged(
        {
            if ($OUTreeSelector.SelectedItem.HasAccess -eq 'True') {
                $OUSelect.Text = $OUTreeSelector.SelectedItem.DistinguishedName.ToString()
                $OUPopup.IsOpen = $False
            }
        }
    )

    # Start Image
    $BeginButton.Add_Click(
        {
            # Sets Task Sequence variables based on end user selection
#            if (-not [string]::IsNullOrEmpty($TSEnv)) {
                if (-not (Perform-PreflightChecks)) {
                    return
                }

                Write-Host "Setting OSDComputerName to $($HostNameBox.Text)"
                $TSEnv.Value("OSDComputerName") = $HostNameBox.Text

#                $SelectedTZ = "{0} Standard Time" -f $TimeZoneSelect.SelectedValue.ToString()
                $SelectedTZ = $TimeZoneSelect.SelectedValue.ToString()
                Write-Host "Setting OSDTimeZone to $SelectedTZ"
                $TSEnv.Value("OSDTimeZone") = $SelectedTZ

                $Domain = 'Admin'
                if ($DomainSelect.SelectedValue.ToString() -eq 'Acad') {
                    $Domain = 'Acad'
                }
                Write-Host "Setting OSDomain to $Domain"
                $TSEnv.Value("OSDomain") = $Domain

                $PackageVariablePrefix = 'WIZSELECTED'
                $PackageIndex = 0
                Write-Host "Processing $($AppSelector.SelectedItems.Count) selected applications."

                foreach ($Package in $AppSelector.SelectedItems) {
                    $PackageIndex += 1
                    $PackageVariable = ("{0}{1}" -f $PackageVariablePrefix, $PackageIndex.ToString("000"))
                    Write-Host "Setting $PackageVariable to $($Package.PackageVariableTag)"
                    $TSEnv.Value($PackageVariable) = $Package.PackageVariableTag
                }
#            }

            # Closes the menu
            $Form.Close()
        }
    )

    # Cancel (Restart)
    $RestartButton.Add_Click(
        {
            if (-not [string]::IsNullOrEmpty($TSEnv)) {
                Restart-Computer
            }

            $Form.Close()
        }
    )

    $CmdAuthPasswordOkButton.Add_Click(
        {
            $HashedPassword = (-join ([Security.Cryptography.HashAlgorithm]::Create('SHA256').ComputeHash([System.Text.Encoding]::UTF8.GetBytes($CmdPassword.Password))))
            $IsVerified = ($HashedPassword -eq $Global:ToolsPassword)

            $CmdToLaunch = $CmdAuthButton.Tag
            if ($IsVerified -and -not [string]::IsNullOrEmpty($CmdToLaunch)) {
                $Process = Start-Process (Join-Path $env:SystemRoot $CmdToLaunch) -PassThru
                $NewProcessData = New-Object PSObject -Property @{
                    Pid = $Process.Id
                    Name = $Process.Name
                    PidAndName = ("{0} : {1}" -f $Process.Id, $Process.Name)
                    UnderlyingObject = $Process
                }

                Write-Host $Script:RunningTools
                $Script:RunningTools += $NewProcessData
                $RunningAppsList.ItemsSource = $Script:RunningTools
            }
            $CmdAuthButton.Tag = [string]::Empty

            $CmdPassword.Password = [string]::Empty
            $ContentControls.FindName($Script:PrevButton).IsChecked = $true

            $ButtonStack.IsEnabled = $true
        }
    )

    $CmdAuthPasswordCancelButton.Add_Click(
        {
            $CmdPassword.Password = [string]::Empty
            $CmdAuthButton.Tag = [string]::Empty

#            Write-Host "Enabling previous enabled radio $Script:PrevButton"
            $ContentControls.FindName($Script:PrevButton).IsChecked = $true

            $ButtonStack.IsEnabled = $true
        }
    )
}

Function Fixup-MainForm {
    # Put in here any adjustments that need to be made to the main form
}

Initialize-CoreControls
