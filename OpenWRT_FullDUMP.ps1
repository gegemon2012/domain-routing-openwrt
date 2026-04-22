# openwrt_backup_restore.ps1
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$form = New-Object System.Windows.Forms.Form
$form.Text = "OpenWRT Backup & Restore Tool"
$form.Width = 750
$form.Height = 650
$form.StartPosition = "CenterScreen"

# Panel
$panel = New-Object System.Windows.Forms.Panel
$panel.Dock = "Top"
$panel.Height = 160
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

# Info
$lblInfo = New-Object System.Windows.Forms.Label
$lblInfo.Text = "Password will be asked for each partition"
$lblInfo.Location = New-Object System.Drawing.Point(100, 72)
$lblInfo.Size = New-Object System.Drawing.Size(300, 20)
$lblInfo.ForeColor = "Gray"
$panel.Controls.Add($lblInfo)

# Progress
$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = New-Object System.Drawing.Point(10, 100)
$progress.Width = 400
$progress.Height = 20
$panel.Controls.Add($progress)

# Buttons
$btnBackup = New-Object System.Windows.Forms.Button
$btnBackup.Text = "Create Backup"
$btnBackup.Location = New-Object System.Drawing.Point(440, 10)
$btnBackup.Width = 220
$btnBackup.Height = 40
$btnBackup.BackColor = "LightGreen"
$btnBackup.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", 10, [System.Drawing.FontStyle]::Bold)
$panel.Controls.Add($btnBackup)

$btnSafeRestore = New-Object System.Windows.Forms.Button
$btnSafeRestore.Text = "Safe Restore"
$btnSafeRestore.Location = New-Object System.Drawing.Point(440, 55)
$btnSafeRestore.Width = 220
$btnSafeRestore.Height = 35
$btnSafeRestore.BackColor = "LightYellow"
$btnSafeRestore.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", 9, [System.Drawing.FontStyle]::Bold)
$panel.Controls.Add($btnSafeRestore)

$btnFullRestore = New-Object System.Windows.Forms.Button
$btnFullRestore.Text = "Full Restore (DANGEROUS)"
$btnFullRestore.Location = New-Object System.Drawing.Point(440, 95)
$btnFullRestore.Width = 220
$btnFullRestore.Height = 35
$btnFullRestore.BackColor = "LightCoral"
$btnFullRestore.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", 9, [System.Drawing.FontStyle]::Bold)
$btnFullRestore.ForeColor = "Red"
$panel.Controls.Add($btnFullRestore)

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = "Close"
$btnClose.Location = New-Object System.Drawing.Point(440, 135)
$btnClose.Width = 220
$btnClose.Height = 25
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

