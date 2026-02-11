if ($IsWindows -or ($null -eq $IsWindows -and $env:OS -match "Windows")) {
    $HostOS = "Windows"
    $HSTImagerExecutableName = "Hst.imager.exe"
    $HSTImagerURL = "https://github.com/henrikstengaard/hst-imager/releases/download/1.5.564/hst-imager_v1.5.564-123f110_console_windows_x64.zip"
} elseif ($IsLinux) {
    $HostOS = "Linux"
    $LoggedInUser = $env:SUDO_USER
    $HSTImagerExecutableName = "hst.imager"
    $HSTImagerURL = "https://github.com/henrikstengaard/hst-imager/releases/download/1.5.564/hst-imager_v1.5.564-123f110_console_linux_x64.zip"
} elseif ($IsMacOS) {
    $HostOS = "MacOS"
    $LoggedInUser = $env:SUDO_USER
    $HSTImagerExecutableName = "hst.imager"
    $HSTImagerURL = "https://github.com/henrikstengaard/hst-imager/releases/download/1.5.564/hst-imager_v1.5.564-123f110_console_macos_x64.zip"
} else {
    Write-Error "Unsupported OS for automatic download."
    exit
}

Write-host "AGS Image Generator v0.6"

Add-Type -AssemblyName System.Net.Http
$client = [System.Net.Http.HttpClient]::new()
$client.DefaultRequestHeaders.UserAgent.ParseAdd("PowerShellHttpClient")

# --- 2. BASE DIRECTORY & FOLDER SETUP ---
if ($PSScriptRoot) {
    $BaseDir = (Get-item $PSScriptRoot).FullName   
} else { 
    $BaseDir = (Get-Item (Join-Path -Path $PWD -ChildPath "Powershell")).FullName
}

$FolderMapping = @{ 
    "Temp" = "..\Temp"; 
    "HSTImager" = "..\HSTImager" 
}

$Paths = @{}
foreach ($key in $FolderMapping.Keys) {
    $Target = Join-Path -Path $BaseDir -ChildPath $FolderMapping[$key]
    if (-not (Test-Path $Target)) { 
        $null = New-Item -Path $Target -ItemType Directory -Force 
    }
    $Paths[$key] = (Get-Item $Target).FullName
}

$FileSystemFolder = (Get-Item (Join-Path -Path $BaseDir -ChildPath "..\FileSystem")).FullName
$FilestoAddPath = (get-item (Join-Path -Path $BaseDir -ChildPath "..\FilestoAdd")).FullName
$TempFolderPath   = $Paths["Temp"]
$HSTProgramFolder = $Paths["HSTImager"]
$FullHSTImagerPath = Join-Path $HSTProgramFolder -ChildPath $HSTImagerExecutableName

# --- 3. DOWNLOAD HST IMAGER ---
if (-not (Test-Path $FullHSTImagerPath)) {
    Write-Host "HST Imager not found. Downloading..." -ForegroundColor Cyan
    $ZipPath = Join-Path $TempFolderPath -ChildPath "HSTImager.zip"
    $response = $client.GetAsync($HSTImagerURL, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).Result
    $FileLength = $response.Content.Headers.ContentLength
    $stream = $response.Content.ReadAsStreamAsync().Result
    $fileStream = [System.IO.File]::OpenWrite($ZipPath)
    $buffer = New-Object byte[] 65536
    while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
        $fileStream.Write($buffer, 0, $read)
        $totalRead += $read
        Write-Progress -Activity "Downloading" -Status "$([math]::Floor(($totalRead/$FileLength)*100))% Complete" -PercentComplete ([math]::Floor(($totalRead/$FileLength)*100))
    }
    $fileStream.Dispose()
    $stream.Dispose()
    Expand-Archive -Path $ZipPath -DestinationPath $HSTProgramFolder -Force
    If ($HostOS -ne "Windows"){
        Write-Host "Cleaning up permissions and ownership of HST Imager Files"
        $dirArgs = @($HSTProgramFolder, "-type", "d", "-exec", "chmod", "755", "{}", "+")
        $fileArgs = @($HSTProgramFolder, "-type", "f", "-exec", "chmod", "644", "{}", "+")
        $ownerArgs = @("-R", "$($LoggedInUser):$($LoggedInUser)", $HSTProgramFolder)
        
        # Set default Directory permissions to 755
        & /usr/bin/find -- $dirArgs
        # Set default File permissions to 644
        & /usr/bin/find -- $fileArgs
        & chown $ownerArgs        
        # Using /usr/bin/chmod for reliability on Unix systems
        & chmod +x "$FullHSTImagerPath"
        
    }
}

# --- 4. PRIVILEGE CHECK ---
$IsAdmin = if ($HostOS -eq "Windows") {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
} else { 
    ($(id -u) -eq 0) 
}

