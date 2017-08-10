<# 
.SYNOPSIS 
    Quick control commands for local VMware VMs 
 
.DESCRIPTION 
    Uses the VMrun.exe executible from VMWare Workstation to perform quick management of local VMs 
    for example sending multiple poweron/poweroff commands to multiple VMs at once 
 
.OUTPUTS 
    .NET GUI Managment dialog 
 
.EXAMPLE 
    .\VMrun.ps1 
    # Locates VMrun.exe and Workstation config file (${env:ProgramData}\VMware\hostd\config.xml) and  
    # ($env:APPDATA\VMware\inventory.vmls) to control local VM inventory. No Parameters required 
 
.NOTES 
    Created by Sadik Tekin 
    Gek-Tek Solutions Ltd 
    Requires VMware Workstation (http://www.vmware.com/products/workstation.html). 
#> 
 
 
# Check if run as Administrator 
#if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) { 
#    (new-object -ComObject wscript.shell).Popup("Please re-run as Administrator",0,"RunAs Admin") 
#    Break 
#} 
 
#net start vmx86 # On rare occasions may need to start this service after boot 


 
# Find VMware Workstation install directory 
$xml = [xml](Get-Content "${env:ProgramData}\VMware\hostd\config.xml") 
if ($xml -eq $null) { 
    (new-object -ComObject wscript.shell).Popup("Can't load Workstation config file:`n${env:ProgramData}\VMware\hostd\config.xml",0,"File not Found") 
    Break 
} else {  
    $WP = $xml.config.defaultInstallPath 
    $WorkstationPath = $WP.Trim() 
}
 
# Locate VMRun.exe
$vmRun = $WorkstationPath + "vmrun.exe" 
if (-NOT (Test-Path $vmRun)) { 
    #throw [System.IO.FileNotFoundException] "$vmRun Needed" 
    (new-object -ComObject wscript.shell).Popup("Could not locate $vmRun",0,"File not Found") 
    Break 
} else {
    # If found create vmrun common alias
    set-alias vmrun $vmRun 
}
      
 
# Check if user profile settings exist 
$vmlsFile = "$env:APPDATA\VMware\inventory.vmls" 
if (!(Test-Path -path $vmlsFile)) { 
    #throw [System.IO.FileNotFoundException] "$vmlsFile Not Found" 
    (new-object -ComObject wscript.shell).Popup("Could not locate $vmlsFile",0,"File not Found") 
    Break 
} else {
    # Store content of VMware Workstation (Roaming) preferences into String 
    $Config = Get-Content $vmlsFile | Select-String -Pattern 'index[0-99]\.id'
}

# Get all VMs on disk and build table
$i = 0
$script:VMList = $config | % {
    New-Object psObject -Property ([ordered]@{
        'ID' = $i
        'VM'= ($_ -split '([^\\]+$)' -replace '.vmx"','')[1]
        'State' = 'Off'
        'Snapshots' = 'None'
        'Path' = ($_ -split ' = ')[1].Replace("`"","")
    }); 
    $i ++
}    
     
 
# Create the session logging feature 
Function Out2Log { 
    [CmdletBinding()] 
    Param( 
    [Parameter(Mandatory=$True)] 
    [string]$l_string, 
    [Parameter(Mandatory=$True)] 
    [int]$l_severity 
    ) 
     
    # Message levels 
    $l_levels = @{0="[Alert] "; 1="[Info] "} 
 
    $DT = Get-Date -UFormat "%Y%m%d" 
    $l_fname = "VMrun-" + $DT + ".log" 
    $entryTime = (Get-Date).ToUniversalTime().ToString("HH:mm:ss.fff")
 
    # Log to GUI Logbox 
        $entryTime + " GMT`t" + ` 
        $l_levels.Get_Item($l_severity) + ` 
        $l_string | ForEach-Object {[void] $objLogBox.Items.Add($_)} 
        # Autoscroll Listbox 
        $objLogBox.SelectedIndex = $objLogBox.Items.Count - 1; 
        $objLogBox.SelectedIndex = -1; 
 
        <# Autoscroll textbox: 
        $objLogBox.SelectionStart = $objLogBox.Text.Length; 
        $objLogBox.ScrollToCaret(); 
        #> 
} 



##########################################
###### Build GUI
########################################## 
$x = @() 
[void] [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") 
[void] [System.Reflection.Assembly]::LoadWithPartialName("System.Drawing") 
 
$form = New-Object System.Windows.Forms.Form 
$form.Text = "VMrun GUI" 
$form.Size = New-Object System.Drawing.Size(700,500)
$form.MinimumSize = New-Object System.Drawing.Size(700,500) 
$form.StartPosition = "CenterScreen" 
try { 
    $icon = [system.drawing.icon]::ExtractAssociatedIcon("$WorkstationPath\vmware.exe") 
    $form.Icon = $icon 
} catch { 
    Out2Log ("Error retrieving app icon: " + $_) -l_severity 0    
} 
$form.KeyPreview = $True 
$form.Add_KeyDown({ 
    if ($_.KeyCode -eq "Enter") { 
        foreach ($objItem in $objGridBox.SelectedItems) { 
            $x += $objItem 
            $objItem | ForEach-Object { $VMselection = $VMPaths -match "$_"; Start-VM } 
        } 
    } 
})
$form.Add_KeyDown({
    if ($_.KeyCode -eq "Escape") {
        $form.Close()
    }
}) 
 
$tooltip = New-Object System.Windows.Forms.ToolTip
$ShowHelp={ 
    #display popup help 
    #each value is the name of a control on the form.  
     Switch ($this.name) { 
        "StartVM" {$tip = "Start Multiple VMs"} 
        "StartAll" {$tip = "Start All VMs"} 
        "StopVM" {$tip = "Stop Multiple VMs"} 
        "SuspendVM" {$tip = "Suspend Multiple VMs"} 
        "SuspendAll" {$tip = "Suspend All VMs"} 
        "ResetVM" {$tip = "Perform Soft Reset on Multiple VMs"}
        "ResetAll" {$tip = "Perform Soft Reset on All VMs"} 
        "CreateSnapshot" {$tip = "Create a Snapshot of Selected VMs"}
        "DeleteSnapshot" {$tip = "Delete a Snapshot of Selected VMs"}
        "RevertSnapshot" {$tip = "Revert to a Snapshot on Selected VMs"}
        "PuttyButton"  {$tip = "Launch Putty to the selected VM"}
        "RDPButton" {$tip = "Launch RDP to the selected VM"} 
        "NetConfigButton" {$tip = "Launch Network Config Editor"}
      } 
     $tooltip.SetToolTip($this,$tip) 
} #end ShowHelp 

# create and add start button
$StartButton = New-Object System.Windows.Forms.Button  
$StartButton.Size = New-Object System.Drawing.Size(75,23)
$StartButton.Top = 5
$StartButton.Left = 5
$StartButton.Text = "Start" 
$StartButton.Name = "StartVM" 
$StartButton.add_MouseHover($ShowHelp)
$StartButton.Add_Click({ 
    # Capture list of running VMs to an Array - skip the 1st entry 
    Out2Log "Getting currently running VMs..." -l_severity 1
    $RunningVMs = & vmrun list | select -skip 1; 
    
    # compare to running vms, then call vmrun to start appropriate vms
    $objGridBox.SelectedRows | % {
        $vmPath = $_.Cells[4].Value.ToString()
        $vmName = $_.Cells[1].Value.ToString()
        if(!($RunningVMs -contains $vmPath)) {
            Out2Log "Starting $vmName at Path - $vmPath" -l_severity 1
            # execute VMrun expression to start VM 
            try { vmrun -T ws start $vmPath nogui; Out2Log "Complete: Started $vmName" -l_severity 1} 
            # Catch any errors into log 
            catch { Out2Log ("Failed to Start VM $vmName, returned - " + $_) -l_severity 0 }  
        } else {
            Out2Log "Failed: $vmName is already running" -l_severity 1
        }  
    }
    Out2Log "Command Complete: Start" -l_severity 1 
}) 
 

 
$StartAllButton = New-Object System.Windows.Forms.Button 
$StartAllButton.Size = New-Object System.Drawing.Size(75,23)
$StartAllButton.Top = 30
$StartAllButton.Left = 5
$StartAllButton.Text = "Start All" 
$StartAllButton.Name = "StartAll" 
$StartAllButton.add_MouseHover($ShowHelp) 
$StartAllButton.Add_Click({ 
    $Confrim = [System.Windows.Forms.MessageBox]::Show("Start/Resume all VMs?" , "Start ALL" , 4) 
    if ($Confrim -eq "YES" ) { 
        Out2Log "Getting currently running VMs..." -l_severity 1
        $RunningVMs = & vmrun list | select -skip 1; 
        
        # compare to running vms, then call vmrun to start appropriate vms 
        $objGridBox.Rows | % {
            $vmPath = $_.Cells[4].Value.ToString()
            $vmName = $_.Cells[1].Value.ToString()
            if(!($RunningVMs -contains $vmPath)) {
                Out2Log "Starting $vmName at Path - $vmPath" -l_severity 1
                # execute VMrun expression to start VM 
                try { vmrun -T ws start $vmPath nogui; Out2Log "Complete: Started $vmName" -l_severity 1} 
                # Catch any errors into log 
                catch { Out2Log ("Failed to Start VM $vmName, returned - " + $_) -l_severity 0 }  
            } else {
                Out2Log "Failed: $vmName is already running" -l_severity 1
            }  
        }
        Out2Log "Finished Command: Start All" -l_severity 1 
    } 
}) 
 
 
$SuspendButton = New-Object System.Windows.Forms.Button 
$SuspendButton.Size = New-Object System.Drawing.Size(75,23)
$SuspendButton.Top = 5
$SuspendButton.Left = 85 
$SuspendButton.Text = "Suspend" 
$SuspendButton.Name = "SuspendVM" 
$SuspendButton.add_MouseHover($ShowHelp) 
$SuspendButton.Add_Click({
    # call vmrun to suspend appropriate vms
    $objGridBox.SelectedRows | % {
        $vmPath = $_.Cells[4].Value.ToString()
        $vmName = $_.Cells[1].Value.ToString()
        Out2Log "Suspending $vmName at path - $vmPath" -l_severity 1 
        # execute VMrun expression to start VM 
        try { vmrun -T ws suspend $vmPath nogui; Out2Log "Complete: Suspended $vmName" -l_severity 1} 
        # Catch any errors into log 
        catch { Out2Log ("Failed: Suspend $vmName returned: " + $_) -l_severity 0 }  
    }
    Out2Log "Finished Command: Suspend" -l_severity 1
}) 
 
 
$SuspendAllButton = New-Object System.Windows.Forms.Button 
$SuspendAllButton.Size = New-Object System.Drawing.Size(75,23)
$SuspendAllButton.Top = 30
$SuspendAllButton.Left = 85
$SuspendAllButton.Text = "Suspend All" 
$SuspendAllButton.Name = "SuspendAll" 
$SuspendAllButton.add_MouseHover($ShowHelp) 
$SuspendAllButton.Add_Click({
    # call vmrun to suspend appropriate vms
    $objGridBox.Rows | % {
        $vmPath = $_.Cells[4].Value.ToString()
        $vmName = $_.Cells[1].Value.ToString()
        Out2Log "Suspending $vmName at path - $vmPath" -l_severity 1 
        # execute VMrun expression to start VM 
        try { vmrun -T ws suspend $vmPath nogui; Out2Log "Complete: Suspended $vmName" -l_severity 1} 
        # Catch any errors into log 
        catch { Out2Log ("Failed: Suspend $vmName returned: " + $_) -l_severity 0 }  
    }
    Out2Log "Finished Command: Suspend All" -l_severity 1
}) 
 
#make the Stop Button
$StopButton = New-Object System.Windows.Forms.Button  
$StopButton.Size = New-Object System.Drawing.Size(75,23)
$StopButton.Top = 5
$StopButton.Left = 165
$StopButton.Text = "Stop" 
$StopButton.Name = "StopVM" 
$StopButton.add_MouseHover($ShowHelp) 
$StopButton.Add_Click({  
    $objGridBox.SelectedRows | % {
        $vmPath = $_.Cells[4].Value.ToString()
        $vmName = $_.Cells[1].Value.ToString()
        Out2Log "Stoping $vmName at path - $vmPath" -l_severity 1 
        # execute VMrun expression to start VM 
        try { vmrun -T ws stop $vmPath nogui; Out2Log "Complete: Stop $vmName" -l_severity 1} 
        # Catch any errors into log 
        catch { Out2Log ("Failed: Stop $vmName returned: " + $_) -l_severity 0 }  
    }
    Out2Log "Finished Command: Stop" -l_severity 1 
}) 

#make the Stop All Button
$StopAllButton = New-Object System.Windows.Forms.Button  
$StopAllButton.Size = New-Object System.Drawing.Size(75,23)
$StopAllButton.Top = 30
$StopAllButton.Left = 165
$StopAllButton.Text = "Stop" 
$StopAllButton.Name = "StopVM" 
$StopAllButton.add_MouseHover($ShowHelp) 
$StopAllButton.Add_Click({ 
        $objGridBox.Rows | % {
        $vmPath = $_.Cells[4].Value.ToString()
        $vmName = $_.Cells[1].Value.ToString()
        Out2Log "Stoping $vmName at path - $vmPath" -l_severity 1 
        # execute VMrun expression to start VM 
        try { vmrun -T ws stop $vmPath nogui; Out2Log "Complete: Stop $vmName" -l_severity 1} 
        # Catch any errors into log 
        catch { Out2Log ("Failed: Stop $vmName returned: " + $_) -l_severity 0 }  
    }
    Out2Log "Finished Command: Stop All" -l_severity 1
}) 

#make reset button
$ResetButton = New-Object System.Windows.Forms.Button  
$ResetButton.Size = New-Object System.Drawing.Size(75,23)
$ResetButton.Top = 5
$ResetButton.Left = 245
$ResetButton.Text = "Reset" 
$ResetButton.Name = "ResetVM" 
$ResetButton.add_MouseHover($ShowHelp) 
$ResetButton.Add_Click({ 
        $objGridBox.SelectedRows | % {
        $vmPath = $_.Cells[4].Value.ToString()
        $vmName = $_.Cells[1].Value.ToString()
        Out2Log "Resetting $vmName at path - $vmPath" -l_severity 1 
        # execute VMrun expression to start VM 
        try { vmrun -T ws reset $vmPath nogui; Out2Log "Complete: Reset $vmName" -l_severity 1} 
        # Catch any errors into log 
        catch { Out2Log ("Failed: Reset $vmName returned: " + $_) -l_severity 0 }  
    }
    Out2Log "Finished Command: Reset VM" -l_severity 1
})

# make reset all button
$ResetAllButton = New-Object System.Windows.Forms.Button  
$ResetAllButton.Size = New-Object System.Drawing.Size(75,23)
$ResetAllButton.Top = 30
$ResetAllButton.Left = 245
$ResetAllButton.Text = "Reset All" 
$ResetAllButton.Name = "ResetAllVM" 
$ResetAllButton.add_MouseHover($ShowHelp) 
$ResetAllButton.Add_Click({ 
        $objGridBox.Rows | % {
        $vmPath = $_.Cells[4].Value.ToString()
        $vmName = $_.Cells[1].Value.ToString()
        Out2Log "Resetting $vmName at path - $vmPath" -l_severity 1 
        # execute VMrun expression to start VM 
        try { vmrun -T ws reset $vmPath nogui; Out2Log "Complete: Reset $vmName" -l_severity 1} 
        # Catch any errors into log 
        catch { Out2Log ("Failed: Reset $vmName returned: " + $_) -l_severity 0 }  
    }
    Out2Log "Finished Command: Reset All" -l_severity 1
}) 

$RefreshListButton = New-Object System.Windows.Forms.Button  
$RefreshListButton.Size = New-Object System.Drawing.Size(75,23)
$RefreshListButton.Top = 30
$RefreshListButton.Left = 245
$RefreshListButton.Text = "Refresh List" 
$RefreshListButton.Name = "RefreshList" 
$RefreshListButton.add_MouseHover($ShowHelp) 
$RefreshListButton.Add_Click({ 
    Out2Log "Updating VM State..." -l_severity 1
    # Detect running VMs
    $runningVMs = & $vmrun list | select -skip 1;
    $script:VMList | % {
        if($runningVMs -and ($runningVMs -contains $_.Path)){
            $_.State = 'On';
        }else{
            $_.State = 'Off';
        }
    }
    
    Out2Log "Updating VM Snapshots..." -l_severity 1
    #Update-Snapshots
    #Consume VMList and update the snapshot field
	#$script:VMList | % {$_.Snapshots = ((& $vmrun listsnapshots $($_.Path))| select -skip 1)}
    
    $objGridBox.Refresh()
    Out2Log "Refresh Complete" -l_severity 1
}) 


# make Create snapshot button 
$CreateSnapshotButton = New-Object System.Windows.Forms.Button  
$CreateSnapshotButton.Size = New-Object System.Drawing.Size(75,23)
$CreateSnapshotButton.Top = 5
$CreateSnapshotButton.Left = 5
$CreateSnapshotButton.Text = "Create Snap" 
$CreateSnapshotButton.Name = "CreateSnapshot" 
$CreateSnapshotButton.add_MouseHover($ShowHelp) 
$CreateSnapshotButton.Add_Click({ 
    $Confrim = [System.Windows.Forms.MessageBox]::Show("Are you sure you want to Snaphot the selected VMs?" , "Create Snapshots" , 4) 
    if ($Confrim -eq "YES" ){ 
        foreach ($objItem in $objGridBox.SelectedItems){  
            $x += $objItem 
            $objItem | ForEach-Object { $VMselection = $VMPaths -match "$_"; CreateSnapshot } 
        } 
    } 
}) 


# make Delete snapshot button 
$DeleteSnapshotButton = New-Object System.Windows.Forms.Button  
$DeleteSnapshotButton.Size = New-Object System.Drawing.Size(75,23)
$DeleteSnapshotButton.Top = 30
$DeleteSnapshotButton.Left = 5
$DeleteSnapshotButton.Text = "Delete Snap" 
$DeleteSnapshotButton.Name = "DeleteSnapshot" 
$DeleteSnapshotButton.add_MouseHover($ShowHelp) 
$DeleteSnapshotButton.Add_Click({ 
    $Confrim = [System.Windows.Forms.MessageBox]::Show("Are you sure you want to Snaphot the selected VMs?" , "Create Snapshots" , 4) 
    if ($Confrim -eq "YES" ){ 
        foreach ($objItem in $objGridBox.SelectedItems){  
            $x += $objItem 
            $objItem | ForEach-Object { $VMselection = $VMPaths -match "$_"; CreateSnapshot } 
        } 
    } 
}) 

# make snapshot button 
$RevertSnapshotButton = New-Object System.Windows.Forms.Button  
$RevertSnapshotButton.Size = New-Object System.Drawing.Size(75,23)
$RevertSnapshotButton.Top = 20
$RevertSnapshotButton.Left = 85
$RevertSnapshotButton.Text = "Revert Snap" 
$RevertSnapshotButton.Name = "RevertSnapshot" 
$RevertSnapshotButton.add_MouseHover($ShowHelp) 
$RevertSnapshotButton.Add_Click({ 
    $Confrim = [System.Windows.Forms.MessageBox]::Show("Are you sure you want to Snaphot the selected VMs?" , "Create Snapshots" , 4) 
    if ($Confrim -eq "YES" ){ 
        foreach ($objItem in $objGridBox.SelectedItems){  
            $x += $objItem 
            $objItem | ForEach-Object { $VMselection = $VMPaths -match "$_"; CreateSnapshot } 
        } 
    } 
}) 

# make the net config button 
$NetConfigButton = New-Object System.Windows.Forms.Button 
$NetConfigButton.Location = New-Object System.Drawing.Size(5,5) 
$NetConfigButton.Size = New-Object System.Drawing.Size(45,45) 
$NetConfigButton.Name = "NetConfigButton" 
$NetConfigButton.add_MouseHover($ShowHelp) 
try { 
    $NetConfigicon = [system.drawing.icon]::ExtractAssociatedIcon("$WorkstationPath\vmnetcfg.exe") 
    $NetConfigButton.Image = $NetConfigicon 
} catch { 
    $NetConfigButton.Text = "VMNet"
}
$NetConfigButton.Add_Click({ 
   # Start NMnet editor as admin 
   try { Start-Process "$WorkstationPath\vmnetcfg.exe" -Verb RunAs } 
   catch { Out2Log ("Failed to launch Virtual Network Editior: " + $_) -l_severity 0 } 
}) 

 
# make the putty button
$PuttyButton = New-Object System.Windows.Forms.Button 
$PuttyButton.Location = New-Object System.Drawing.Size(50,5) 
$PuttyButton.Size = New-Object System.Drawing.Size(45,45) 
$PuttyButton.Name = "PuttyButton" 
$PuttyButton.add_MouseHover($ShowHelp) 
try { 
    $puttyicon = [system.drawing.icon]::ExtractAssociatedIcon("${env:ProgramFiles(x86)}\PuTTY\putty.exe") 
    $PuttyButton.Image = $puttyicon 
} catch { 
    $PuttyButton.Text = "Putty" 
} 
$PuttyButton.Add_Click({ 
    # Launch Putty SSH 
    if ($objGridBox.SelectedRows.Length -eq 1){
        try{
            $ip = & vmrun getGuestIPAddress $objGridBox.SelectedRows.Cells[4].Value.ToString()
            Out2Log ("IP Address: $ip ") -l_severity 1
        }
        catch{ Out2Log ("Failed to get VM IP Address " + $_) -l_severity 0 }
        try { [system.Diagnostics.Process]::start("${env:ProgramFiles(x86)}\PuTTY\putty.exe",$ip) } 
        catch { Out2Log ("Failed to launch Putty: " + $_) -l_severity 0 }
    } else {
        Out2Log ("Must select only 1 VM above") -l_severity 0
    }
}) 


$RDPButton = New-Object System.Windows.Forms.Button 
$RDPButton.Location = New-Object System.Drawing.Size(95,5) 
$RDPButton.Size = New-Object System.Drawing.Size(45,45) 
$RDPButton.Name = "RDPButton" 
$RDPButton.add_MouseHover($ShowHelp) 
try { 
    $rdpicon = [system.drawing.icon]::ExtractAssociatedIcon("$env:SystemRoot\System32\mstsc.exe") 
    $RDPButton.Image = $rdpicon 
} catch { 
    $RDPButton.Text = "RDP" 
} 
$RDPButton.Add_Click({ 
    # Launch Putty SSH 
    if ($objGridBox.SelectedRows.Length -eq 1){
        try{
            $ip = & vmrun getGuestIPAddress $objGridBox.SelectedRows.Cells[4].Value.ToString()
            Out2Log ("IP Address: $ip ") -l_severity 1
        }
        catch{ Out2Log ("Failed to get VM IP Address " + $_) -l_severity 0 }
        try { [system.Diagnostics.Process]::start("$env:SystemRoot\System32\mstsc.exe","/v:$ip") } 
        catch { Out2Log ("Failed to launch RDP: " + $_) -l_severity 0 }
    } else {
        Out2Log ("Must select only 1 VM above") -l_severity 0
    }
})

# make the Grid Label
$objGridLabel = New-Object System.Windows.Forms.Label 
$objGridLabel.Location = New-Object System.Drawing.Size(10,10) 
$objGridLabel.Size = New-Object System.Drawing.Size(280,20) 
$objGridLabel.Text = "Please select the VM(s) you wish to control:" 


# make the GridDataView Box
$objGridBox = New-Object System.Windows.Forms.DataGridView 
$objGridBox.Location = New-Object System.Drawing.Size(10,30) 
$objGridBox.Size = New-Object System.Drawing.Size(($form.Width - 35), [Math]::Min((($objGridBox.RowTemplate.Height) * ($script:VMList.Length + 2)), 300))
$objGridBox.MaximumSize = New-Object System.Drawing.Size(500,250)
#$objGridBox.Height = [Math]::Min((($objGridBox.RowTemplate.Height) * ($script:VMList.Length + 2)), 300)
$objGridBox.Anchor = "Top,Left,Right"
$objGridBox.AutoSizeColumnsMode = "AllCells"
$objGridBox.SelectionMode = "FullRowSelect"
$objGridBox.RowHeadersVisible = $False
$objGridBox.MultiSelect = $True
$objGridBox.ReadOnly = $True
$objGridBox.AllowUserToResizeRows = $False
$objGridBox.AllowUserToResizeColumns = $True
#$bojGridBox.AllowUserToSort = $True

# bind the VM array to the datagrid
$array = New-Object System.Collections.ArrayList
$array.AddRange($script:VMList)
$objGridBox.DataSource = $array

# make the log label
$objLogLabel = New-Object System.Windows.Forms.Label 
$objLogLabel.Location = New-Object System.Drawing.Size(10,290) 
$objLogLabel.Size = New-Object System.Drawing.Size(280,20) 
$objLogLabel.Text = "Session Log:" 

# make the log box
$objLogBox = New-Object System.Windows.Forms.ListBox 
$objLogBox.Location = New-Object System.Drawing.Size(10,310) 
$objLogBox.Size = New-Object System.Drawing.Size(($form.Width - 35),80)
$objLogBox.Anchor = "Top,Left,Right,Bottom"
$objLogBox.HorizontalScrollbar = $true
$objLogBox.SelectionMode = "MultiExtended" 
 

# build the button panel
$commandsButtonPanel = New-Object Windows.Forms.Panel
$commandsButtonPanel.Size = New-Object System.Drawing.Size(325,60)
$commandsButtonPanel.Location = New-Object System.Drawing.Size(5,($form.Height - $commandsButtonPanel.Height - 45))
$commandsButtonPanel.Anchor = "Bottom, Left"
$commandsButtonPanel.BorderStyle = "FixedSingle"
$CommandsButtonPanel.Text = "VM Commands"
$commandsButtonPanel.Controls.Add($StartButton)
$commandsButtonPanel.Controls.Add($StartAllButton)
$commandsButtonPanel.Controls.Add($SuspendButton)
$commandsButtonPanel.Controls.Add($SuspendAllButton)
$commandsButtonPanel.Controls.Add($StopButton)
$commandsButtonPanel.Controls.Add($StopAllButton)
$commandsButtonPanel.Controls.Add($ResetButton)
$commandsButtonPanel.Controls.Add($RefreshListButton)

$connectButtonPanel = New-Object Windows.Forms.Panel
$connectButtonPanel.Size = New-Object System.Drawing.Size(145,60)
$connectButtonPanel.Location = New-Object System.Drawing.Size(340,($form.Height - $connectButtonPanel.Height - 45))
$connectButtonPanel.Anchor = "Bottom, Left"
$connectButtonPanel.BorderStyle = "FixedSingle"
$connectButtonPanel.Text = "VM Commands"
$connectButtonPanel.Controls.Add($NetConfigButton)
$connectButtonPanel.Controls.Add($RDPButton)
$connectButtonPanel.Controls.Add($PuttyButton)

$snapsButtonPanel = New-Object Windows.Forms.Panel
$snapsButtonPanel.Size = New-Object System.Drawing.Size(165,60)
$snapsButtonPanel.Location = New-Object System.Drawing.Size(500,($form.Height - $snapsButtonPanel.Height - 45))
$snapsButtonPanel.Anchor = "Bottom, Left"
$snapsButtonPanel.BorderStyle = "FixedSingle"
$snapsButtonPanel.Controls.Add($CreateSnapshotButton)
$snapsButtonPanel.Controls.Add($DeleteSnapshotButton)
$snapsButtonPanel.Controls.Add($RevertSnapshotButton)


$form.Controls.Add($commandsButtonPanel)
$form.Controls.Add($connectButtonPanel)
$form.Controls.Add($snapsButtonPanel) 
$form.Controls.Add($objGridLabel) 
$form.Controls.Add($objGridBox)
$form.Controls.Add($objLogLabel)
$form.Controls.Add($objLogBox)


# display GUI
$form.Add_Shown({$form.Activate()})
[void] $form.ShowDialog()
# $x
