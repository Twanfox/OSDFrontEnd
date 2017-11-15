## OSD Front End Functions File

#region Multithreading Management
Function Start-RunspaceManager {
    $Global:JobManager = [hashtable]::Synchronized(@{})
    $Global:JobList = [system.collections.arraylist]::Synchronized((New-Object System.Collections.ArrayList))

    #region Background runspace to clean up jobs
    $JobManager.IsEnabled = $True
    $Runspace = [runspacefactory]::CreateRunspace()
    $Runspace.ApartmentState = "STA"
    $Runspace.ThreadOptions = "ReuseThread"          
    $Runspace.Open()        
    $Runspace.SessionStateProxy.SetVariable("JobManager",$JobManager)     
    $Runspace.SessionStateProxy.SetVariable("JobList",$JobList) 
    $JobManager.PowerShell = [PowerShell]::Create().AddScript({
        #Routine to handle completed runspaces
        Do {    
            Start-Sleep -Seconds 1     
            Foreach($Job in $JobList) {            
                If ($Job.State.IsCompleted -or -not $JobManager.IsEnabled) {
                    if ($JobManager.IsEnabled) {
                        [void]$Job.PowerShell.EndInvoke($Job.State)
                    } else {
                        $Job.PowerShell.Stop()
                    }
                    $Job.PowerShell.Runspace.Dispose()
                    $Job.PowerShell.Dispose()
                    $Job.State = $null
                    $Job.PowerShell = $null               
                } 
            }
            #Clean out unused runspace jobs
            $JobList.Clone() | Where {
                $_.State -eq $Null
            } | ForEach {
                $JobList.Remove($_)
            }
        } while ($JobManager.IsEnabled)
    })
    $JobManager.PowerShell.Runspace = $Runspace
    $JobManager.State = $JobManager.PowerShell.BeginInvoke()  
    #endregion Background runspace to clean up jobs
}

Function Stop-RunspaceManager {
    $JobManager.IsEnabled = $False

    $Timeout = 0
    Do {
        Start-Sleep -Seconds 1
    } While (++$Timeout -lt 30 -and $JobManager.State.IsCompleted -ne $true)

    [void]$JobManager.PowerShell.EndInvoke($JobManager.State)
    $JobManager.PowerShell.Runspace.Dispose()
    $JobManager.PowerShell.Dispose()
}

Function Start-Worker {
    Param(
        [Parameter(Mandatory=$true)]
        [ScriptBlock]
        $ScriptBlock,

        [Parameter(Mandatory=$false)]
        [System.Windows.UIElement]
        $ParentControl,

        [Parameter(Mandatory=$false)]
        [string]
        $OutputControl,

        [Parameter(Mandatory=$false)]
        [PSObject]
        $Argument = $null
    )

    if ($ParentControl -ne $null) {
        $Control = $ParentControl.FindName($OutputControl)
    }

    $SyncHash = [hashtable]::Synchronized(@{Parent = $ParentControl; Output = $Control; Argument = $Argument})

    $Runspace = [runspacefactory]::CreateRunspace()
    $Runspace.ApartmentState = "STA"
    $Runspace.ThreadOptions = "ReuseThread"         
    $Runspace.Open()
    $Runspace.SessionStateProxy.SetVariable("SyncHash", $SyncHash)          
    $Worker = [PowerShell]::Create().AddScript($ScriptBlock)
    $Worker.Runspace = $Runspace

    [void]$JobList.Add((
        [pscustomobject] @{
            PowerShell = $Worker
            State = $Worker.BeginInvoke()
        }
	))
	
	Write-Output $SyncHash
}
#endregion Multithreading Management

#region Xaml Form Management
# You can design the window using Blend. Copy the .xaml file and name it what you want to include
# Removes the Visual Studio class headers and "Name x:" prefixes to make the XML compatible
$Script:PatternList = @()
$PatternList += New-Object PSObject -Property @{
	Pattern	     = 'mc:Ignorable="d"'
	ReplaceWith  = ''
}
$PatternList += New-Object PSObject -Property @{
	Pattern	     = 'x:N'
	ReplaceWith  = 'N'
}
$PatternList += New-Object PSObject -Property @{
	Pattern	     = '^<Win.*'
	ReplaceWith  = '<Window'
}
$PatternList += New-Object PSObject -Property @{
	Pattern	     = 'x:Class="[a-zA-Z_\.]*"'
	ReplaceWith  = ''
}
$PatternList += New-Object PSObject -Property @{
	Pattern	     = 'd:[a-zA-Z]*="[a-zA-Z0-9_\.]*"'
	ReplaceWith  = ''
}

