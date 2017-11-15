Function Initialize-DiskUtilities {
    $Script:DeviceDriveList = (@() + (Get-Disk))
    $DiskListView.ItemsSource = $Script:DeviceDriveList

    # http://www.thomasmaurer.ch/2012/04/replace-diskpart-with-windows-powershell-basic-storage-cmdlets/

    # Tools: Disk: Inspect Disk
    $InspectDiskButton.Add_Click(
        {
            $InspectLineTemplate = "{0,-9} {1,-11} {2,10} {3,-15}`n"

            if ($DiskListView.SelectedItems.Count -gt 0) {
                $DiskDetailsOutput.Text = [string]::Empty

                foreach ($Disk in $DiskListView.SelectedItems) {
                    $PartitionList = $Disk | Get-Partition

                    $DiskDetailsOutput.Text = ("Inspecting disk {0}`n`n" -f $Disk.Number)

                    $DiskDetailsOutput.Text += ($InspectLineTemplate -f 'Partition', 'DriveLetter', 'Size', 'Type')
                    $DiskDetailsOutput.Text += ($InspectLineTemplate -f [string]::Empty.PadLeft(9,"-"), [string]::Empty.PadLeft(11,"-"), [string]::Empty.PadLeft(10,"-"), [string]::Empty.PadLeft(15,"-"))
                    foreach ($Partition in $PartitionList) {
                        if ($Partition.Size -gt 1TB) {
                            $SizeDiv = 1TB
                            $SizeName = 'TB'
                        } elseif ($Partition.Size -gt 1GB) {
                            $SizeDiv = 1GB
                            $SizeName = 'GB'
                        } else {
                            $SizeDiv = 1MB
                            $SizeName = 'MB'
                        }
                        $Size = ("{0:n2} {1}" -f ($Partition.Size / $SizeDiv), $SizeName)
                        
                        $DriveLetter = $Partition.DriveLetter
                        if ($DriveLetter -eq [char]0) {
                            $DriveLetter = [string]::Empty
                        }

                        $DiskDetailsOutput.Text += ($InspectLineTemplate -f $Partition.PartitionNumber, $DriveLetter, $Size, $Partition.Type)
                    }
                }
            } else {
                $DiskDetailsOutput.Text = 'Please select a disk from the list above to inspect.'
            }
        }
    )

    # Tools: Disk: Clean Disk
    $CleanDiskButton.Add_Click(
        {
            $WhatIf = @{}

            if ($TSEnv -eq $null) {
                $WhatIf = @{WhatIf = $True}
            }

            if ($DiskListView.SelectedItems.Count -gt 0) {
                $DiskDetailsOutput.Text = [string]::Empty

                foreach ($Disk in $DiskListView.SelectedItems) {

                    try {
#                         $DiskDetailsOutput.Text += "Pre-Clear Check - ConfirmPref is $ConfirmPreference.`n`n"

                        Clear-Disk -Number $Disk.Number -RemoveData -RemoveOEM @WhatIf -Confirm:$False -ErrorAction Stop

                        $DiskDetailsOutput.Text += "Disk $($Disk.Number) cleaned.`n"
                    } catch {
                        $DiskDetailsOutput.Text += "Error while attempting to clear disk $($Disk.Number). Reason:`n"
                        $DiskDetailsOutput.Text += ("{0}`n`n" -f $_.Exception.Message)
                    } finally {
                    }
                }
            } else {
                $DiskDetailsOutput.Text = 'Please select a disk from the list above to clean.'
            }
        }
    )

    # Tools: Disk: Check Disk
    $CheckDiskButton.Add_Click(
        {
            if ($DiskListView.SelectedItems.Count -gt 0) {
                $DiskDetailsOutput.Text = [string]::Empty

                foreach ($Disk in $DiskListView.SelectedItems) {
                    $DiskDetailsOutput.Text += "Check disk operation on $($Disk)`n"
                }
            } else {
                $DiskDetailsOutput.Text = 'Please select a disk from the list above to check.'
            }
        }
    )

    # Tools: Launch Explorer
    $ExplorerButton.Add_Click(
        {
            if ($TSEnv -eq $null) {
                $Explorer = "\Explorer.exe"
            } else {
                $Explorer = "\System32\Explorer.exe"
            }

            Start-Process (Join-Path $Env:SystemRoot $Explorer)
        }
    )
}

Initialize-DiskUtilities