Function Initialize-AdvancedUtilities
{
    # Tools: Advanced: Command Prompt
    $CommandButton.Add_Click(
        {
            $ButtonStack.IsEnabled = $false
        
            foreach ($Radio in $StackSelector.Children) {
                if ($Radio.IsChecked) {
                    $Script:PrevButton = $Radio.Name
                }
            }

            $CmdPassword.Password = [string]::Empty
            $CmdAuthButton.Tag = "System32\cmd.exe"
            $CmdAuthButton.IsChecked = $true

            # Set focus: https://msdn.microsoft.com/en-us/library/system.windows.input.focusmanager.setfocusedelement.aspx
            [System.Windows.Input.FocusManager]::SetFocusedElement($Form, $CmdPassword)
        }
    )

    # Tools: Advanced: PowerShell 
    $PowerShellButton.Add_Click(
        {
            $ButtonStack.IsEnabled = $false
        
            foreach ($Radio in $StackSelector.Children) {
                if ($Radio.IsChecked) {
                    $Script:PrevButton = $Radio.Name
                }
            }

            $CmdPassword.Password = [string]::Empty
            $CmdAuthButton.Tag = "System32\WindowsPowerShell\v1.0\PowerShell.exe"
            $CmdAuthButton.IsChecked = $true

            # Set focus: https://msdn.microsoft.com/en-us/library/system.windows.input.focusmanager.setfocusedelement.aspx
            [System.Windows.Input.FocusManager]::SetFocusedElement($Form, $CmdPassword)
        }
    )

    $NotepadButton.Add_Click(
        {
            Start-Process (Join-Path $env:SystemDrive "\Program Files\Notepad++\Notepad++.exe")
        }
    )

    $CmTraceButton.Add_Click(
        {
            Start-Process (Join-Path $env:SystemDrive "\sms\bin\x64\cmtrace.exe")
        }
    )
}

Initialize-AdvancedUtilities