Function Load-XamlFile {
    Param(
        $LayoutXaml,
		[switch]$LoadVariables,
		[Array] $PatternList = $Script:PatternList
    )

    foreach ($Pattern in $PatternList) {
        $LayoutXaml = $LayoutXaml -replace $Pattern.Pattern, $Pattern.ReplaceWith
    }
    [xml] $LayoutXml = $LayoutXaml

    # Reads XAML Nodes
    $LayoutReader = New-Object System.Xml.XmlNodeReader $LayoutXml

    # Loads Parsed XAML into a .NET Form object container
    $Layout = [Windows.Markup.XamlReader]::Load($LayoutReader)

    if ($LoadVariables) {
        $LayoutXml.SelectNodes("//*[@Name]") | foreach { Set-Variable -Name $_.Name -Scope Global -Value $Layout.FindName($_.Name) }
    }

    Write-Output $Layout
}

Function Add-LayoutForm {
    Param(
        [xml] $FormXml,
        [string] $Name,
        [ValidateSet('UserControl', 'Window')]
        [string] $Type
    )

    $FormObject = New-Object PSObject -Property @{
        XamlLayout = $FormXml
        Name = $Name
        Type = $Type
    }

    if ($Script:FormList.ContainsKey($Name)) {
        throw "Could not add form $Name to Form List, already exists."
    }

    $Script:FormList.Add($Name, $FormObject)
}

Function Show-LayoutForm {
    Param(
		[string]$Name,
		[System.Windows.UIElement] $ContainerControl = $null,
        [Hashtable] $FormList = $Script:FormList,
        [Array] $PatternList = $Script:PatternList
    )
	
	if ($FormList.ContainsKey($Name))
	{
		$ContentXaml = $FormList[$Name].XamlLayout
		
		foreach ($Pattern in $PatternList)
		{
			$ContentXaml = $ContentXaml -replace $Pattern.Pattern, $Pattern.ReplaceWith
		}
		[xml]$ContentLayout = $ContentXaml
		
		# Reads XAML Nodes
		$ContentReader = (New-Object System.Xml.XmlNodeReader $ContentLayout)
		
		# Loads Parsed XAML into a .NET Form object container
		try {
			$ControlSet = [Windows.Markup.XamlReader]::Load($ContentReader)
		} catch {
			throw "Could not parse markup: $($_.Exception.Message)"
		}
		
		if ($FormList[$Name].Type -eq 'UserControl') {
			if ($ContainerControl.Children.Count -gt 0) {
				# Remove Child layout. Replacing Content Panel
			}
		} else {
			
		}
		
		$ContainerControl.Children.Clear() | Out-Null
		$ContainerControl.Children.Add($ContentControls) | Out-Null
	}
}
#endregion Xaml Form Management

#region Dynamic Form Management
Function Import-VerificationCertificates {

    $OutputList = New-Object System.Collections.Hashtable
    $FileList = Get-ChildItem -Path '.' -Filter '*.cer'

    foreach ($File in $FileList) {
        try {
            $Certificate = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($File.FullName)
            $OutputList.Add($Certificate.Thumbprint, $Certificate)
        } catch {
            # If we had a problem, skip it. We can't use that certificate.
        }
    }

    Write-Output $OutputList
}

Function Test-FileSignature {
    Param(
        [System.Security.Cryptography.X509Certificates.X509Certificate2]
        $Certificate,

        [string]
        $FileName,

        [string]
        $Signature
    )

    [byte[]] $Signature = [System.Convert]::FromBase64String($Signature)

    if (Test-Path $FileName) {
        $Data = Get-Content $FileName
    } else {
        throw "Invalid filename specified"
    }

    [System.Security.Cryptography.RSACryptoServiceProvider] $CryptoProvider = $Certificate.PublicKey.Key
    
    if ($CryptoProvider -eq $null) {
        throw "Cannot generate file signature without a private key"
    }

    $Sha1 = New-Object System.Security.Cryptography.SHA1Managed
    $ByteStream = [System.Text.Encoding]::UTF8.GetBytes($Data)
    $Hash = $Sha1.ComputeHash($ByteStream)
    
    Write-Output ($CryptoProvider.VerifyHash($Hash, [System.Security.Cryptography.CryptoConfig]::MapNameToOID("SHA1"), $Signature))
}

