# Determine OS with backward compatibility for PS 5.1
if ($IsWindows -or ($null -eq $IsWindows -and $env:OS -match "Windows")) {
    $HostOS = "Windows"
    $HSTImagerExecutableName = "Hst.imager.exe"
    $HSTImagerURL = "https://github.com/henrikstengaard/hst-imager/releases/download/1.5.541/hst-imager_v1.5.541-90b4b77_console_windows_x64.zip"
    
}
elseif ($IsLinux) {
    $HostOS = "Linux"
    $HSTImagerExecutableName = "hst.imager"
    $HSTImagerURL = "https://github.com/henrikstengaard/hst-imager/releases/download/1.5.541/hst-imager_v1.5.541-90b4b77_console_linux_x64.zip"
}
elseif ($IsMacOS) {
    $HostOS = "MacOS"
    $HSTImagerExecutableName = "hst.imager"
    $HSTImagerURL = "https://github.com/henrikstengaard/hst-imager/releases/download/1.5.541/hst-imager_v1.5.541-90b4b77_console_macos_x64.zip"
}
else {
    $HostOS = "Unknown"
    $HSTImagerExecutableName = "Hst.imager"
    Write-Error "Unsupported OS for automatic download."
    exit
}

Write-host "AGS PiStorm Image Generator v0.2"
Write-Host "This tool will write an image to a SD card suitable for use in your PiStorm"
Write-Host "Running on $HostOS"
Add-Type -AssemblyName System.Net.Http
$client = [System.Net.Http.HttpClient]::new()
$client.DefaultRequestHeaders.UserAgent.ParseAdd("PowerShellHttpClient")

# If $PSScriptRoot is empty (not running from a file), use the current working directory ($PWD)

if ($PSScriptRoot) {
    $BaseDir = (Get-item $PSScriptRoot).FullName   
} 
else { 
    $BaseDir = (Get-Item (Join-Path -Path $PWD -ChildPath "Powershell")).FullName
}

# Define folder paths (creating them if they don't exist)
$FolderMapping = @{
    "Temp"       = "..\Temp"
    "HSTImager"  = "..\HSTImager"
}

$Paths = @{}
foreach ($key in $FolderMapping.Keys) {
    $Target = Join-Path -Path $BaseDir -ChildPath $FolderMapping[$key]
    if (-not (Test-Path $Target)) {
        $null = New-Item -Path $Target -ItemType Directory -Force
    }
    # Resolve the full absolute path now that we are sure it exists
    $Paths[$key] = (Get-Item $Target).FullName
}

$FileSystemFolder = (Get-Item (Join-Path -Path $BaseDir -ChildPath "..\FileSystem")).FullName
$FilestoAddPath = (get-item (Join-Path -Path $BaseDir -ChildPath "..\FilestoAdd")).FullName
$TempFolderPath   = $Paths["Temp"]
$HSTProgramFolder = $Paths["HSTImager"]
$FullHSTImagerPath = Join-Path $HSTProgramFolder -ChildPath $HSTImagerExecutableName

if (-not (Test-Path "$HSTProgramFolder\$HSTImagerExecutableName")){
    Write-Host "HST Imager not found. Downloading..." -ForegroundColor Cyan
    $ZipPath = Join-Path $TempFolderPath -ChildPath "HSTImager.zip"
    $response = $client.GetAsync($HSTImagerURL, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).Result

    $FileLength = $response.Content.Headers.ContentLength
    $stream = $response.Content.ReadAsStreamAsync().Result
    $fileStream = [System.IO.File]::OpenWrite($ZipPath )
    $buffer = New-Object byte[] 65536  # 64 KB
    $read = 0
    $totalRead = 0
    $percentComplete = 0
    while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
        $fileStream.Write($buffer, 0, $read)
        $totalRead += $read
        $newPercent = [math]::Floor(($totalRead/$FileLength)*100)
        if ($newPercent -ne $percentComplete) {
            $percentComplete = $newPercent
            Write-Progress -Activity "Downloading" -Status "$percentComplete% Complete" -PercentComplete $percentComplete
        }
    }
    Write-Progress -Activity "Downloading" -Completed -Status "Done"
    if ($fileStream) {
        $fileStream.Dispose()
        $fileStream = $null
    }  
    
    Expand-Archive -Path $ZipPath -DestinationPath $HSTProgramFolder 

    # Fix permissions for Linux/macOS
    if ($HostOS -ne "Windows") {
        # Using /usr/bin/chmod for reliability on Unix systems
        & chmod +x "$FullHSTImagerPath"
    }

}

