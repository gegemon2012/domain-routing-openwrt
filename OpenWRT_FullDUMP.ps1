# openwrt_simple_backup_restore.ps1
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$form = New-Object System.Windows.Forms.Form
$form.Text = "OpenWRT Backup & Restore Tool"
$form.Width = 700
$form.Height = 600
$form.StartPosition = "CenterScreen"

# Panel
$panel = New-Object System.Windows.Forms.Panel
$panel.Dock = "Top"
$panel.Height = 150
$form.Controls.Add($panel)

# IP
$lblIP = New-Object System.Windows.Forms.Label
$lblIP.Text = "Router IP:"
$lblIP.Location = New-Object System.Drawing.Point(10, 15)
$lblIP.AutoSize = $true
$panel.Controls.Add($lblIP)

$txtIP = New-Object System.Windows.Forms.TextBox
$txtIP.Location = New-Object System.Drawing.Point(100, 12)
$txtIP.Width = 150
$txtIP.Text = "192.168.1.1"
$panel.Controls.Add($txtIP)

# User
$lblUser = New-Object System.Windows.Forms.Label
$lblUser.Text = "User:"
$lblUser.Location = New-Object System.Drawing.Point(10, 45)
$lblUser.AutoSize = $true
$panel.Controls.Add($lblUser)

$txtUser = New-Object System.Windows.Forms.TextBox
$txtUser.Location = New-Object System.Drawing.Point(100, 42)
$txtUser.Width = 150
$txtUser.Text = "root"
$panel.Controls.Add($txtUser)

# Password
$lblPass = New-Object System.Windows.Forms.Label
$lblPass.Text = "Password:"
$lblPass.Location = New-Object System.Drawing.Point(10, 75)
$lblPass.AutoSize = $true
$panel.Controls.Add($lblPass)

$txtPass = New-Object System.Windows.Forms.TextBox
$txtPass.Location = New-Object System.Drawing.Point(100, 72)
$txtPass.Width = 150
$txtPass.UseSystemPasswordChar = $true
$panel.Controls.Add($txtPass)

# Progress
$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = New-Object System.Drawing.Point(10, 115)
$progress.Width = 400
$progress.Height = 20
$panel.Controls.Add($progress)

# Buttons
$btnBackup = New-Object System.Windows.Forms.Button
$btnBackup.Text = "Create Backup"
$btnBackup.Location = New-Object System.Drawing.Point(440, 10)
$btnBackup.Width = 220
$btnBackup.Height = 35
$btnBackup.BackColor = "LightGreen"
$panel.Controls.Add($btnBackup)

$btnRestore = New-Object System.Windows.Forms.Button
$btnRestore.Text = "Restore from Backup"
$btnRestore.Location = New-Object System.Drawing.Point(440, 55)
$btnRestore.Width = 220
$btnRestore.Height = 35
$btnRestore.BackColor = "LightCoral"
$panel.Controls.Add($btnRestore)

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = "Close"
$btnClose.Location = New-Object System.Drawing.Point(440, 100)
$btnClose.Width = 220
$btnClose.Height = 35
$panel.Controls.Add($btnClose)

# Log
$log = New-Object System.Windows.Forms.TextBox
$log.Multiline = $true
$log.ScrollBars = "Vertical"
$log.Dock = "Fill"
$log.ReadOnly = $true
$log.BackColor = "Black"
$log.ForeColor = "Lime"
$log.Font = New-Object System.Drawing.Font("Consolas", 9)
$form.Controls.Add($log)

function Write-Log {
    param($Message)
    $log.AppendText("$Message`r`n")
    $log.ScrollToCaret()
}

function Invoke-SSHCommand {
    param($Command)
    
    $ip = $txtIP.Text
    $user = $txtUser.Text
    $pass = $txtPass.Text
    
    Write-Log "> $Command"
    
    try {
        if ($pass -ne "") {
            $result = & sshpass -p $pass ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no $user@$ip $Command 2>&1
        } else {
            $result = & ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no $user@$ip $Command 2>&1
        }
        return $result
    }
    catch {
        Write-Log "ERROR: $_"
        return $null
    }
}

function Test-Connection {
    Write-Log "Testing SSH connection..."
    $result = Invoke-SSHCommand "echo OK"
    
    if ($result -match "OK") {
        Write-Log "OK - Connected to router"
        return $true
    } else {
        Write-Log "ERROR - Cannot connect to router"
        Write-Log "Check IP, username and password (sshpass required for password auth)"
        return $false
    }
}