Function Request-OSDFrontEndFile {
    <#
        .SYNOPSIS
            Request-OSDFrontEndFile retrieves a file from a remote source and downloads it locally.
        .DESCRIPTION
            Request-OSDFrontEndFile is used by the OSD Front End to fetch remote files from a web server
            and download them locally. This is intended to provide dynamic features to the OSD Front End
            that can add content panels or additional code to the front end.
        .PARAMETER URL
            The URL of the remote site (absent the file name itself) to download.
        .PARAMETER FileName
            The FileName parameter accepts the name of the remote file to download. It is also used
            as the name of the file to download locally.
        .EXAMPLE
            Request-OSDFrontEndFile -Url http://www.example.com/OSDFrontEnd -FileName Manifest.xml

            This example contacts the web server at www.example.com and downloads the file Manifest.xml
            in the folder /OSDFrontEnd/. It will save this file locally in the current location where
            the commandlet is run from.
    #>
    Param(
        [string]
        $URL,

        [string]
        $FileName,

        [switch]
        $TestMode
    )

    $FullUri = ("{0}/{1}" -f $URL, $FileName)

    try {
        if ($TestMode -eq $true) {
            Write-Host "Copying $FileName from test location $(Join-Path (Get-Location) "Server Files")."
            Copy-Item "Server Files\$FileName" "$FileName" -Force
        } else {
            Write-Host "Trying to retrieve $FileName at $FullUri"
            $Response = Invoke-WebRequest -Uri $FullUri -Method Get -OutFile "$FileName"
        }

        Write-Output $true
    } catch {
        Write-Output $false
    }
}
#endregion Dynamic Form Management

Function Check-PowerStatus {
    if (Get-WmiObject -Namespace "root\cimv2" -Class Win32_SystemEnclosure | Where-Object {($_.ChassisTypes -eq 9) -or ($_.ChassisTypes -eq 10) -or ($_.ChassisTypes -eq 14)}) {
        $isLaptop = $true
    } else {
        $isWorkstation = $true
    }

    if ($isLaptop -eq $true) {
        $BatteryStatus = Get-WmiObject -Namespace "root\WMI" -Class BatteryStatus | Select-Object -ExpandProperty PowerOnline
        if ($BatteryStatus -eq $true) {
            return $true
        } else {
            return $false
        }
    }
    if ($isWorkstation -eq $true) {
        return $true
    }
}

Function Test-Port {
<#
.Synopsis
   Test-Port allows you to test if a port is accessible
.Description
   Using Test-Port you can find if a specified port is open on a machine.  The results are the original servername, Ipaddress, Port and if successful
.Parameter Server
   The server parameter is the name of the machine you want to test, either FQDN or NetBIOS name
.Parameter Port
   Use Port Parameter to specify the port to test
.Parameter TimeOut
   Use Timeout value to specify how long to wait for connection in milliseconds
.Example
   Test-Port -Server www.google.com -Port 80
#>
	Param (
		[Parameter(Mandatory = $true)]
		[String]$Server,
		[Parameter(Mandatory = $true)]
		[Int]$Port,
		[Parameter(Mandatory = $False)]
		[Int]$Timeout = 3000
	)
	
	$IP = [net.dns]::Resolve($server).addresslist[0].ipaddresstostring
	
	if ($IP) {
		[void] ($socket = New-Object net.sockets.tcpclient)
		$Connection = $socket.BeginConnect($server, $Port, $null, $null)
		[void] ($Connection.AsyncWaitHandle.WaitOne($TimeOut, $False))
		
		#
		#[void] ($socket.connect($server,$port))
		$hash = @{
			Server		    = $Server
			IPAddress	    = $IP
			Port		    = $Port
			Successful	    = ($socket.connected)
		}
		
		$socket.Close()
		
	} else {
		$hash = @{
			Server	   = $server
			IPAddress  = $null
			Port	   = $Port
			Successful = $null
		}
	}
	
	return (new-object PSObject -Property $hash) | select Server, IPAddress, Port, Successful
}