# 1. ESCALATION / PRIVILEGE CHECK
$IsAdmin = $false

# Robust OS and Admin Check
if ($IsWindows -or ($null -eq $IsWindows -and $env:OS -match "Windows")) {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $IsAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
} else {
    # Check for UID 0 on Linux/macOS
    $IsAdmin = ($(id -u) -eq 0)
}

if (-not $IsAdmin) {
    if ($IsWindows -or ($null -eq $IsWindows -and $env:OS -match "Windows")) {
        Write-Host "Not running as Admin. Attempting to escalate..." -ForegroundColor Yellow
        if ($PSCommandPath) {        
           # FIX: We must pass the current directory to the new process 
            # so it doesn't default to C:\Windows\System32
            $EscalateDir = Get-Location
            $ArgList = "-NoProfile -ExecutionPolicy Bypass -Command `"Set-Location -LiteralPath '$EscalateDir'; & '$PSCommandPath'`""
            try {
                Start-Process powershell.exe -ArgumentList $ArgList -Verb RunAs -ErrorAction Stop
                exit
            } catch {
                Write-Host "Failed to elevate automatically. Please right-click and 'Run as Administrator'." -ForegroundColor Red
                Read-Host "Press Enter to exit"
                exit
            }
        } else {
            Write-Error "Script must be saved as a .ps1 file to auto-escalate on Windows."
            Read-Host "Press Enter to exit"
            exit
        }
    } else {
        # Linux / MacOS Logic: Stop and Error
        Write-Host "ERROR: This script requires root privileges to access disks." -ForegroundColor Red
        Write-Host "Please run this script using sudo:" -ForegroundColor Yellow
        Write-Host "Example: sudo pwsh $(if($PSCommandPath){$PSCommandPath}else{'YourScript.ps1'})" -ForegroundColor Cyan
        exit
    }
}


$AGSVersion = ""
while ($AGSVersion -notin @("WinUAE", "AGA")) {
    Write-Host ""
    Write-Host "Select AGS Installation Version:" -ForegroundColor Cyan
    Write-Host ""    
    Write-Host "1. WinUAE - this will install the WinUAE version of AGS. You will need a 64Gib card"
    Write-Host "2. AGA (A1200 only) - this will install the AGA version of AGS. You will need a 32GiB card"
    $Selection = Read-Host "Enter choice (1 or 2)"
    if ($Selection -eq "1") { $AGSVersion = "WinUAE" }
    elseif ($Selection -eq "2") { $AGSVersion = "AGA" }
    else { Write-Warning "Invalid selection. Please enter 1 or 2." }
}
Write-Host "Selected Version: $AGSVersion`n" -ForegroundColor Green

Write-Host "`nListing disks via $HSTImagerExecutableName..." -ForegroundColor Green
Write-Host "Identify the disk you wish to use to write the image. Note this disk will be erased!"

$DiskList = & $FullHSTImagerPath list
$DiskList # Display the list to the user

$DiskValid = $false
while (-not $DiskValid) {
    if ($HostOS -eq "Windows") {
        $RawInput = Read-Host "Which disk number do you wish to use? (e.g., enter '6' for \disk6)"
        # Strip \disk prefix if they typed it, so we only have the number for regex
        $CleanInput = $RawInput -replace '^\\disk', ''
        $InputPattern = '^\d+$'
    } else {
        $RawInput = Read-Host "Enter the full disk path (e.g., /dev/sdb)"
        $CleanInput = $RawInput
        $InputPattern = '^/dev/.*'
    }

    # 1. Basic format check
    if ($CleanInput -match $InputPattern) {
        
        # 2. Define search pattern for Hst.imager output
        $SearchPattern = if ($HostOS -eq "Windows") {
            "\\disk$CleanInput\b|disk $CleanInput\b"
        } else {
            [regex]::Escape($CleanInput)
        }

        # 3. Check if it actually exists in the imager's list
        if ($DiskList -match $SearchPattern) {
            $DiskValid = $true
            
            # 4. Finalizing $DisktoUse based on OS
            if ($HostOS -eq "Windows") {
                $DisktoUse = "\disk$CleanInput"
            } else {
                $DisktoUse = $CleanInput
            }

            Write-Host "Success: '$DisktoUse' verified and selected." -ForegroundColor Green
        }
        else {
            Write-Warning "Disk '$CleanInput' was not found in the Hst.imager list. Check the list and try again."
        }
    }
    else {
        $ErrorMsg = if ($HostOS -eq "Windows") { "Please enter a numeric disk ID." } else { "Linux/Mac paths must start with '/dev/'." }
        Write-Warning "Invalid format. $ErrorMsg"
    }
}

If ($AGSVersion -eq "WinUAE"){
    # Define the list of required files/folders for the AGS Image source
    $RequiredFiles = @(
        "AGS_Drive.hdf", "Emulators.hdf", "Emulators2.hdf", "Games.hdf", 
        "Media.hdf", "Music.hdf", "Premium.hdf", "WHD_Demos.hdf", 
        "WHD_Games.hdf", "Work.hdf", "Workbench.hdf"
    )
    $RequiredDir = "SHARED"
}
else {
        $RequiredFiles = @(
        "AGS_Classic_AGA_KickstartFix_v30.img"
    )
}

# Validation loop for the AGS Source Folder
$SourceValid = $false
while (-not $SourceValid) {
    # Determine the specific terminology based on version
    $FileTypeLabel = if ($AGSVersion -eq "WinUAE") { "AGS .hdf files" } else { "AGS_Classic_AGA_KickstartFix_v30.img" }
    
    if ($HostOS -eq "Windows") {
        $ExamplePath = if ($AGSVersion -eq "WinUAE") { "C:\Emulators\AGS\WinUAE\AGS_UAE" } else { "C:\Emulators\AGS\AGS_Classic" }
        $AGSSourceLocation = Read-Host -Prompt "Provide the folder containing your $FileTypeLabel (e.g. $ExamplePath)"
    }
    else {
        # Linux/MacOS Example
        $ExamplePath = if ($AGSVersion -eq "WinUAE") { "/home/user/documents/AGS/WinUAE/AGS_UAE" } else { "/home/user/documents/AGS/AGS_Classic" }
        $AGSSourceLocation = Read-Host -Prompt "Provide the folder containing your $FileTypeLabel (e.g. $ExamplePath). Note this is case-sensitive!"
    }
    
    $AGSSourceLocation = $AGSSourceLocation.Trim("'").Trim('"').TrimEnd('\').TrimEnd('/')
    
    if (Test-Path -Path $AGSSourceLocation -PathType Container) {
        $MissingItems = @()
        if ($AGSVersion -eq "WinUAE") {
            # Check for HDF files
            foreach ($File in $RequiredFiles) {
                $FilePath = Join-Path -Path $AGSSourceLocation -ChildPath $File
                if (-not (Test-Path -Path $FilePath -PathType Leaf)) {
                    $MissingItems += $File
                }
            }        
            # Check for SHARED directory
            $DirPath = Join-Path -Path $AGSSourceLocation -ChildPath $RequiredDir
            if (-not (Test-Path -Path $DirPath -PathType Container)) {
                $MissingItems += "$RequiredDir (Directory)"
            }
        }
        else {
            # AGA Logic: Check for the single file stored in $RequiredFiles
            $FilePath = Join-Path -Path $AGSSourceLocation -ChildPath $RequiredFiles[0]
            if (-not (Test-Path -Path $FilePath -PathType Leaf)) {
                $MissingItems += $RequiredFiles[0]
            }
        }
    
        if ($MissingItems.Count -eq 0) {
            $SourceValid = $true
            Write-Host "Success: All required components for $AGSVersion found in $AGSSourceLocation" -ForegroundColor Green
        }
        else {
            Write-Warning "The folder is missing the following required components for ${AGSVersion}:"
            $MissingItems | ForEach-Object { Write-Host " - $_" -ForegroundColor Red }
        }
    }

    else {
        Write-Warning "The directory '$AGSSourceLocation' does not exist."
    }

}

# 3. Define Output Script Path
$ScriptOutputFile = Join-Path -Path $TempFolderPath -ChildPath "hst_commands.txt"

# 4. Generate the Text File Content
# Injected variables: $TempFolderPath, $AGSSourceLocation, $DisktoUse, $FilepathtoKickstartROM

if ($AGSVersion -eq "WinUAE") {

$ScriptContent = @"
settings update --cache-type disk
blank "$TempFolderPath\Clean.vhd" 10mb
write "$TempFolderPath\Clean.vhd" $DisktoUse --skip-unused-sectors FALSE
mbr init $DisktoUse
mbr part add $DisktoUse 0xb 1073741824 --start-sector 2048
mbr part format $DisktoUse 1 EMU68BOOT
mbr part add $DisktoUse 0x76 58gb --start-sector 2099200
rdb init $DisktoUse\mbr\2
rdb filesystem add $DisktoUse\mbr\2 "$FileSystemFolder\pfs3aio" PDS3
rdb part copy "$AGSSourceLocation\Workbench.hdf" 1 "$DisktoUse\mbr\2" --name DH0
rdb part copy "$AGSSourceLocation\Work.hdf" 1 "$DisktoUse\MBR\2" --name DH1
rdb part copy "$AGSSourceLocation\Music.hdf" 1 "$DisktoUse\MBR\2" --name DH2
rdb part copy "$AGSSourceLocation\Media.hdf" 1 "$DisktoUse\MBR\2" --name DH3
rdb part copy "$AGSSourceLocation\AGS_Drive.hdf" 1 "$DisktoUse\MBR\2" --name DH4
rdb part copy "$AGSSourceLocation\Games.hdf" 1 "$DisktoUse\MBR\2" --name DH5
rdb part copy "$AGSSourceLocation\Premium.hdf" 1 "$DisktoUse\MBR\2" --name DH6
rdb part copy "$AGSSourceLocation\Emulators.hdf" 1 "$DisktoUse\MBR\2" --name DH7
rdb part copy "$AGSSourceLocation\WHD_Demos.hdf" 1 "$DisktoUse\MBR\2" --name DH13
rdb part copy "$AGSSourceLocation\WHD_Games.hdf" 1 "$DisktoUse\MBR\2" --name DH14
rdb part copy "$AGSSourceLocation\Emulators2.hdf" 1 "$DisktoUse\MBR\2" --name DH15
fs c "$FilestoAddPath\Emu68Boot" $DisktoUse\MBR\1\ -r -md -q
fs mkdir $DisktoUse\MBR\1\SHARED\SaveGames
fs c "$DisktoUse\MBR\2\rdb\DH0\s\startup-sequence" "$DisktoUse\MBR\2\rdb\DH0\s\startup-sequence.bak"
fs c "$DisktoUse\MBR\2\rdb\DH0\s\user-startup" "$DisktoUse\MBR\2\rdb\DH0\s\user-startup.bak"
fs c "$DisktoUse\MBR\2\rdb\DH0\s\AGS-Stuff" "$DisktoUse\MBR\2\rdb\DH0\s\AGS-Stuff.bak"
fs c "$DisktoUse\MBR\2\rdb\DH0\c\whdload" "$DisktoUse\MBR\2\rdb\DH0\c\whdload.ori"
fs c "$FilestoAddPath\WinUAE\Workbench" "$DisktoUse\MBR\2\rdb\DH0" -r -md -q -f
fs c "$FilestoAddPath\WinUAE\Work" "$DisktoUse\MBR\2\rdb\DH1" -r -md -q -f
fs c "$FilestoAddPath\WinUAE\AGS_Drive" "$DisktoUse\MBR\2\rdb\DH4" -r -md -q -f
fs c "$DisktoUse\MBR\2\rdb\DH0\Devs\monitors\HD720*" "$DisktoUse\MBR\2\rdb\DH0\storage\monitors"
fs c "$DisktoUse\MBR\2\rdb\DH0\Devs\monitors\HighGFX*" "$DisktoUse\MBR\2\rdb\DH0\storage\monitors"
fs c "$DisktoUse\MBR\2\rdb\DH0\Devs\monitors\SuperPlus*" "$DisktoUse\MBR\2\rdb\DH0\storage\monitors"
fs c "$DisktoUse\MBR\2\rdb\DH0\Devs\monitors\Xtreme*" "$DisktoUse\MBR\2\rdb\DH0\storage\monitors"
fs c "$DisktoUse\MBR\2\rdb\DH0\Devs\Kickstarts\kick40068.A1200" "$DisktoUse\MBR\1\kick.rom"
"@
}

else {
   If ($HostOS -eq "Windows"){
       $AGAImageFile = "$AGSSourceLocation\$($RequiredFiles[0])"
   }
   else {
       $AGAImageFile = "$AGSSourceLocation/$($RequiredFiles[0])"
   }

   $ScriptContent = @"
settings update --cache-type disk
blank "$TempFolderPath\Clean.vhd" 10mb
write "$TempFolderPath\Clean.vhd" $DisktoUse --skip-unused-sectors FALSE
mbr init $DisktoUse
mbr part add $DisktoUse 0xb 250mb --start-sector 2048
mbr part format $DisktoUse 1 EMU68BOOT
mbr part add $DisktoUse 0x76 30601641984
write "$AGAImageFile" "$DisktoUse\mbr\2"
fs c "$DisktoUse\MBR\2\rdb\DH0\Devs\Kickstarts\kick40068.A1200" "$DisktoUse\MBR\1\kick.rom"
fs c "$FilestoAddPath\Emu68Boot" $DisktoUse\MBR\1\ -r -md -q
fs mkdir $DisktoUse\MBR\1\SHARED\SaveGames
fs c "$DisktoUse\MBR\2\rdb\DH0\c\whdload" "$DisktoUse\MBR\2\rdb\DH0\c\whdload.ori"
fs c "$FilestoAddPath\AGA\Workbench" "$DisktoUse\MBR\2\rdb\DH0" -r -md -q -f
"@   
}

If ($HostOS -ne "Windows"){
    $ScriptContent = $ScriptContent.Replace("\","/")
}

# 5. Write to File
$ScriptContent | Out-File -FilePath $ScriptOutputFile -Encoding utf8 -Force
Write-Host "HST Imager script generated at: $ScriptOutputFile" -ForegroundColor Green

If ($HostOS -ne "Windows"){
    & chmod 664 "$ScriptOutputFile"
}

# 6. FINAL CONFIRMATION
Write-Host "`n====================================================" -ForegroundColor Yellow
Write-Host "            READY TO WRITE TO DISK" -ForegroundColor Yellow
Write-Host "====================================================" -ForegroundColor Yellow
Write-Host "Target Disk:          $DisktoUse" -ForegroundColor Red
Write-Host "Selected AGS Version: $AGSVersion"
Write-Host "Source Folder:        $AGSSourceLocation"
Write-Host "----------------------------------------------------"
Write-Host "WARNING: This will ERASE all data on $DisktoUse." -ForegroundColor Red
Write-Host "====================================================" -ForegroundColor Yellow

$Confirmation = Read-Host "Type 'YES' to proceed with the write operation"

if ($Confirmation -eq "YES") {
    Write-Host "`nStarting Hst.imager script execution..." -ForegroundColor Cyan
    
    # Run the hst.imager with the script argument
    # On Windows: & "path\to\Hst.imager.exe" script "path\to\hst_commands.txt"
    # On Linux/Mac: & "path/to/Hst.imager" script "path/to/hst_commands.txt"
    
    & $FullHSTImagerPath script $ScriptOutputFile
    
    Write-Host "`nOperation completed." -ForegroundColor Green
}
else {
    Write-Host "`nOperation cancelled by user. No changes were made." -ForegroundColor Red
}

Read-Host -Prompt "`nPress Enter to close this window"