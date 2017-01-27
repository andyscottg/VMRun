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

    Requires VMware Workstation (http://www.vmware.com/products/workstation.html).
#>


# Check if run as Administrator
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
    [Security.Principal.WindowsBuiltInRole] "Administrator"))
	{
	(new-object -ComObject wscript.shell).Popup("Please re-run as an Administrator",0,"RunAs Admin")
	Break
	}

$ScriptPath = split-path -parent $MyInvocation.MyCommand.Definition

#net start vmx86 # On rare occasions may need to start this service after boot

# Find VMware Workstation install directory
$xml = [xml](Get-Content "${env:ProgramData}\VMware\hostd\config.xml")
if ($xml -eq $null)
	{
	(new-object -ComObject wscript.shell).Popup("Can't load Workstation config file:`n${env:ProgramData}\VMware\hostd\config.xml",0,"File not Found")
	Break
	}
	else 
	{ 
	$WP = $xml.config.defaultInstallPath
	$WorkstationPath = $WP.Trim()
	}

# Locate VMRun.exe
$vmRun = $WorkstationPath + "vmrun.exe"
if (-NOT (Test-Path $vmRun))
	{
	#throw [System.IO.FileNotFoundException] "$vmRun Needed"
	(new-object -ComObject wscript.shell).Popup("Could not locate $vmRun",0,"File not Found")
	Break
	}
	# If found create vmrun common alias
	else { set-alias vmrun $vmRun }

# Check if user profile settings exist
$vmlsFile = "$env:APPDATA\VMware\inventory.vmls"
if (-NOT (Test-Path -path $vmlsFile))
	{
	#throw [System.IO.FileNotFoundException] "$vmlsFile Not Found"
	(new-object -ComObject wscript.shell).Popup("Could not locate $vmlsFile",0,"File not Found")
	Break
	}
	# Store content of VMware Workstation (Roaming) preferences into String
	else { $Config = Get-Content $vmlsFile | Select-String -Pattern 'index[0-99]\.id' }