Function Test-Ping {
<#
.Synopsis
    Powershell Version of Ping
.Description
    This is meant to be used as an alternative to the ping option in an object result
.Parameter Server
    Specify the server or IP address
.Parameter Count
    Specify how many times it should ping (defautl is 1)
.Example
    Test-Ping -Server dc1-w-admindc1p -count 5
#>
	Param (
		[Parameter(Mandatory = $true)]
		[String]$Server,
		[Parameter(Mandatory = $false)]
		[Int]$Count = 4,
		[Parameter(Mandatory = $false)]
		[Switch]$Continuous = $false
	)
	
	$result = @()
	try	{
		$h = [net.dns]::GetHostEntry($Server)
		
		$array = @()
		$obj = New-Object PSObject
		
		While ($Count) {
			$obj = ((New-Object System.Net.NetworkInformation.Ping).Send($h.AddressList.IPAddressToString) | Select @{ N = 'HostName'; E = { $h.HostName } }, Address, Status, RoundTripTime, @{ N = 'TTL'; E = { $_.options.TTL } }, @{ N = 'Buffer'; E = { $_.Buffer.Count } })
			$obj
			
			$array += $obj
			if (!$Continuous) {
				$count -= 1
			}
		}
		
		#return $array
	} Catch [Net.Sockets.SocketException] {
		"Unable to resolve host."
	} Catch {
		Write-Host "Unknown Error." -ForegroundColor Red
	}
}

Function Check-NetworkConnectivity {
    Param(
        [string] $Url
    )

    try {
		$Uri = [System.Uri]$Url
		
		$Uri.DnsSafeHost
    } catch {
        
    }
}

Function New-DisplayPanelEntry {
    Param(
        [string] $Label,
        [string] $Value,
        [string] $Description = ""
    )
    New-Variable -Scope Script -Name "$($Label)Label" -Value (New-Object System.Windows.Controls.Label)
    $LabelField = Get-Variable -Scope Script -Name "$($Label)Label" -ValueOnly
    
    $LabelField.Name = "$($Label)Label"
    $LabelField.Content = $(if ([string]::IsNullOrEmpty($Description)) { "$Label" } else { "$Description" })
    $LabelField.Margin = "0,2,10,0"
    $LabelField.Foreground = "Gold"
    $LabelField.VerticalAlignment = "Top"
    $LabelField.FontSize = "14.667"

    New-Variable -Scope Script -Name "$Label" -Value (New-Object System.Windows.Controls.TextBox)
    $ValueField = Get-Variable -Scope Script -Name "$Label" -ValueOnly

    $ValueField.Text = $Value
    $ValueField.Margin = "10,-5,10,0" 
    $ValueField.Background = "Transparent" 
    $ValueField.BorderThickness = "0"  
    $ValueField.Foreground = "LightGray" 
    $ValueField.VerticalAlignment = "Top" 
    $ValueField.FontSize = "12" 
    $ValueField.TextWrapping = "Wrap"

    # Add at the tail of the System Info Panel
    [void] $SystemInfoGroup.Content.Children.Add($LabelField)
    [void] $SystemInfoGroup.Content.Children.Add($ValueField)
}

Function Initialize-DisplayPanels {

    ##########
    #
    # System Info Panel
    #
    ##########

    # Set default options for laptops
    if ((gwmi -Class Win32_ComputerSystem).PCSystemType -eq 2) {
    #    $BitLockerCheckBox.IsChecked = $true
    #    $BIOSCheckBox.IsChecked = $true
    #    $VPNCheckBox.IsChecked = $true
    }

    # Fills in system information from WMI
    $Manufacturer.Text = (Get-WmiObject Win32_ComputerSystem).Manufacturer
    $ModelNumber.Text = (gwmi -Class Win32_ComputerSystem).Model
    $SerialNumber.Text = (gwmi -Class Win32_BIOS).SerialNumber
    $RAMInstalled.Text = ([math]::Round((gwmi -Class Win32_ComputerSystem).TotalPhysicalMemory / (1024 * 1024 * 1024))).ToString() + " GB (" + ([math]::Round(((gwmi -Class Win32_ComputerSystem).TotalPhysicalMemory / (1024 * 1024 * 1024)),2)).ToString() + " GB avail.)"

    $NetworkAdapter = ([array] (get-ciminstance win32_networkadapter -property Name,MacAddress,AdapterType| where adaptertype -eq "Ethernet 802.3"))[0]
    $NICAdapter.Text = $NetworkAdapter.Name
    $MACAddress.Text = $NetworkAdapter.MacAddress
    $IPAddress.Text = (get-ciminstance win32_networkadapterconfiguration -property ipaddress | where ipaddress -ne $null).ipaddress[0]

    if (Check-PowerStatus) {
        $PowerState.Text = "On AC Power"
    } else {
        $PowerState.Text = "On Battery Power"
    }
}