function Create-Backup {
    Write-Log ""
    Write-Log "=========================================="
    Write-Log "STARTING BACKUP"
    Write-Log "=========================================="
    
    if (-not (Test-Connection)) { return }
    
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupDir = "OpenWRT_Backup_$timestamp"
    Write-Log "Creating folder: $backupDir"
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    
    Write-Log "Getting MTD partitions..."
    $mtdList = Invoke-SSHCommand "cat /proc/mtd"
    
    if ($mtdList) {
        $mtdList | Out-File "$backupDir\mtd_list.txt"
        Write-Log "MTD list saved"
    }
    
    # Find all mtd partitions
    $lines = $mtdList -split "`r`n"
    $partitions = @()
    
    foreach ($line in $lines) {
        if ($line -match "^mtd(\d+):.*""(.+)""") {
            $partitions += @{
                Number = $matches[1]
                Name = $matches[2]
                Device = "mtd$($matches[1])"
            }
        }
    }
    
    $total = $partitions.Count
    $current = 0
    
    foreach ($part in $partitions) {
        $current++
        $percent = [int](($current / $total) * 100)
        $progress.Value = $percent
        
        $safeName = $part.Name -replace '[\\/:*?"<>|]', '_'
        $dumpFile = "$backupDir\$($part.Device)_$safeName.bin"
        
        Write-Log "[$current/$total] Dumping $($part.Device) ($($part.Name))..."
        
        # Simple dump using dd
        $dumpContent = Invoke-SSHCommand "dd if=/dev/$($part.Device) 2>/dev/null"
        
        if ($dumpContent) {
            $dumpContent | Out-File -FilePath $dumpFile -Encoding UTF8
            $size = [math]::Round((Get-Item $dumpFile).Length / 1KB, 2)
            Write-Log "  Saved: $size KB"
        } else {
            Write-Log "  WARNING: Empty dump"
        }
    }
    
    Write-Log "Creating archive..."
    Compress-Archive -Path "$backupDir\*" -DestinationPath "$backupDir.zip" -Force
    
    Write-Log ""
    Write-Log "=========================================="
    Write-Log "BACKUP COMPLETE"
    Write-Log "=========================================="
    Write-Log "File: $backupDir.zip"
    
    [System.Windows.Forms.MessageBox]::Show(
        "Backup created successfully!`n`n$backupDir.zip", 
        "Success", "OK", "Information"
    )
    
    $progress.Value = 100
}

