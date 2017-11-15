$PingHostScriptBlock = {
    # Required to use XAML GUI components
    [void][System.Reflection.Assembly]::LoadWithPartialName('presentationframework')

    Function Resolve-Host {
        Param(
            [Parameter(Mandatory=$true)][string]$Hostname
        )
        $Output = New-Object PSObject -Property @{
            HostName = $Hostname
            IPAddress = [string]::Empty
            IsResolved = $false
            IsIPAddress = $false
        }

        if ([ipaddress]::TryParse($Hostname, [ref] $null)) {
            $Output.IsIPAddress = $true
            $Output.IPAddress = $Hostname
        } else {
            $h = [net.dns]::GetHostEntry($Hostname)
            $Output.HostName = $h.HostName
            $Output.IPAddress = $h.AddressList.IPAddressToString
            $Output.IsResolved = $true
        }

        Write-Output $Output
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
        Specify how many times it should ping (default is 4)
    .Example
        Test-Ping -Server dc1-w-admindc1p -count 5
    #>
        Param(
            [Parameter(Mandatory=$true)][String]$Server,
            [Parameter(Mandatory=$false)][Int]$Count=4,
            [Parameter(Mandatory=$false)][Switch]$Continuous=$false
        )

        try
        {
            $HostData = Resolve-Host -Hostname $Server
            $PingOpts = New-Object System.Net.NetworkInformation.PingOptions
        
            $Reply = New-Object PSObject

            While ($Count -gt 0)
            {
                $Reply = ((New-Object System.Net.NetworkInformation.Ping).Send($HostData.IPAddress) | Select @{N='HostName'; E={$HostName}},Address,Status,RoundTripTime,@{N='TTL';E={if ($_.Options -ne $null) {$_.options.TTL} else {$PingOpts.Ttl}}},@{N='Buffer';E={$_.Buffer.Count}})

                Write-Output $Reply

                if (-not $Continuous)
                {
                    $count -= 1
                }
                
                if ($Count -gt 0) {
                    Start-Sleep 1
                }
            }
        }
        Catch [Net.Sockets.SocketException]
        {
            throw "Ping request could not find host $Server. Please check the name and try again."
        }
        Catch
        {
            throw "Unknown error trying to ping $Server"
        }
    }
    
    $Statistics = New-Object PSObject -Property @{
        Sent = 0
        Received = 0
        RoundTripMin = 99999
        RoundTripMax = 0
        RoundTripAvg = 0
    }

    # Header Information
    try {
        $HostData = Resolve-Host -Hostname $SyncHash.Argument
    } catch {
        $HostData = $null
        $SyncHash.Parent.Dispatcher.Invoke([action]{$SyncHash.Output.Text += "Problems resolving host $($SyncHash.Argument): $($_.Exception.Message)`n`n"})
    }

    if ($HostData -ne $null) {

        if ($HostData.IsIPAddress) {
            $PingHeader = $HostData.IPAddress
        } elseif ($HostData.IsResolved) {
            $PingHeader = ("{0} [{1}]" -f $HostData.HostName, $HostData.IPAddress)
        } else {
            $SyncHash.Parent.Dispatcher.Invoke([action]{$SyncHash.Output.Text = "Unable to ping $($SyncHash.Argument), unresolvable.`n`n"})
            return
        }

        $SyncHash.Parent.Dispatcher.Invoke([action]{$SyncHash.Output.Text += "Pinging $PingHeader with 32 bytes of data:`n`n"})

        # Ping it, let's see if we can reach our target
        for ($Progress = 0; $Progress -lt 4; $Progress++) {
            if ($Progress -ne 0) {
                Start-Sleep 1
            }

            $Output = Test-Ping -Server $SyncHash.Argument -Count 1

            $Statistics.Sent += 1

            switch ($Output.Status) {
                'Success' {
                    $Statistics.RoundTripMin = [math]::Min($Statistics.RoundTripMin, $Output.RoundtripTime)
                    $Statistics.RoundTripMax = [math]::Max($Statistics.RoundTripMax, $Output.RoundtripTime)

                    $Statistics.RoundTripAvg = ($Statistics.RoundTripAvg * $Statistics.Received + $Output.RoundtripTime) / ($Statistics.Received + 1)
                    $Statistics.Received += 1
                    $Message = "Reply from $($Output.Address): bytes=$($Output.Buffer) time=$($Output.RoundTripTime)ms TTL=$($Output.TTL)"
                }
                'TimedOut' {
                    $Message = "Request timed out."
                }
                default {
                    $Message = $Output.Status
                }
            }

            $SyncHash.Parent.Dispatcher.Invoke([action]{$SyncHash.Output.Text += ("{0}`n" -f $Message)})
        }

        # Summarize so they know we're done.
        $Summary = @"

Ping statistics for $($HostData.IPAddress):
    Packets: Sent = $($Statistics.Sent), Received = $($Statistics.Received), Lost = $($Statistics.Sent - $Statistics.Received) ($([math]::Round(($Statistics.Sent - $Statistics.Received) / $Statistics.Sent * 100))% loss),
Approximate round trip times in milli-seconds:
    Minimum = $($Statistics.RoundTripMin)ms, Maximum = $($Statistics.RoundTripMax)ms, Average = $($Statistics.RoundTripAvg)ms
"@

        $SyncHash.Parent.Dispatcher.Invoke([action]{$SyncHash.Output.Text += $Summary})
    }

    Exit
}

Function Invoke-PingHost {
    $NetworkDetailsOutput.Text = [string]::Empty

    try {
        Start-Worker -ScriptBlock $PingHostScriptBlock -ParentControl $ContentGrid.Children[0] -OutputControl 'NetworkDetailsOutput' -Argument $HostToPing.Text   
    } catch {
        $NetworkDetailsOutput.Text = $_.Exception.Message
    }
}


Function Initialize-NetworkUtilities {
    # Tools: Network: Ping

    # http://stackoverflow.com/questions/39808166/add-enter-and-escape-key-presses-to-powershell-wpf-form
    $HostToPing.Add_KeyDown(
        {
            Param(
                [Parameter(Mandatory)][Object]$sender,
                [Parameter(Mandatory)][Windows.Input.KeyEventArgs]$e
            )

            if($e.Key -eq 'Enter') {
                Invoke-PingHost
            }        
        }
    )

    $PingHostButton.Add_Click(
        {
            Invoke-PingHost
        }
    )
}

Initialize-NetworkUtilities