# Create the session logging feature
function Out2Log
{
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
	
    <# Write log to file
    if (-NOT (Test-Path -path $ScriptPath\logs))
    { New-Item -ItemType directory -path $ScriptPath\logs\ | Out-Null }

        $l_severity.ToString() + "`t" + `
	    $entryTime + " GMT`t" + `
	    $l_levels.Get_Item($l_severity) + `
	    $l_string | Out-File -Append -NoClobber -Encoding UTF8 -FilePath $ScriptPath\logs\$l_fname
    #>

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

#------------------------------
# Retrieve local VM paths using inventory.vmls
Function Get-VMPaths {
	$Config | ForEach-Object {
	$filePath = $_ -split ' = '
	$filePath[1]
	}
}
# Split VM paths to leave VM names only
Function Get-VMNames {
	$VMPaths | ForEach-Object {
	$fileName = $_ -split '([^\\]+$)' -replace '.vmx"',''
	$fileName[1]
	}
}
# Pass these into variables
$VMPaths = Get-VMPaths
$VMNames = Get-VMNames
#------------------------------

Function Start-VM
{
	# Capture list of running VMs to an Array - skip the 1st entry
	$RunningVMs = Invoke-Expression "vmrun list" | select -skip 1
	# Full path to VM in VMSelection needed
    	$VMselection |
		ForEach-Object {
		#check if selected vm ($objItem) is running by matching $RunningVMs
		if (-NOT ($RunningVMs -match $objItem)){
			Out2Log "Starting $objItem..." -l_severity 1
			# execute VMrun expression to start VM
			try { vmrun -T ws start $_ nogui }
			# Catch any errors into log
			catch { Out2Log ("Could not start $objItem " + $_) -l_severity 0 }
			Out2Log "$objItem Started" -l_severity 1
		}}
}

Function StartAll-VMs
{
	$RunningVMs = Invoke-Expression "vmrun list" | select -skip 1
	# Use VMPaths to control all VMs
    	$VMPaths |
		ForEach-Object {
		# Skip RunningVMs by matching list from $VMPaths
		if (-NOT ($RunningVMs -match $_)){
			# Grab just VM name from path for logging
	   		$item = $_ -split '([^\\]+$)' -replace '.vmx"',' '
			Out2Log ("Starting " + $item[1] + "...") -l_severity 1
			# execute VMrun expression to start VM if powered off
        		try { vmrun -T ws start $_ nogui }
        		catch { Out2Log ("Could not start " + $item[1] + $_) -l_severity 0 }
			Out2Log ($item[1] + " Started") -l_severity 1
        	}}
}

Function Suspend-VM
{
	$RunningVMs = Invoke-Expression "vmrun list" | select -skip 1
    	$VMselection |
		ForEach-Object {
		if ($RunningVMs -match $objItem){
			Out2Log "Suspending $objItem..." -l_severity 1
	   		try { vmrun -T ws suspend $_ nogui }
			catch { Out2Log ("Could not Suspend $objItem " + $_) -l_severity 0 }
			Out2Log "$objItem Suspended" -l_severity 1
		}}
}

Function SuspendAll-VMs
{
	$RunningVMs = Invoke-Expression "vmrun list" | select -skip 1
	$RunningVMs |
		ForEach-Object{
			$item = $_ -split '([^\\]+$)' -replace '.vmx',' '
			Out2Log ("Suspending " + $item[1] +"...") -l_severity 1
			try { vmrun -T ws suspend $_ nogui}
			catch { Out2Log ("Error while Suspending " + $item[1] + $_) -l_severity 0 }
			Out2Log ($item[1] + "Suspended") -l_severity 1
		}
}

Function Reset-VM
{
	$RunningVMs = Invoke-Expression "vmrun list" | select -skip 1
    	$VMselection |
		ForEach-Object {
		if ($RunningVMs -match $objItem){
	   		Out2Log ("Resetting $objItem...") -l_severity 1
        		try { vmrun -T ws reset $_ soft nogui }
        		catch { Out2Log ("Could not SOFT Reset $objItem, ensure VM tools are installed " + $_) -l_severity 0 }
			Out2Log ("$objItem Restarted") -l_severity 1
        }}
}

Function Stop-VM
{
	$RunningVMs = Invoke-Expression "vmrun list" | select -skip 1
    	$VMselection |
		ForEach-Object {
		if ($RunningVMs -match $objItem){
	   		Out2Log ("Powering off $objItem...") -l_severity 1
        		try { vmrun -T ws stop $_ soft nogui }
        		catch { Out2Log ("Could not SOFT Stop $objItem, ensure VM tools are installed " + $_) -l_severity 0 }
			Out2Log ("$objItem Stopped") -l_severity 1
        }}
}

Function CreateSnapshot
{
    $VMselection |
        ForEach-Object {
	   	Out2Log ("Creating Snapshot for $objItem...") -l_severity 1
		$DT2 = (Get-Date -Format "s") -replace "T"," @ "
		$snapshotname = $DT2
        	try { vmrun -T ws snapshot $_ $snapshotname }
        	catch { Out2Log ("Could not create Snapshot for $objItem " + $_) -l_severity 0 }
		Out2Log ("$objItem [$snapshotname] Created") -l_severity 1
        }
}

#Create GUI
$x = @()

[void] [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")
[void] [System.Reflection.Assembly]::LoadWithPartialName("System.Drawing")

$objForm = New-Object System.Windows.Forms.Form
$objForm.Text = "VMrun GUI"
$objForm.Size = New-Object System.Drawing.Size(375,500)
$objForm.StartPosition = "CenterScreen"
try {
$icon = [system.drawing.icon]::ExtractAssociatedIcon("$WorkstationPath\vmware.exe")
$objForm.Icon = $icon
	} catch { Out2Log ("Error retrieving app icon: " + $_) -l_severity 0 }

$objForm.KeyPreview = $True

$objForm.Add_KeyDown({if ($_.KeyCode -eq "Enter")
    {
	foreach ($objItem in $objListbox.SelectedItems)
		{$x += $objItem
		$objItem | ForEach-Object {
		  	$VMselection = $VMPaths -match "$_"
			Start-VM
		  	}
  		}
    }})

$objForm.Add_KeyDown({if ($_.KeyCode -eq "Escape")
    {$objForm.Close()}})

$StartButton = New-Object System.Windows.Forms.Button
$StartButton.Location = New-Object System.Drawing.Size(10,180)
$StartButton.Size = New-Object System.Drawing.Size(75,23)
$StartButton.Text = "Start"

$StartButton.Add_Click(
   {
	foreach ($objItem in $objListbox.SelectedItems)
		{$x += $objItem
		$objItem | ForEach-Object {
		  	$VMselection = $VMPaths -match "$_"
			Start-VM
		  	}
  		}
	})

$objForm.Controls.Add($StartButton)

$StartAllButton = New-Object System.Windows.Forms.Button
$StartAllButton.Location = New-Object System.Drawing.Size(10,210)
$StartAllButton.Size = New-Object System.Drawing.Size(75,23)
$StartAllButton.Text = "Start All"

$StartAllButton.Add_Click(
	{
	$Confrim = [System.Windows.Forms.MessageBox]::Show("Start/Resume all VMs?" , "Start ALL" , 4)
	if ($Confrim -eq "YES" )
		{ StartAll-VMs }
	})

$objForm.Controls.Add($StartAllButton)

$SuspendButton = New-Object System.Windows.Forms.Button
$SuspendButton.Location = New-Object System.Drawing.Size(90,180)
$SuspendButton.Size = New-Object System.Drawing.Size(75,23)
$SuspendButton.Text = "Suspend"

$SuspendButton.Add_Click(
   {
    foreach ($objItem in $objListbox.SelectedItems)
        {$x += $objItem
            $objItem | ForEach-Object {
            $VMselection = $VMPaths -match $_
            Suspend-VM
          }
    } })

$objForm.Controls.Add($SuspendButton)

$SuspendAllButton = New-Object System.Windows.Forms.Button
$SuspendAllButton.Location = New-Object System.Drawing.Size(90,210)
$SuspendAllButton.Size = New-Object System.Drawing.Size(75,23)
$SuspendAllButton.Text = "Suspend All"

$SuspendAllButton.Add_Click(
	{
	$Confrim = [System.Windows.Forms.MessageBox]::Show("Suspend all VMs?" , "Suspend ALL" , 4)
	if ($Confrim -eq "YES" )
		{ SuspendAll-VMs }
	})

$objForm.Controls.Add($SuspendAllButton)

$ResetButton = New-Object System.Windows.Forms.Button
$ResetButton.Location = New-Object System.Drawing.Size(10,240)
$ResetButton.Size = New-Object System.Drawing.Size(75,23)
$ResetButton.Text = "Reset"

$ResetButton.Add_Click(
   {
   $Confrim = [System.Windows.Forms.MessageBox]::Show("Reset selected VMs?" , "Reset" , 4)
	if ($Confrim -eq "YES" )
		{
    		foreach ($objItem in $objListbox.SelectedItems)
        	{$x += $objItem
          	$objItem | ForEach-Object {
            	$VMselection = $VMPaths -match "$_"
            	Reset-VM
          	    }
    		}}})

$objForm.Controls.Add($ResetButton)

$StopButton = New-Object System.Windows.Forms.Button
$StopButton.Location = New-Object System.Drawing.Size(90,240)
$StopButton.Size = New-Object System.Drawing.Size(75,23)
$StopButton.Text = "Stop"

$StopButton.Add_Click(
   {
   $Confrim = [System.Windows.Forms.MessageBox]::Show("Shutdown selected VMs?" , "Shutdown" , 4)
    if ($Confrim -eq "YES" )
        {
		foreach ($objItem in $objListbox.SelectedItems)
          {$x += $objItem
          $objItem | ForEach-Object {
			$VMselection = $VMPaths -match "$_"
               Stop-VM
            	}
		} }})

$objForm.Controls.Add($StopButton)

$SnapshotButton = New-Object System.Windows.Forms.Button
$SnapshotButton.Location = New-Object System.Drawing.Size(270,180)
$SnapshotButton.Size = New-Object System.Drawing.Size(75,23)
$SnapshotButton.Text = "Snapshot"

$SnapshotButton.Add_Click(
   {
   $Confrim = [System.Windows.Forms.MessageBox]::Show("Create Snaphot for selected VMs?" , "Snapshot" , 4)
    if ($Confrim -eq "YES" )
        {
		foreach ($objItem in $objListbox.SelectedItems)
          {$x += $objItem
          $objItem | ForEach-Object {
			$VMselection = $VMPaths -match "$_"
               CreateSnapshot
            	}
		} }})

$objForm.Controls.Add($SnapshotButton)

$NetConfigButton = New-Object System.Windows.Forms.Button
$NetConfigButton.Location = New-Object System.Drawing.Size(270,210)
$NetConfigButton.Size = New-Object System.Drawing.Size(75,23)
$NetConfigButton.Text = "VMNet"

$NetConfigButton.Add_Click(
   {
   # Start NMnet editor as admin
   try { Start-Process "$WorkstationPath\vmnetcfg.exe" -Verb RunAs }
   catch { Out2Log ("Could not start Virtual Network Editior: " + $_) -l_severity 0 }
   })

$objForm.Controls.Add($NetConfigButton)

$CloseButton = New-Object System.Windows.Forms.Button
$CloseButton.Location = New-Object System.Drawing.Size(270,240)
$CloseButton.Size = New-Object System.Drawing.Size(75,23)
$CloseButton.Text = "Close"
$CloseButton.Add_Click({$objForm.Close()})
$objForm.Controls.Add($CloseButton)

$objLabel = New-Object System.Windows.Forms.Label
$objLabel.Location = New-Object System.Drawing.Size(10,20)
$objLabel.Size = New-Object System.Drawing.Size(280,20)
$objLabel.Text = "Please select the VM(s) you wish to control:"
$objForm.Controls.Add($objLabel)

$objListBox = New-Object System.Windows.Forms.ListBox
$objListBox.Location = New-Object System.Drawing.Size(10,40)
$objListBox.Size = New-Object System.Drawing.Size(335,100)
$objListbox.Height = 140
$objListBox.Sorted = $True
$objListBox.HorizontalScrollbar = $true
$objListbox.SelectionMode = "MultiExtended"

$objLogLabel = New-Object System.Windows.Forms.Label
$objLogLabel.Location = New-Object System.Drawing.Size(10,270)
$objLogLabel.Size = New-Object System.Drawing.Size(280,20)
$objLogLabel.Text = "Session Log:"
$objForm.Controls.Add($objLogLabel)

$objLogBox = New-Object System.Windows.Forms.ListBox
$objLogBox.Location = New-Object System.Drawing.Size(10,290)
$objLogBox.Size = New-Object System.Drawing.Size(335,100)
$objLogBox.Height = 150
$objLogBox.HorizontalScrollbar = $true
$objLogBox.SelectionMode = "MultiExtended"
$objForm.Controls.Add($objLogBox)

# add VM names to multi-select listbox
$VMNames | ForEach-Object {[void] $objListBox.Items.Add($_)}

$objForm.Controls.Add($objListbox)
#$objForm.Topmost = $True
$objForm.Add_Shown({$objForm.Activate()})
[void] $objForm.ShowDialog()

# display GUI
$x