function Restore-Backup {
    Write-Log ""
    Write-Log "=========================================="
    Write-Log "RESTORE OPERATION"
    Write-Log "=========================================="
    Write-Log "WARNING: This will write to router MTD partitions!"
    
    # Select backup folder
    $folder = New-Object System.Windows.Forms.FolderBrowserDialog
    $folder.Description = "Select folder with backup files"
    
    if ($folder.ShowDialog() -ne "OK") {
        Write-Log "Restore cancelled"
        return
    }
    
    $backupDir = $folder.SelectedPath
    Write-Log "Backup folder: $backupDir"
    
    # Check connection
    if (-not (Test-Connection)) { return }
    
    # Get current MTD layout
    Write-Log "Getting current MTD layout..."
    $currentMtd = Invoke-SSHCommand "cat /proc/mtd"
    
    # Find backup files
    $backupFiles = Get-ChildItem "$backupDir\*.bin" -ErrorAction SilentlyContinue
    
    if ($backupFiles.Count -eq 0) {
        Write-Log "ERROR: No .bin files found in backup folder"
        return
    }
    
    Write-Log "Found $($backupFiles.Count) backup files"
    
    # Parse current partitions
    $currentParts = @{}
    $currentMtd -split "`r`n" | Where-Object { $_ -match "^mtd(\d+):.*""(.+)""" } | ForEach-Object {
        $currentParts[$matches[2]] = "mtd$($matches[1])"
    }
    
    # Build restore list
    $restoreItems = @()
    
    foreach ($file in $backupFiles) {
        # Extract partition name from filename (format: mtdX_name.bin)
        if ($file.Name -match "mtd\d+_(.+)\.bin$") {
            $partName = $matches[1]
            
            # Skip dangerous partitions
            if ($partName -match "art|factory|uboot|bootloader|nvram|u-boot") {
                Write-Log "SKIP - Protected partition: $partName"
                continue
            }
            
            # Check if partition exists on router
            if ($currentParts.ContainsKey($partName)) {
                $restoreItems += @{
                    Name = $partName
                    Device = $currentParts[$partName]
                    File = $file.FullName
                    Size = $file.Length
                }
                Write-Log "Found: $partName -> $($currentParts[$partName])"
            } else {
                Write-Log "SKIP - Partition not found: $partName"
            }
        }
    }
    
    if ($restoreItems.Count -eq 0) {
        Write-Log "ERROR: No matching partitions found for restore"
        return
    }
    
    # Show restore plan
    Write-Log ""
    Write-Log "Partitions to restore:"
    foreach ($item in $restoreItems) {
        $sizeKB = [math]::Round($item.Size / 1KB, 2)
        Write-Log "  - $($item.Name) -> $($item.Device) ($sizeKB KB)"
    }
    
    # First confirmation
    $confirm = [System.Windows.Forms.MessageBox]::Show(
        "WARNING!`n`nYou are about to restore $($restoreItems.Count) partition(s).`nThis can DAMAGE your router if wrong!`n`nContinue?",
        "Confirm Restore",
        "YesNo",
        "Warning"
    )
    
    if ($confirm -ne "Yes") {
        Write-Log "Restore cancelled"
        return
    }
    
    # Second confirmation
    $confirm2 = [System.Windows.Forms.MessageBox]::Show(
        "FINAL WARNING!`n`nAre you ABSOLUTELY sure?`nThis will write directly to MTD devices!",
        "Final Confirmation",
        "YesNo",
        "Error"
    )
    
    if ($confirm2 -ne "Yes") {
        Write-Log "Restore cancelled"
        return
    }
    
    # Perform restore
    Write-Log ""
    Write-Log "Starting restore..."
    $total = $restoreItems.Count
    $current = 0
    
    foreach ($item in $restoreItems) {
        $current++
        $percent = [int](($current / $total) * 100)
        $progress.Value = $percent
        
        Write-Log "[$current/$total] Restoring $($item.Name)..."
        
        # Read the backup file
        $backupData = Get-Content $item.File -Raw -Encoding UTF8
        
        if ($backupData) {
            # Simple restore using echo through SSH
            Write-Log "  Writing to $($item.Device)..."
            
            # Escape special characters
            $escapedData = $backupData -replace "'", "'\\''"
            
            # Write to MTD
            $result = Invoke-SSHCommand "echo '$escapedData' | dd of=/dev/$($item.Device) 2>/dev/null && echo 'OK'"
            
            if ($result -match "OK") {
                Write-Log "  OK - Restored successfully"
            } else {
                Write-Log "  ERROR - Restore failed"
            }
        } else {
            Write-Log "  ERROR - Cannot read backup file"
        }
    }
    
    Write-Log ""
    Write-Log "=========================================="
    Write-Log "RESTORE COMPLETE"
    Write-Log "=========================================="
    Write-Log "IMPORTANT: Reboot router to apply changes"
    
    $reboot = [System.Windows.Forms.MessageBox]::Show(
        "Restore finished!`n`nReboot router now?",
        "Reboot",
        "YesNo",
        "Question"
    )
    
    if ($reboot -eq "Yes") {
        Write-Log "Rebooting router..."
        Invoke-SSHCommand "reboot"
        Write-Log "Reboot command sent"
    }
    
    $progress.Value = 100
}

# Button handlers
$btnBackup.Add_Click({ Create-Backup })
$btnRestore.Add_Click({ Restore-Backup })
$btnClose.Add_Click({ $form.Close() })

# Startup info
Write-Log "OpenWRT Backup & Restore Tool"
Write-Log "=========================================="
Write-Log "Backup - Safe, creates full router backup"
Write-Log "Restore - DANGEROUS, restores from backup"
Write-Log "=========================================="
Write-Log ""
Write-Log "Protected partitions (skipped):"
Write-Log "  art, factory, uboot, bootloader, nvram"
Write-Log ""
Write-Log "Requirements:"
Write-Log "  - SSH access to router"
Write-Log "  - sshpass for password authentication"
Write-Log "=========================================="

$form.ShowDialog()