function Create-Backup {
    Write-Log ""
    Write-Log "=========================================="
    Write-Log "STARTING BACKUP"
    Write-Log "=========================================="
    
    $ip = $txtIP.Text
    $user = $txtUser.Text
    
    # Папка в директории пользователя
    $userFolder = $env:USERPROFILE
    $backupBaseFolder = "$userFolder\OpenWRT_Backups"
    
    if (-not (Test-Path $backupBaseFolder)) {
        New-Item -ItemType Directory -Path $backupBaseFolder -Force | Out-Null
        Write-Log "Created folder: $backupBaseFolder"
    }
    
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupDir = "$backupBaseFolder\OpenWRT_Backup_$timestamp"
    
    Write-Log "Backup folder: $backupDir"
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    
    Write-Log "Getting MTD partitions..."
    Write-Log ">>> You will be asked for password below <<<"
    Write-Log ""
    
    $mtdList = & ssh $user@$ip "cat /proc/mtd" 2>&1
    $mtdList | Out-File "$backupDir\mtd_list.txt"
    Write-Log "MTD list saved"
    
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
    
    Write-Log ""
    Write-Log "Found $total partitions"
    Write-Log "=========================================="
    Write-Log ""
    
    foreach ($part in $partitions) {
        $current++
        $percent = [int](($current / $total) * 100)
        $progress.Value = $percent
        
        $safeName = $part.Name -replace '[\\/:*?"<>|]', '_'
        $dumpFile = "$backupDir\$($part.Device)_$safeName.bin"
        
        Write-Log "[$current/$total] Dumping $($part.Device) ($($part.Name))..."
        Write-Log ">>> Enter password when prompted <<<"
        
        $dumpContent = & ssh $user@$ip "dd if=/dev/$($part.Device) 2>/dev/null" 2>&1
        
        if ($dumpContent) {
            $dumpContent | Out-File -FilePath $dumpFile -Encoding UTF8
            $size = [math]::Round((Get-Item $dumpFile).Length / 1KB, 2)
            Write-Log "  Saved: $size KB"
        } else {
            Write-Log "  WARNING: Empty dump"
        }
        Write-Log ""
    }
    
    Write-Log ""
    Write-Log "=========================================="
    Write-Log "BACKUP COMPLETE"
    Write-Log "=========================================="
    Write-Log "Backup saved to: $backupDir"
    Write-Log "Total partitions: $total"
    Write-Log ""
    
    [System.Windows.Forms.MessageBox]::Show(
        "Backup created successfully!`n`nFolder: $backupDir`n`nTotal partitions: $total", 
        "Success", "OK", "Information"
    )
    
    $progress.Value = 100
}

function Get-DangerousPartitions {
    return @("art", "factory", "uboot", "u-boot", "bootloader", "nvram")
}

function Is-DangerousPartition {
    param($PartitionName)
    
    $dangerous = Get-DangerousPartitions
    foreach ($danger in $dangerous) {
        if ($PartitionName -match $danger) {
            return $true
        }
    }
    return $false
}