if (-not $IsAdmin) {
    if ($HostOS -eq "Windows") {
        $EscalateDir = Get-Location
        $ArgList = "-NoProfile -ExecutionPolicy Bypass -Command `"Set-Location -LiteralPath '$EscalateDir'; & '$PSCommandPath'`""
        try { Start-Process powershell.exe -ArgumentList $ArgList -Verb RunAs; exit } catch { exit }
    } else {
        Write-Host "ERROR: Root privileges required. Use sudo." -ForegroundColor Red
        exit
    }
}

Write-Host "-------------------------------------------------------------------" 
Write-Host "This tool will generate an image based on the default AGS files    " 
write-host "and in the case of PiStorm write that image to a SD card with the  "
Write-Host "required files in order to run in your Amiga. It should be         "
Write-Host "considered beta software and is used at your own risk!             "
Write-Host "-------------------------------------------------------------------"
Write-Host "Running on $HostOS"
Write-Host ""
Pause

# --- 5. MENU STATE ---
$menuStack = @("Main")
$running = $true
$InstallType = "PiStorm - WinUAE"
$FAT32PartitionSizeBytes = 209715200
$RDBOverheadBytes = 10485760
$DiskSelectedSizeBytes = $null
$InstallLocation = "None Selected"
$SourceLocation  = "None Selected"
$FreeBytes = 0

$DriveStatus = [ordered]@{
    "Workbench"      = [pscustomobject]@{ status = "Enabled"; visible = $false; size = 1019805696}
    "Work"           = [pscustomobject]@{ status = "Enabled"; visible = $false; size = 2039611392}
    "AGS_Drive"      = [pscustomobject]@{ status = "Enabled"; visible = $false; size = 4079738880}
    "Media"          = [pscustomobject]@{ status = "Enabled"; visible = $false; size = 4079738880}
    "Music"          = [pscustomobject]@{ status = "Enabled"; visible = $false; size = 4079738880}
    "Emulators"      = [pscustomobject]@{ status = "Enabled"; visible = $true;size = 4079738880}
    "Emulators2"     = [pscustomobject]@{ status = "Enabled"; visible = $true;size = 8159993856}
    "WHD_Games"      = [pscustomobject]@{ status = "Enabled"; visible = $true;size = 8159993856}
    "WHD_Demos"      = [pscustomobject]@{ status = "Enabled"; visible = $true;size = 4079738880}
    "Games"          = [pscustomobject]@{ status = "Enabled"; visible = $true;size = 8159993856}
    "Premium"        = [pscustomobject]@{ status = "Enabled"; visible = $true;size = 8159993856}
}

$currentTotalBytesHDF = $RDBOverheadBytes
foreach($e in ($DriveStatus.Keys | Where-Object { $DriveStatus[$_].status -eq "Enabled" })) { 
    $currentTotalBytesHDF += $DriveStatus[$e].size 
}
              
# --- 6. MAIN LOOP ---
while ($running) {
    Clear-Host
    Write-Host "AGS Image Generator v0.3" -ForegroundColor Yellow
    Write-Host "Menu: $($menuStack -join " > ")" -ForegroundColor Gray
    Write-Host "-------------------------------"

    switch ($menuStack[-1]) {
        "Main" {
            Write-Host "Select an option and press ENTER:" -ForegroundColor Gray
            Write-Host "1. Type of Install     [$InstallType]" -ForegroundColor Cyan
            Write-Host "   - Sets the type of install you want to perform" 
            Write-Host "   - Default is PiStorm install based on WinUAE version"                                               
            Write-Host "2. Location to Install [$InstallLocation]" -ForegroundColor Cyan
            Write-Host "   - Sets the location of where the install will be made"        
            Write-Host "3. Source Location     [$SourceLocation]" -ForegroundColor Cyan
            Write-Host "   - Sets the location for the source file(s)"                    
            if ($InstallType -eq "PiStorm - Portable Install") {
                $enabled = ($DriveStatus.Keys | Where-Object { $DriveStatus[$_].status -eq "Enabled" })
                $currentTotalBytesHDF = $RDBOverheadBytes
                foreach($e in $enabled) { $currentTotalBytesHDF += $DriveStatus[$e].size }
                $currentTotalGB = [math]::Round($currentTotalBytesHDF / 1GB, 2)
                
                # Logic for Available Space
                $availText = if ($InstallLocation -ne "None Selected" -and $FreeBytes -gt 0) { 
                    "$([math]::Round($FreeBytes / 1GB, 2)) GB" 
                } else { 
                    "N/A" 
                }                

                $visibleEnabled = $enabled | Where-Object { $DriveStatus[$_].Visible -eq $true }
                $summary = if ($visibleEnabled.Count -eq ($DriveStatus.Keys | Where-Object {$DriveStatus[$_].Visible}).Count) { "ALL" } else { $visibleEnabled -join ", " }
                
                Write-Host "4. Drives to Install   [$summary] ($currentTotalGB GB / Avail: $availText)" -ForegroundColor Cyan
                Write-Host "   - Allows you to disable to enable different drives if you"
                Write-Host "     do not want to install the full set of drives"    
                Write-Host "5. Write image" -ForegroundColor Cyan
            } 
            elseif (($InstallType -eq "PiStorm - WinUAE")  -or ($InstallType -eq "PiStorm - AGA")){
                Write-Host "4. Set FAT32 Partition Size" -ForegroundColor Cyan
                Write-Host "   - Allows you to set a larger/smaller FAT32 partition size"
                Write-Host "5. Write image" -ForegroundColor Cyan
            }             
            else {
                Write-Host "4. Write image" -ForegroundColor Cyan
            }
            
            Write-Host "`n-------------------------------"
            Write-Host "X. Exit AGS Image Generator" -ForegroundColor Red
            
            $choice = (Read-Host "`nSelection").ToUpper()
            if ($choice -eq '1') { $menuStack += "Type of Install" }
            elseif ($choice -eq '2') { $menuStack += "Location to Install" }
            elseif ($choice -eq '3') { $menuStack += "Source Location" }
            elseif ($choice -eq 'X') { $running = $false }
            elseif ($InstallType -eq "PiStorm - Portable Install") {
                if ($choice -eq '4') { $menuStack += "Drives to Install" }
                elseif ($choice -eq '5') { $menuStack += "Run Command" }
            }
            elseif (($InstallType -eq "PiStorm - WinUAE") -or ($InstallType -eq "PiStorm - AGA")){
                if ($choice -eq '4') { $menuStack += "Set FAT32 Partition Size" }
                elseif ($choice -eq '5') { $menuStack += "Run Command" }
            }             
            else {
                if ($choice -eq '4') { $menuStack += "Run Command" }
            }
        }

        "Type of Install" {
            Write-Host "Select your installation profile:`n" -ForegroundColor Gray
            Write-Host "1. PiStorm - WinUAE Version" -ForegroundColor Cyan
            Write-Host "   - Converts WinUAE AGS for PiStorm (RTG)"
            Write-Host "   - Should work on both PiStorm and PiStorm32lite (AGA software requires an A1200)"
            Write-Host "   - Required: HDMI monitor connected to Pi`n"
            Write-Host "2. PiStorm - AGA Version" -ForegroundColor Cyan
            Write-Host "   - Uses native Amiga video output"
            Write-Host "   - Requires an Amiga 1200 and PiStorm32lite"
            Write-Host "   - Note: Includes a smaller software range than WinUAE`n"
            Write-Host "3. PiStorm - Portable Install - EXPERIMENTAL" -ForegroundColor Cyan
            Write-Host "   - Adds AGS launcher and drives to an existing install"
            Write-Host "   - Sufficient space and a spare MBR partition are needed on the SD card"
            Write-Host "   - The selected drives to include are configurable `n"
            Write-Host "4. General - Combined Drive (Single .hdf file)" -ForegroundColor Cyan
            Write-Host "   - Combines separate .hdf files from WinUAE install into a single .hdf`n"
 
            Write-Host "-------------------------------"
            Write-Host "B. BACK TO MAIN MENU" -ForegroundColor Red
            
            $c = (Read-Host "`nSelect").ToUpper()
            switch ($c) {
                '1' { 
                    $InstallType = "PiStorm - WinUAE"
                    $DiskSelectedSizeBytes =$null
                    $FAT32PartitionSizeBytes = 209715200
                    $InstallLocation = "None Selected"
                    $SourceLocation = "None Selected"
                    foreach ($k in $DriveStatus.Keys) {
                       $DriveStatus[$k].status = "Enabled"
                    }
                    $currentTotalBytesHDF = $RDBOverheadBytes
                    foreach($e in ($DriveStatus.Keys | Where-Object { $DriveStatus[$_].status -eq "Enabled" })) { 
                        $currentTotalBytesHDF += $DriveStatus[$e].size 
                    }                    
                 }
                '2' {
                    $InstallType = "PiStorm - AGA"
                    $FAT32PartitionSizeBytes = 209715200
                    $DiskSelectedSizeBytes = $null
                    $currentTotalBytesHDF = $null
                    $InstallLocation = "None Selected"
                    $SourceLocation = "None Selected"
                } 
                '3' {

                    $InstallType = "PiStorm - Portable Install"
                    $FAT32PartitionSizeBytes = $null
                    $DiskSelectedSizeBytes = $null
                    $DiskSelectedSizeBytes = 0
                    $InstallLocation = "None Selected"
                    $SourceLocation = "None Selected" 
                    
                    $DriveStatus["Workbench"].status  = "Disabled"
                    $DriveStatus["Work"].status       = "Disabled"
                    $DriveStatus["Music"].status      = "Disabled"
                    $DriveStatus["Media"].status      = "Disabled"
                    $DriveStatus["AGS_Drive"].status  = "Enabled"
                    $DriveStatus["Emulators"].status  = "Enabled"
                    $DriveStatus["Emulators2"].status = "Enabled"
                    $DriveStatus["WHD_Games"].status  = "Enabled"
                    $DriveStatus["WHD_Demos"].status  = "Enabled"
                    $DriveStatus["Games"].status      = "Enabled"
                    $DriveStatus["Premium"].status    = "Enabled"
                    $currentTotalBytesHDF = $RDBOverheadBytes
                    foreach($e in ($DriveStatus.Keys | Where-Object { $DriveStatus[$_].status -eq "Enabled" })) { 
                        $currentTotalBytesHDF += $DriveStatus[$e].size 
                    }                       
          
                }
                '4' {
                    $InstallType = "General - Combined"
                    $FAT32PartitionSizeBytes = $null
                    $DiskSelectedSizeBytes =$null
                    $InstallLocation = "None Selected"
                    $SourceLocation = "None Selected" 
                    $currentTotalBytesHDF = $RDBOverheadBytes
                    foreach ($k in $DriveStatus.Keys) {
                       $DriveStatus[$k].status = "Enabled"
                    }                        
                    foreach($e in ($DriveStatus.Keys | Where-Object { $DriveStatus[$_].status -eq "Enabled" })) { 
                        $currentTotalBytesHDF += $DriveStatus[$e].size 
                    }   
                }
            }
            if ($c -match '[1-4B]') { $menuStack = $menuStack[0..($menuStack.Count - 2)] }
        }

"Location to Install" {

    if ($InstallType -eq "General - Combined") {
        # OS-specific path examples
        $PathExample = if ($HostOS -eq "Windows") { "C:\Amiga\Combined.hdf" } 
                       elseif ($HostOS -eq "MacOS") { "/Users/$LoggedInUser/Documents/Combined.hdf" }
                       else { "/home/$LoggedInUser/Documents/Combined.hdf" }

        Write-Host "Provide the full path for the new destination .hdf file" -ForegroundColor Gray
        Write-Host "e.g., $PathExample" -ForegroundColor Gray
        if ($HostOS -ne "Windows"){
            Write-Host "Remember this is case sensitive!" -ForegroundColor Gray
        }
        Write-Host "-------------------------------"
        Write-Host "B. BACK TO MAIN MENU" -ForegroundColor Red
        
        $RawInput = Read-Host "`nPath"
        if ($RawInput.ToUpper() -eq "B") { 
            $menuStack = $menuStack[0..($menuStack.Count - 2)]
            continue 
        }
        # Clean quotes and handle trailing slashes for Mac/Linux compatibility
        $Path = $RawInput.Trim("'").Trim('"').TrimEnd('\').TrimEnd('/')

        if ($Path -notlike "*.hdf") {
        Write-Host "`nERROR: The destination must be a file ending in .hdf" -ForegroundColor Red
        Write-Host "You entered: $Path" -ForegroundColor Gray
        Pause
        continue
        }
        
        # Cross-platform parent directory check
        $ParentDir = Split-Path -Path $Path -Parent
        if ($ParentDir -and (Test-Path $ParentDir -PathType Container)) {
            $InstallLocation = $Path
            Write-Host "Target HDF set to: $InstallLocation" -ForegroundColor Green
            Start-Sleep -Seconds 1
            $menuStack = $menuStack[0..($menuStack.Count - 2)]
        } else {
            Write-Warning "The directory '$ParentDir' does not exist!"
            Pause
        }
        continue 
    }
        
    $DiskDetails = & $FullHSTImagerPath list

    $DiskDetails
    Write-Host "`n-------------------------------" -ForegroundColor Gray
    Write-Host "B. BACK TO MAIN MENU" -ForegroundColor Red
    
    if ($HostOS -eq "Windows") {
        $RawInput = Read-Host "Select disk number (e.g. 6) or 'B' to go back"
    } else {
        $RawInput = Read-Host "Select full path (e.g. /dev/sdb) or 'B' to go back"
    }

    if ($RawInput.ToUpper() -eq "B") { 
        $menuStack = $menuStack[0..($menuStack.Count - 2)]
        continue 
    }
        
    $CleanInput = $RawInput -replace '^\\disk', ''
    $TargetDisk = if ($HostOS -eq "Windows") { "\disk$CleanInput" } else { $CleanInput }
        
        if ($DiskDetails -match "\\disk$CleanInput\b|disk $CleanInput\b") {
            
            if ($InstallType -eq "PiStorm - Portable Install") {
                Write-Host "Checking disk layout for Portable Install..." -ForegroundColor Cyan
                $MBROutput = & $FullHSTImagerPath mbr info $TargetDisk
                
                $FullText = $MBROutput -join "`n"
                $PartLines = @()
                if ($FullText -match "Partitions:") {
                    $PartTableText = (($FullText -split "Partitions:")[1] -split "Partition table overview:")[0]
                    $PartLines = $PartTableText -split "`n" | Where-Object { $_ -match "^\s*\d+\s*\|" }
                }

                $ValidationError = $false
                $FoundFAT32 = $false
                $Count0x76 = 0

                if ($PartLines.Count -gt 0) {
                    $FirstPartCols = $PartLines[0] -split '\|' | ForEach-Object { $_.Trim() }
                    if (($FirstPartCols[1] -eq "0xb") -or ($FirstPartCols[1] -eq "0xc")) {
                        $FoundFAT32 = $true 
                    }

                }

                foreach ($Line in $PartLines) {
                    $Cols = $Line -split '\|' | ForEach-Object {
                         $_.Trim() 
                    }
                    if ($Cols[1] -eq "0x76") { 
                        $Count0x76++ 
                    }
                }

                # --- REPORT STATUS ---
                $FatColor = if ($FoundFAT32) { "Green" } else { "Red" }
                $RdbColor = if ($Count0x76 -gt 0) { "Green" } else { "Red" }
                $FatStatus = if ($FoundFAT32) { "Found" } else { "NOT FOUND" }

                Write-Host "FAT32 (0xb) Partition: $FatStatus" -ForegroundColor $FatColor
                Write-Host "PiStorm (0x76) Partitions Found: $Count0x76" -ForegroundColor $RdbColor
                Write-Host "Total Partitions: $($PartLines.Count)" -ForegroundColor Yellow

                # --- VALIDATE ---
                if (-not $FoundFAT32) {
                    Write-Host "ERROR: No FAT32 partition found in the first slot." -ForegroundColor Red
                    $ValidationError = $true
                }
                if ($Count0x76 -eq 0) {
                    Write-Host "ERROR: No 0x76 partition found." -ForegroundColor Red
                    $ValidationError = $true
                }
                if ($PartLines.Count -gt 3) {
                    Write-Host "ERROR: Disk has $($PartLines.Count) existing partitions. Max 3 allowed." -ForegroundColor Red
                    $ValidationError = $true
                }

                $FreeBytes = 0
                $UnallocatedLine = $MBROutput | Where-Object { $_ -match "Unallocated" } | Select-Object -Last 1
                if ($UnallocatedLine) {
                    $Cols = $UnallocatedLine -split '\|' | ForEach-Object { $_.Trim() }
                    if ($Cols.Count -ge 5) {
                        $FreeBytes = ([int64]$Cols[4] - [int64]$Cols[3]) + 1
                    }
                }

                $RequiredBytes = 0
                foreach($e in ($DriveStatus.Keys | Where-Object { $DriveStatus[$_].status -eq "Enabled" })) { 
                    $RequiredBytes += $DriveStatus[$e].size
                }
                $RequiredBytes += (1024 * 1024) 

                if ($FreeBytes -lt $RequiredBytes) {

                    Write-Host "`nWARNING: INSUFFICIENT SPACE" -ForegroundColor Yellow
                    Write-Host "Available: $([math]::Round($FreeBytes / 1GB, 2)) GB"
                    Write-Host "Required:  $([math]::Round($RequiredBytes / 1GB, 2)) GB"
                    Write-Host "You can still select this disk, but you MUST deselect drives" -ForegroundColor White
                    Write-Host "in the 'Drives to Install' menu before writing." -ForegroundColor White       
                    Pause
                }

                if ($ValidationError) {
                    Pause
                    continue 
                }
                $PortablePartIndex = $PartLines.Count + 1
                $AvailableGB = [math]::Round($FreeBytes / 1GB, 2)
                $RequiredGB  = [math]::Round($RequiredBytes / 1GB, 2)
                Write-Host "Disk verified and compatible for Portable Install." -ForegroundColor Green
                Write-Host "Available Space: $AvailableGB GB" -ForegroundColor Green
                Write-Host "Required Space:  $RequiredGB GB" -ForegroundColor White
                Write-Host "Portable Install will use MBR Partition number: $PortablePartIndex" -ForegroundColor Cyan
                pause
            }

            if (($InstallType -eq "PiStorm - WinUAE") -or ($InstallType -eq "PiStorm - AGA")) {
                $DiskSpaceDetails = & $FullHSTImagerPath info $TargetDisk
                $DiskSelectedSizeBytes = ($DiskSpaceDetails| Where-Object { $_ -match 'Size:' }) -replace '.*\((\d+) bytes\).*', '$1'        
            }
            $InstallLocation = $TargetDisk
            Start-Sleep -s 1
            $menuStack = $menuStack[0..($menuStack.Count - 2)]
        } else { 
            Write-Warning "Disk not found!"
            Pause 
        }
    }
    
    
"Set FAT32 Partition Size" {

    $TotalSpaceNeededBytes = $currentTotalBytesHDF + $FAT32PartitionSizeBytes + $RDBOverheadBytes

    # 3. Set the display text
    $availText = if ($InstallLocation -ne "None Selected" -and ($DiskSelectedSizeBytes)) { 
        "$([math]::Round($DiskSelectedSizeBytes / 1GB, 2)) GB" 
    } else { 
        "N/A" 
    }

    $Fat32SizetoDisplay = if ($FAT32PartitionSizeBytes -ge 1GB) {
        "$([math]::Round($FAT32PartitionSizeBytes / 1GB, 2)) GiB"
    }
    else 
    {
        "$([math]::Round($FAT32PartitionSizeBytes / 1MB, 2)) MiB"
    }

    Write-Host "Set the size for the FAT32 (EMU68BOOT) partition." -ForegroundColor Gray
    Write-Host "Current FAT32 Partition Size: $Fat32SizetoDisplay" -ForegroundColor Cyan
    Write-Host "Destination Disk:   $InstallLocation" -ForegroundColor Gray
    Write-Host "Total Disk Size:   $availText" -ForegroundColor Yellow
    if ($currentTotalBytesHDF){
        Write-Host "Required Space: $([math]::Round($TotalSpaceNeededBytes / 1GB, 2)) GB" -ForegroundColor Gray
    }
    else {
       Write-Host "Required Space: N/A" -ForegroundColor Gray 
    }
    Write-Host "-------------------------------"
    Write-Host "B. BACK TO MAIN MENU (Keep $Fat32SizetoDisplay)" -ForegroundColor Red

    $NewSize = Read-Host "`nEnter new size (e.g., 250mb, 500mb, 1gb)"

    if ($NewSize.ToUpper() -ne "B" -and -not [string]::IsNullOrWhiteSpace($NewSize)) {
        if ($NewSize -match '^\d+(mb|gb)$') {
            
            # --- VALIDATION LOGIC ---
            $Val = [int64]($NewSize -replace '[^\d]')
            $Mult = if ($NewSize -match "gb") { 1GB } else { 1MB }
            $RequestedFatBytes = $Val * $Mult

            if (-not ($DiskSelectedSizeBytes)){
                Write-Warning "Need to select disk first!"
                Pause            
            }
            elseif (($RequestedFatBytes + $currentTotalBytesHDF) -gt $DiskSelectedSizeBytes) {
                Write-Host "`nERROR: Combined size exceeds disk capacity!" -ForegroundColor Red
                Write-Host "Disk Capacity: $([math]::Round($DiskSelectedSizeBytes/1GB, 2)) GB" -ForegroundColor Yellow
                Pause
            } 
            else {
                $Fat32SizetoDisplay = $NewSize.ToLower()
                $FAT32PartitionSizeBytes = $RequestedFatBytes
                Write-Host "Size updated." -ForegroundColor Green
                Start-Sleep -Seconds 1
            }
        } else {
            Write-Warning "Invalid format! Use 'mb' or 'gb'."
            Pause
        }
    }
    $menuStack = $menuStack[0..($menuStack.Count - 2)]
  
}
    
   "Source Location" {
            
            if (($InstallType -eq "PiStorm - WinUAE") -or ($InstallType -eq "General - Combined")) {
                $PathExample = if ($HostOS -eq "Windows") { "C:\Emulators\AGS\WinUAE\AGS_UAE" } else { "/home/$LoggedInUser/Documents/AGS/WinUAE/AGS_UAE" }
                $FileTypeLabel = "folder containing your AGS .hdf files (e.g. $PathExample)"
                $RequiredFiles = @("AGS_Drive.hdf", "Emulators.hdf", "Emulators2.hdf", "Games.hdf", "Media.hdf", "Music.hdf", "Premium.hdf", "WHD_Demos.hdf", "WHD_Games.hdf", "Work.hdf", "Workbench.hdf")
            } 
            elseif ($InstallType -eq "PiStorm - AGA") {
                $PathExample = if ($HostOS -eq "Windows") { "C:\Emulators\AGS\WinUAE\AGS_Classic" } else { "/home/$LoggedInUser/documents/AGS/WinUAE/AGS_Classic" }
                $FileTypeLabel = "path containing the AGA .img file (e.g. $PathExample)"
                $RequiredFiles = @("AGS_Classic_AGA_KickstartFix_v30.img")
            }
            elseif ($InstallType -eq "PiStorm - Portable Install") {
                $PathExample = if ($HostOS -eq "Windows") { "C:\Emulators\AGS\WinUAE\AGS_UAE" } else { "/home/$LoggedInUser/documents/AGS/WinUAE/AGS_UAE" }
                $FileTypeLabel = "folder containing your AGS .hdf files (e.g. $PathExample)"
                $RequiredFiles = @("AGS_Drive.hdf", "Emulators.hdf", "Emulators2.hdf", "Games.hdf", "Media.hdf", "Music.hdf", "Premium.hdf", "WHD_Demos.hdf", "WHD_Games.hdf", "Work.hdf", "Workbench.hdf")                
            }
            
            Write-Host "Provide the $FileTypeLabel" -ForegroundColor Gray
            if ($HostOS -ne "Windows"){
                Write-Host "Remember this is case sensitive!" -ForegroundColor Gray
            }
         
            Write-Host "B. BACK TO MAIN MENU" -ForegroundColor Red
            
            $RawInput = Read-Host "`nPath"
            if ($RawInput.ToUpper() -eq "B") { 
                $menuStack = $menuStack[0..($menuStack.Count - 2)]
                continue 
            }

            $path = $RawInput.Trim("'").Trim('"').TrimEnd('\').TrimEnd('/')
            if (Test-Path $path -PathType Container) {
                $MissingItems = @()
                foreach ($f in $RequiredFiles) {
                    if (Test-Path (Join-Path $path $f)) {
                        Write-Host "[FOUND] $f" -ForegroundColor Green
                    } else {
                        Write-Host "[MISSING] $f" -ForegroundColor Red
                        $MissingItems += $f
                    }
                }

                if ($MissingItems.Count -eq 0) {
                    $SourceLocation = $path
                    if ($InstallType -eq "PiStorm - AGA") {
                        foreach ($f in $RequiredFiles) {
                            $DiskSpaceDetails = & $FullHSTImagerPath info $(Join-Path $path $f)
                        }
                        $currentTotalBytesHDF = [int64](($DiskSpaceDetails| Where-Object { $_ -match 'Size:' }) -replace '.*\((\d+) bytes\).*', '$1')   
                    }
                    Write-Host "`nAll components found." -ForegroundColor Green
                    Start-Sleep -Seconds 1
                    $menuStack = $menuStack[0..($menuStack.Count - 2)]
                } else { 
                    Write-Warning "`nMissing: $($MissingItems.Count) required file(s)!"
                    Pause 
                }
            } else { 
                Write-Warning "Path does not exist!"
                Pause 
            }
        }

        "Drives to Install" {
            Write-Host "Available drives (all selected by default):" -ForegroundColor Gray
            Write-Host "Enter a number to toggle Enable/Disable the drive from installation.`n" -ForegroundColor Gray
            
            $visibleKeys = $DriveStatus.Keys | Where-Object { $DriveStatus[$_].Visible -eq $true }
            $TotalBytes = 0
            
            foreach($k in $DriveStatus.Keys) { 
                if($DriveStatus[$k].status -eq "Enabled") { $TotalBytes += $DriveStatus[$k].size } 
            }
   
            for ($i=0; $i -lt $visibleKeys.Count; $i++) {
                $k = $visibleKeys[$i]
                # Reference .status property
                $isEnabled = ($DriveStatus[$k].status -eq "Enabled")
                $col = if ($isEnabled) { "Green" } else { "Red" }
                # Reference .size property
                $sizeGB = [math]::Round($DriveStatus[$k].size / 1GB, 2)
                Write-Host "[$($i+1)] $k ($sizeGB GB) : $($DriveStatus[$k].status)" -ForegroundColor $col
            }
            
            Write-Host "----------------------------------------------------"
            Write-Host "Total Space Required: $([math]::Round($TotalBytes / 1GB, 2)) GB" -ForegroundColor Yellow

            # --- PORTABLE INSTALL SPACE CHECK ---
            if ($InstallType -eq "PiStorm - Portable Install" -and $InstallLocation -ne "None Selected") {
                if ($TotalBytes -gt $FreeBytes) {
                    Write-Host "WARNING: Selection exceeds available space on $InstallLocation ($([math]::Round($FreeBytes / 1GB, 2)) GB)!" -ForegroundColor Red
                } else {
                    Write-Host "Available on Disk: $([math]::Round($FreeBytes / 1GB, 2)) GB" -ForegroundColor Green
                }
            }            
            # --- PORTABLE INSTALL SPACE CHECK ---

            Write-Host "B. BACK TO MAIN MENU" -ForegroundColor Red

            $c = (Read-Host "`nSelection").ToUpper()
            if ($c -eq 'B') { 
                $menuStack = $menuStack[0..($menuStack.Count-2)] 
            }
            
            elseif ($c -match '^\d+$') { 
                $idx = [int]$c - 1
                if ($idx -ge 0 -and $idx -lt $visibleKeys.Count) {
                    $k = $visibleKeys[$idx]
                    $enabledVisibleCount = 0
                    foreach ($vk in $visibleKeys) {
                        # 1. Update: Check .status property
                        if ($DriveStatus[$vk].status -eq "Enabled") { $enabledVisibleCount++ }
                    }
                    # 2. Update: Check .status property
                    if ($DriveStatus[$k].status -eq "Enabled" -and $enabledVisibleCount -le 1) {
                        Write-Host "`nERROR: You must have at least one additional drive selected." -ForegroundColor Red
                        Start-Sleep -Seconds 2
                    } else {
                        # 3. Update: Toggle the .status property specifically
                        $DriveStatus[$k].status = if ($DriveStatus[$k].status -eq "Enabled") { "Disabled" } else { "Enabled" }
                    }
                }
            }
        }

        "Run Command" {

            $MissingOptions = @()
            if ($InstallLocation -eq "None Selected") { $MissingOptions += "Location to Install (Option 2)" }
            if ($SourceLocation -eq "None Selected")  { $MissingOptions += "Source Location (Option 3)" }

            if ($MissingOptions.Count -gt 0) {
                Write-Host "`nERROR: Cannot proceed with writing." -ForegroundColor Red
                Write-Host "The following options are not set:" -ForegroundColor Yellow
                foreach ($opt in $MissingOptions) { Write-Host " - $opt" }
                Write-Host "`nPlease configure these settings before writing the image." -ForegroundColor White
                Pause
                $menuStack = $menuStack[0..($menuStack.Count - 2)] # Go back to Main Menu
                continue # Skip the rest of the Run Command logic
            }

            # --- PORTABLE INSTALL FINAL GUARD ---
            if ($InstallType -eq "PiStorm - Portable Install") {
                $finalReq = $RDBOverheadBytes
                foreach($e in ($DriveStatus.Keys | Where-Object { $DriveStatus[$_].status -eq "Enabled" })) { 
                    $finalReq += $DriveStatus[$e].size 
                }
                
                if ($InstallLocation -eq "None Selected") {
                    Write-Host "ERROR: No install location selected!" -ForegroundColor Red
                    Pause
                    $menuStack = $menuStack[0..($menuStack.Count-2)]
                    continue
                }

                if ($finalReq -gt $FreeBytes) {
                    Write-Host "`n!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" -ForegroundColor Red
                    Write-Host "CRITICAL ERROR: INSUFFICIENT SPACE" -ForegroundColor Red
                    Write-Host "The selected drives require $([math]::Round($finalReq / 1GB, 2)) GB."
                    Write-Host "The destination disk only has $([math]::Round($FreeBytes / 1GB, 2)) GB free."
                    Write-Host "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" -ForegroundColor Red
                    Write-Host "Please deselect some drives before running."
                    Pause
                    $menuStack = $menuStack[0..($menuStack.Count-2)]
                    continue      
                }
            }      
            # --- PORTABLE INSTALL FINAL GUARD ---
            $ScriptOutputFile = Join-Path -Path $TempFolderPath -ChildPath "hst_commands.txt"
                      
            # --- 6. FINAL CONFIRMATION ---
            Write-Host "====================================================" -ForegroundColor Yellow
            Write-Host "            READY TO WRITE TO DISK" -ForegroundColor Yellow
            Write-Host "====================================================" -ForegroundColor Yellow
            
            # Display target based on InstallType (Disk vs HDF file)
            if ($InstallType -eq "General - Combined") {
                Write-Host "Target HDF File:      $InstallLocation" -ForegroundColor Cyan
            } else {
                Write-Host "Target Disk:          $InstallLocation" -ForegroundColor Red
            }

            Write-Host "Selected AGS Version: $InstallType" -ForegroundColor White
            Write-Host "Source Folder:        $SourceLocation" -ForegroundColor White
            Write-Host "----------------------------------------------------"

            # Warning Logic: Only show ERASE warning for physical disks, not HDF files
            if (($InstallType -ne "General - Combined") -and ($InstallType -ne "PiStorm - Portable Install")){
                Write-Host "WARNING: This will ERASE all data on $InstallLocation." -ForegroundColor Red
                if ($HostOS -ne "Windows") {
                    Write-Host "CAUTION: Ensure $InstallLocation is the correct device node for your SD Card." -ForegroundColor Magenta
                }
            }
            elseif ($InstallType -eq "PiStorm - Portable Install") {
                Write-Host "WARNING: This will write to the card at $InstallLocation which already has data on it. If something goes wrong there is a" -ForegroundColor Red
                Write-host "chance this could destroy data on this card! If you have not already, please make sure you have made a backup!" -ForegroundColor Red
                if ($HostOS -ne "Windows") {
                    Write-Host "CAUTION: Ensure $InstallLocation is the correct device node for your SD Card." -ForegroundColor Magenta
                }
            } 
            else {
                Write-Host "Make sure you have sufficient space on your destination drive!" -ForegroundColor Yellow
                Write-Host "NOTE: This will create/overwrite the file at $InstallLocation" -ForegroundColor Yellow
            }

            Write-Host "====================================================" -ForegroundColor Yellow
            
            if ($InstallType -eq "PiStorm - WinUAE") {
                
                $DriveCopyCommands = ""              
                $Counter = 1

                foreach ($k in $DriveStatus.Keys) {
                    if ($DriveStatus[$k].status -eq "Enabled") {
                        # Map the display name to the actual filename if they differ
                        $FileName = "$k.hdf"
                        $PartName = switch ($k) {
                            "Workbench"      { "DH0" }
                            "Work"           { "DH1" }
                            "Media"          { "DH3" }
                            "Music"          { "DH2" }        
                            "AGS_Drive"      { "DH4" }
                            "Emulators"      { "DH7" }
                            "Emulators2"     { "DH15"}
                            "WHD_Games"      { "DH13"}
                            "WHD_Demos"      { "DH14"}
                            "Games"          { "DH5" }
                            "Premium"        { "DH6" }
                        } 
                        $DriveCopyCommands += "rdb part copy `"$SourceLocation\$FileName`" 1 `"$InstallLocation\MBR\2`" --name $PartName`n"
                        $DriveCopyCommands += "rdb part update `"$InstallLocation\MBR\2`" $Counter --buffers 300"
                        $Counter ++
               
                    }
                }

                if ($HostOS -eq "Windows"){
                    $DriveCopyCommands = ($DriveCopyCommands.Split("`n").Trim() | Where-Object {$_}) -join "`r`n"
                }
                else {
                    $DriveCopyCommands = ($DriveCopyCommands.Split("`n").Trim() | Where-Object {$_}) -join "`n"
                }
                
$ScriptContent = @"
settings update --cache-type disk
blank "$TempFolderPath\Clean.vhd" 10mb
write "$TempFolderPath\Clean.vhd" $InstallLocation --skip-unused-sectors FALSE
mbr init $InstallLocation
mbr part add $InstallLocation 0xb $FAT32PartitionSizeBytes --start-sector 2048
mbr part format $InstallLocation 1 EMU68BOOT
mbr part add $InstallLocation 0x76 ${currentTotalBytesHDF}
rdb init $InstallLocation\mbr\2
rdb filesystem add $InstallLocation\mbr\2 "$FileSystemFolder\pfs3aio" PDS3
fs c "$SourceLocation\Workbench.hdf\rdb\1\Devs\Kickstarts\kick40068.A1200" "$InstallLocation\MBR\1\kick.rom" -f
fs c "$FilestoAddPath\Emu68Boot" $InstallLocation\MBR\1\ -r -md -q
fs mkdir $InstallLocation\MBR\1\SHARED\SaveGames
$DriveCopyCommands
fs c "$SourceLocation\Workbench.hdf\rdb\1\c\whdload" "$InstallLocation\MBR\2\rdb\DH0\c\whdload.ori"
fs c "$FilestoAddPath\WinUAE\Workbench" "$InstallLocation\MBR\2\rdb\DH0" -r -md -q -f
fs c "$FilestoAddPath\WinUAE\Work" "$InstallLocation\MBR\2\rdb\DH1" -r -md -q -f
fs c "$FilestoAddPath\WinUAE\AGS_Drive" "$InstallLocation\MBR\2\rdb\DH4" -r -md -q -f
fs c "$InstallLocation\MBR\2\rdb\DH0\Devs\monitors\HD720*" "$InstallLocation\MBR\2\rdb\DH0\storage\monitors"
fs c "$InstallLocation\MBR\2\rdb\DH0\Devs\monitors\HighGFX*" "$InstallLocation\MBR\2\rdb\DH0\storage\monitors"
fs c "$InstallLocation\MBR\2\rdb\DH0\Devs\monitors\SuperPlus*" "$InstallLocation\MBR\2\rdb\DH0\storage\monitors"
fs c "$InstallLocation\MBR\2\rdb\DH0\Devs\monitors\Xtreme*" "$InstallLocation\MBR\2\rdb\DH0\storage\monitors"
"@
            } 
            elseif ($InstallType -eq "General - Combined"){
                $currentTotalBytesHDF = $RDBOverheadBytes
                foreach($e in ($DriveStatus.Keys | Where-Object { $DriveStatus[$_].status -eq "Enabled" })) { 
                    $currentTotalBytesHDF += $DriveStatus[$e].size 
                }
                
                $DriveCopyCommands = ""

                foreach ($k in $DriveStatus.Keys) {
                    if ($DriveStatus[$k].status -eq "Enabled") {
                        # Map the display name to the actual filename if they differ
                        $FileName = "$k.hdf"
                        $PartName = switch ($k) {
                            "Workbench"      { "DH0" }
                            "Work"           { "DH1" }
                            "Media"          { "DH3" }
                            "Music"          { "DH2" }        
                            "AGS_Drive"      { "DH4" }
                            "Emulators"      { "DH7" }
                            "Emulators2"     { "DH15"}
                            "WHD_Games"      { "DH13"}
                            "WHD_Demos"      { "DH14"}
                            "Games"          { "DH5" }
                            "Premium"        { "DH6" }
                        }                        
                        $DriveCopyCommands += "rdb part copy `"$SourceLocation\$FileName`" 1 `"$InstallLocation`" --name $PartName`n"
                    }
                }
                
                if ($HostOS -eq "Windows"){
                    $DriveCopyCommands = ($DriveCopyCommands.Split("`n").Trim() | Where-Object {$_}) -join "`r`n"
                }
                else {
                    $DriveCopyCommands = ($DriveCopyCommands.Split("`n").Trim() | Where-Object {$_}) -join "`n"
                }

$ScriptContent = @"
settings update --cache-type disk
blank "$InstallLocation" ${currentTotalBytesHDF}
rdb init "$InstallLocation"
rdb filesystem add "$InstallLocation" "$FileSystemFolder\pfs3aio" PDS3
$DriveCopyCommands
"@                
            }
            elseif ($InstallType -eq "PiStorm - Portable Install"){
                $currentTotalBytesHDF = $RDBOverheadBytes
                foreach($e in ($DriveStatus.Keys | Where-Object { $DriveStatus[$_].status -eq "Enabled" })) { 
                    $currentTotalBytesHDF += $DriveStatus[$e].size 
                }
                $DriveCopyCommands = ""
                $Counter = 1
                                
                foreach ($k in $DriveStatus.Keys) {
                    if ($DriveStatus[$k].status -eq "Enabled") {
                        # Map the display name to the actual filename if they differ
                        $FileName = "$k.hdf" 
                        # Map the display name to the Amiga Partition Name (e.g., DH4)
                        $PartName = switch ($k) {
                            "AGS_Drive"      { "ADH0" }
                            "Emulators"      { "ADH1" }
                            "Emulators2"     { "ADH2" }
                            "WHD_Games"      { "ADH3" }
                            "WHD_Demos"      { "ADH4" }
                            "Games"          { "ADH5" }
                            "Premium"        { "ADH6" }
                        }
                        $DriveCopyCommands += "rdb part copy `"$SourceLocation\$FileName`" 1 `"$InstallLocation\MBR\$PortablePartIndex`" --name $PartName`n"
                        $DriveCopyCommands += "rdb part update `"$InstallLocation\MBR\$PortablePartIndex`" $Counter --buffers 300"
                        $Counter ++
                    }
                }

                if ($HostOS -eq "Windows"){
                    $DriveCopyCommands = ($DriveCopyCommands.Split("`n").Trim() | Where-Object {$_}) -join "`r`n"
                }
                else {
                    $DriveCopyCommands = ($DriveCopyCommands.Split("`n").Trim() | Where-Object {$_}) -join "`n"
                }                
                
$ScriptContent = @"
settings update --cache-type disk
mbr part add $InstallLocation 0x76 ${currentTotalBytesHDF}
rdb init $InstallLocation\mbr\$PortablePartIndex
rdb filesystem add $InstallLocation\mbr\$PortablePartIndex "$FileSystemFolder\pfs3aio" PDS3 
$DriveCopyCommands 
fs c "$FilestoAddPath\Portable\AGS_Drive" "$InstallLocation\MBR\$PortablePartIndex\rdb\ADH0" -r -md -q -f
"@                
            
            }
            elseif  ($InstallType -eq "PiStorm - AGA") {
                $AGAImageFile = if($HostOS -eq "Windows"){"$SourceLocation\AGS_Classic_AGA_KickstartFix_v30.img"} Else {"$SourceLocation/AGS_Classic_AGA_KickstartFix_v30.img"}
$ScriptContent = @"
settings update --cache-type disk
blank "$TempFolderPath\Clean.vhd" 10mb
write "$TempFolderPath\Clean.vhd" $InstallLocation --skip-unused-sectors FALSE
mbr init $InstallLocation
mbr part add $InstallLocation 0xb $FAT32PartitionSizeBytes --start-sector 2048
mbr part format $InstallLocation 1 EMU68BOOT
mbr part add $InstallLocation 0x76 ${currentTotalBytesHDF}
write "$AGAImageFile" "$InstallLocation\mbr\2"
"rdb part update `"$InstallLocation\MBR\2`" 1 --buffers 300"
"rdb part update `"$InstallLocation\MBR\2`" 2 --buffers 300"
"rdb part update `"$InstallLocation\MBR\2`" 3 --buffers 300"
"rdb part update `"$InstallLocation\MBR\2`" 4 --buffers 300"
"rdb part update `"$InstallLocation\MBR\2`" 5 --buffers 300"
fs c "$AGAImageFile\rdb\1\Devs\Kickstarts\kick40068.A1200" "$InstallLocation\MBR\1\kick.rom" -f
fs c "$FilestoAddPath\Emu68Boot" $InstallLocation\MBR\1\ -r -md -q
fs mkdir $InstallLocation\MBR\1\SHARED\SaveGames
fs c "$AGAImageFile\rdb\1\c\whdload" "$InstallLocation\MBR\2\rdb\DH0\c\whdload.ori"
fs c "$FilestoAddPath\AGA\Workbench" "$InstallLocation\MBR\2\rdb\DH0" -r -md -q -f
"@  
            }

            if ($HostOS -ne "Windows") { $ScriptContent = $ScriptContent.Replace("\","/") }
            $ScriptContent | Out-File -FilePath $ScriptOutputFile -Encoding utf8 -Force
            
            Write-Host "`nTarget: $InstallLocation`nVersion: $InstallType" -ForegroundColor Yellow
            if ((Read-Host "Type 'YES' to proceed").ToUpper() -eq "YES") {
                if ($HostOS -eq "Windows") {
                   & $FullHSTImagerPath script $ScriptOutputFile 
                }
                else {               
                    $Commands = Get-Content -Path $ScriptOutputFile
                    foreach ($Line in $Commands) {
                        if (-not [string]::IsNullOrWhiteSpace($Line)) {
                            $ArgList = [System.Management.Automation.PsParser]::Tokenize($Line, [ref]$null) | Select-Object -ExpandProperty Content
                            & $FullHSTImagerPath @ArgList
                            Start-Sleep -Seconds 1
                        }
                    }

                    If ($HostOS -ne "Windows"){
                        Write-Host "Cleaning up permissions and ownership of temporary files" -ForegroundColor Cyan
                        Write-Host "so not restricted to Root access" -ForegroundColor Cyan
                        $dirArgs = @($TempFolderPath, "-type", "d", "-exec", "chmod", "755", "{}", "+")
                        $fileArgs = @($TempFolderPath, "-type", "f", "-exec", "chmod", "644", "{}", "+")
                        $ownerArgs = @("-R", "$($LoggedInUser):$($LoggedInUser)", $TempFolderPath)
                        
                        # Set default Directory permissions to 755
                        & /usr/bin/find -- $dirArgs
                        # Set default File permissions to 644
                        & /usr/bin/find -- $fileArgs
                        & chown $ownerArgs        
                        if ($InstallType -eq "General - Combined"){
                            Write-Host "Applying ownership and permissions to destination .hdf file" -ForegroundColor Cyan
                            Write-Host "so not restricted to root access" -ForegroundColor Cyan
                            & chown "$($LoggedInUser):$($LoggedInUser)" "$InstallLocation"
                            & chmod 644 "$InstallLocation"
                        }
                    }                    
                    
                }
                Write-Host "Process Complete. Press enter to exit" -ForegroundColor Green
                pause
                $running = $false
                return
            }
            $menuStack = $menuStack[0..($menuStack.Count-2)]
        }
    }
}