function Restore-Backup {
    param([bool]$SkipDangerous)
    
    $mode = if ($SkipDangerous) { "SAFE MODE (skip dangerous)" } else { "FULL MODE (ALL partitions)" }
    
    Write-Log ""
    Write-Log "=========================================="
    Write-Log "RESTORE FROM BACKUP - $mode"
    Write-Log "=========================================="
    
    if ($SkipDangerous) {
        Write-Log "Safe mode: Dangerous partitions will be SKIPPED"
        $dangerousList = (Get-DangerousPartitions) -join ", "
        Write-Log "Dangerous partitions: $dangerousList"
    } else {
        Write-Log "FULL mode: ALL partitions will be restored (DANGEROUS!)"
        Write-Log "This includes: art, factory, uboot, bootloader, nvram"
    }
    Write-Log ""
    
    # Выбираем папку с бэкапом
    $folder = New-Object System.Windows.Forms.FolderBrowserDialog
    $folder.Description = "Select backup folder (contains .bin files)"
    $folder.ShowNewFolderButton = $false
    
    if ($folder.ShowDialog() -ne "OK") {
        Write-Log "Restore cancelled by user"
        return
    }
    
    $backupDir = $folder.SelectedPath
    Write-Log "Selected backup folder: $backupDir"
    
    # Проверяем наличие файлов
    $backupFiles = Get-ChildItem "$backupDir\*.bin" -ErrorAction SilentlyContinue
    
    if ($backupFiles.Count -eq 0) {
        Write-Log "ERROR: No .bin files found in selected folder"
        [System.Windows.Forms.MessageBox]::Show(
            "No .bin files found in selected folder!", 
            "Error", "OK", "Error"
        )
        return
    }
    
    Write-Log "Found $($backupFiles.Count) backup files"
    Write-Log ""
    
    $ip = $txtIP.Text
    $user = $txtUser.Text
    
    # Получаем текущие разделы на роутере
    Write-Log "Getting current MTD partitions from router..."
    $currentMtd = & ssh $user@$ip "cat /proc/mtd" 2>&1
    
    # Парсим текущие разделы
    $currentParts = @{}
    $currentMtd -split "`r`n" | Where-Object { $_ -match "^mtd(\d+):.*""(.+)""" } | ForEach-Object {
        $currentParts[$matches[2]] = "mtd$($matches[1])"
    }
    
    # Собираем список для восстановления
    $restoreList = @()
    $skippedList = @()
    
    foreach ($file in $backupFiles) {
        # Извлекаем имя раздела из имени файла (формат: mtdX_name.bin)
        if ($file.Name -match "mtd\d+_(.+)\.bin$") {
            $partName = $matches[1]
            
            # Проверяем опасность раздела
            $isDangerous = Is-DangerousPartition -PartitionName $partName
            
            if ($SkipDangerous -and $isDangerous) {
                $skippedList += $partName
                Write-Log "SKIP - Dangerous partition (safe mode): $partName"
                continue
            }
            
            if ($SkipDangerous -and -not $isDangerous) {
                Write-Log "OK - Safe partition: $partName"
            }
            
            if (-not $SkipDangerous) {
                Write-Log "WARNING - Restoring $partName (including dangerous)"
            }
            
            # Проверяем существует ли такой раздел на роутере
            if ($currentParts.ContainsKey($partName)) {
                $restoreList += @{
                    Name = $partName
                    Device = $currentParts[$partName]
                    File = $file.FullName
                    Size = [math]::Round($file.Length / 1KB, 2)
                    IsDangerous = $isDangerous
                }
                Write-Log "  -> $($currentParts[$partName]) ($($restoreList[-1].Size) KB)"
            } else {
                Write-Log "SKIP - Partition not found on router: $partName"
            }
        }
    }
    
    if ($restoreList.Count -eq 0) {
        Write-Log ""
        Write-Log "ERROR: No partitions to restore"
        [System.Windows.Forms.MessageBox]::Show(
            "No partitions to restore!", 
            "Error", "OK", "Error"
        )
        return
    }
    
    Write-Log ""
    Write-Log "=========================================="
    Write-Log "Partitions to restore:"
    foreach ($item in $restoreList) {
        $dangerMark = if ($item.IsDangerous) { " [DANGEROUS]" } else { "" }
        Write-Log "  - $($item.Name) -> $($item.Device) ($($item.Size) KB)$dangerMark"
    }
    
    if ($skippedList.Count -gt 0) {
        Write-Log ""
        Write-Log "Skipped partitions (dangerous):"
        foreach ($skip in $skippedList) {
            Write-Log "  - $skip"
        }
    }
    Write-Log "=========================================="
    Write-Log ""
    
    # Подтверждение в зависимости от режима
    if ($SkipDangerous) {
        $confirmMsg = "Safe Restore`n`nYou are about to restore $($restoreList.Count) partition(s).`nDangerous partitions will be skipped.`n`nContinue?"
        $confirmTitle = "Confirm Safe Restore"
    } else {
        $confirmMsg = "FULL RESTORE - DANGEROUS!`n`nYou are about to restore $($restoreList.Count) partition(s).`nThis INCLUDES dangerous partitions (art, uboot, etc).`nTHIS CAN BRICK YOUR ROUTER!`n`nContinue?"
        $confirmTitle = "DANGEROUS - Confirm Full Restore"
    }
    
    $confirm1 = [System.Windows.Forms.MessageBox]::Show(
        $confirmMsg,
        $confirmTitle,
        "YesNo",
        "Warning"
    )
    
    if ($confirm1 -ne "Yes") {
        Write-Log "Restore cancelled by user"
        return
    }
    
    # Второе подтверждение для полного восстановления
    if (-not $SkipDangerous) {
        $confirm2 = [System.Windows.Forms.MessageBox]::Show(
            "FINAL WARNING!`n`nYou are about to restore dangerous partitions!`nThis can permanently damage your router!`n`nType 'YES' to continue",
            "FINAL CONFIRMATION - FULL RESTORE",
            "YesNo",
            "Error"
        )
        
        if ($confirm2 -ne "Yes") {
            Write-Log "Restore cancelled by user"
            return
        }
    }
    
    Write-Log ""
    Write-Log "Starting restore operation..."
    Write-Log ">>> You will be asked for password for each partition <<<"
    Write-Log ""
    
    $total = $restoreList.Count
    $current = 0
    
    foreach ($item in $restoreList) {
        $current++
        $percent = [int](($current / $total) * 100)
        $progress.Value = $percent
        
        $dangerWarning = if ($item.IsDangerous) { " [DANGEROUS PARTITION!]" } else { "" }
        Write-Log "[$current/$total] Restoring $($item.Name) to $($item.Device)$dangerWarning"
        Write-Log ">>> Enter password when prompted <<<"
        
        # Читаем файл бэкапа
        $backupData = Get-Content $item.File -Raw -Encoding UTF8
        
        if ($backupData) {
            # Экранируем спецсимволы
            $escapedData = $backupData -replace "'", "'\\''"
            
            # Восстанавливаем через SSH
            $result = & ssh $user@$ip "echo '$escapedData' | dd of=/dev/$($item.Device) 2>/dev/null && echo 'OK'" 2>&1
            
            if ($result -match "OK") {
                Write-Log "  OK - Restored successfully"
            } else {
                Write-Log "  ERROR - Restore failed: $result"
            }
        } else {
            Write-Log "  ERROR - Cannot read backup file"
        }
        Write-Log ""
    }
    
    Write-Log ""
    Write-Log "=========================================="
    Write-Log "RESTORE COMPLETE"
    Write-Log "=========================================="
    Write-Log "Restored $total partitions"
    
    if ($skippedList.Count -gt 0) {
        Write-Log "Skipped $($skippedList.Count) dangerous partitions"
    }
    Write-Log ""
    Write-Log "IMPORTANT: Reboot router to apply changes!"
    
    $reboot = [System.Windows.Forms.MessageBox]::Show(
        "Restore completed!`n`nReboot router now?",
        "Reboot Required",
        "YesNo",
        "Question"
    )
    
    if ($reboot -eq "Yes") {
        Write-Log "Rebooting router..."
        & ssh $user@$ip "reboot" 2>&1
        Write-Log "Reboot command sent"
    }
    
    $progress.Value = 100
}

# Button handlers
$btnBackup.Add_Click({ 
    try {
        Create-Backup
    } catch {
        Write-Log "ERROR: $_"
    }
})

$btnSafeRestore.Add_Click({ 
    try {
        Restore-Backup -SkipDangerous $true
    } catch {
        Write-Log "ERROR: $_"
    }
})

$btnFullRestore.Add_Click({ 
    try {
        Restore-Backup -SkipDangerous $false
    } catch {
        Write-Log "ERROR: $_"
    }
})

$btnClose.Add_Click({ $form.Close() })

# Startup info
Write-Log "=========================================="
Write-Log "OpenWRT Backup & Restore Tool"
Write-Log "=========================================="
Write-Log ""
Write-Log "BACKUP:"
Write-Log "  - Creates full backup of ALL MTD partitions"
Write-Log "  - Saves to: %USERPROFILE%\OpenWRT_Backups\"
Write-Log ""
Write-Log "SAFE RESTORE:"
Write-Log "  - Restores only SAFE partitions"
Write-Log "  - Skips: art, factory, uboot, bootloader, nvram"
Write-Log "  - Recommended for normal use"
Write-Log ""
Write-Log "FULL RESTORE (DANGEROUS):"
Write-Log "  - Restores ALL partitions including dangerous"
Write-Log "  - Can brick your router!"
Write-Log "  - Use only if you know what you're doing"
Write-Log ""
Write-Log "Password will be asked for each partition"
Write-Log "=========================================="

$form.ShowDialog()
