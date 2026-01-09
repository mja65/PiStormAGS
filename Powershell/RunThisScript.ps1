# Determine OS with backward compatibility for PS 5.1
if ($IsWindows -or ($null -eq $IsWindows -and $env:OS -match "Windows")) {
    $HostOS = "Windows"
    $HSTImagerExecutableName = "Hst.imager.exe"
}
elseif ($IsLinux) {
    $HostOS = "Linux"
    $HSTImagerExecutableName = "hst.imager"
}
elseif ($IsMacOS) {
    $HostOS = "MacOS"
    $HSTImagerExecutableName = "hst.imager"
}
else {
    $HostOS = "Unknown"
    $HSTImagerExecutableName = "Hst.imager"
}

# Check for Administrative/Root privileges
# 1. ESCALATION TO ADMIN/ROOT
$IsAdmin = $false
# Robust Windows Check
if ($IsWindows -or ($null -eq $IsWindows -and $env:OS -match "Windows")) {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $IsAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
} else {
    $IsAdmin = (id -u) -eq 0
}

if (-not $IsAdmin) {
    Write-Host "Not running as Admin. Attempting to escalate..." -ForegroundColor Yellow
    
    # Check if we are running as a file or just pasted code
    if ($PSCommandPath) {        
        $ArgList = "-NoProfile -ExecutionPolicy Bypass -File `"`"$PSCommandPath`"`""
        if ($IsWindows -or ($null -eq $IsWindows)) {
            try {
                # Launch a NEW powershell window as Admin
                Start-Process powershell.exe -ArgumentList $ArgList -Verb RunAs -ErrorAction Stop
                exit
            } catch {
                Write-Host "Failed to elevate. Please right-click and 'Run as Administrator'." -ForegroundColor Red
                Read-Host "Press Enter to exit"
                exit
            }
        } else {
            Start-Process sudo -ArgumentList "pwsh $ArgList"
            exit
        }
    } else {
        Write-Error "Script must be saved as a .ps1 file to auto-escalate."
        Read-Host "Press Enter to exit"
        exit
    }
}

Write-host "AGS PiStorm Image Generator"



Write-Host "Running on $HostOS"

# Validation loop
$PathValid = $false
while (-not $PathValid) {
    $HSTImagerLocation = Read-Host -Prompt "Provide the folder with HST Imager installed"
    
    
    # Remove quotes if present
    $HSTImagerLocation = $HSTImagerLocation.Trim('"')

    $HSTImagerLocation = $HSTImagerLocation.Trim('"').TrimEnd('\').TrimEnd('/')



    if (Test-Path -Path $HSTImagerLocation -PathType Container) {
        $FullHSTImagerPath = Join-Path -Path $HSTImagerLocation -ChildPath $HSTImagerExecutableName
        
        if (Test-Path -Path $FullHSTImagerPath -PathType Leaf) {
            $PathValid = $true
            Write-Host "Success: Found $FullHSTImagerPath" -ForegroundColor Green
        }
        else {
            Write-Warning "Folder found, but $HSTImagerExecutableName was not found inside."
        }
    }
    else {
        Write-Warning "The directory '$HSTImagerLocation' does not exist."
    }
}

Write-Host "`nListing disks via $HSTImagerExecutableName..." -ForegroundColor Green
Write-Host "Identify the disk you wish to use to write the image. Note this disk will be erased!"

$DiskList = & $FullHSTImagerPath list
$DiskList # Display the list to the user

$DiskValid = $false
while (-not $DiskValid) {
    $DisktoUse = Read-Host "Which disk number do you wish to use? This should be a single number. For example if you see `"\disk6`" then enter `"6`" (without the quote marks)"

    # 1. Ensure input is not empty and is a digit
    if ($DisktoUse -match '^\d+$') {
        
        # 2. Check if the disk number exists in the Hst.imager output
        # We look for the pattern "\disk[number]" or "disk [number]" in the text
        if ($DiskList -match "\\disk$DisktoUse\b" -or $DiskList -match "disk $DisktoUse\b") {
            $DiskValid = $true
            Write-Host "Disk $DisktoUse selected and verified." -ForegroundColor Green
        }
        else {
            Write-Warning "Disk number '$DisktoUse' was not found in the list above. Please check the number and try again."
        }
    }
    else {
        Write-Warning "Invalid input. Please enter a single numeric value only."
    }

}

# Define the list of required files/folders for the AGS Image source
$RequiredFiles = @(
    "AGS_Drive.hdf", "Emulators.hdf", "Emulators2.hdf", "Games.hdf", 
    "Media.hdf", "Music.hdf", "Premium.hdf", "WHD_Demos.hdf", 
    "WHD_Games.hdf", "Work.hdf", "Workbench.hdf"
)
$RequiredDir = "SHARED"

# Validation loop for the AGS Source Folder
$SourceValid = $false
while (-not $SourceValid) {
    $AGSSourceLocation = Read-Host -Prompt "Provide the folder containing your AGS HDF files"
    $AGSSourceLocation = $AGSSourceLocation.Trim('"')
    $AGSSourceLocation = $AGSSourceLocation.Trim('"').TrimEnd('\')
    
    if (Test-Path -Path $AGSSourceLocation -PathType Container) {
        $MissingItems = @()

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

        if ($MissingItems.Count -eq 0) {
            $SourceValid = $true
            Write-Host "Success: All required files and folders found in $AGSSourceLocation" -ForegroundColor Green
        }
        else {
            Write-Warning "The folder is missing the following required components:"
            $MissingItems | ForEach-Object { Write-Host " - $_" -ForegroundColor Red }
        }
    }
    else {
        Write-Warning "The directory '$AGSSourceLocation' does not exist."
    }
}

# 1. Capture Kickstart ROM Path
$ROMValid = $false
while (-not $ROMValid) {
    $FilepathtoKickstartROM = Read-Host -Prompt "Provide the full path to your Kickstart ROM file"
    $FilepathtoKickstartROM = $FilepathtoKickstartROM.Trim('"')

    if (Test-Path -Path $FilepathtoKickstartROM -PathType Leaf) {
        $ROMValid = $true
    } else {
        Write-Warning "File not found. Please provide a valid path to the Kickstart ROM."
    }
}

# Creates a 'temp' folder in the script's current directory

# If $PSScriptRoot is empty (not running from a file), use the current working directory ($PWD)
$BaseDir = if ($PSScriptRoot) { $PSScriptRoot } else { $PWD }
$FileSystemFolder = (Get-Item (Join-Path -Path $BaseDir -ChildPath "..\FileSystem")).FullName

$TempFolderPath = Join-Path -Path $BaseDir -ChildPath "temp"
if (-not (Test-Path -Path $TempFolderPath)) {
    New-Item -ItemType Directory -Path $TempFolderPath | Out-Null
    Write-Host "Created temporary folder: $TempFolderPath" -ForegroundColor Cyan
}

# 3. Define Output Script Path
$ScriptOutputFile = Join-Path -Path $TempFolderPath -ChildPath "hst_commands.txt"

# 4. Generate the Text File Content
# Injected variables: $TempFolderPath, $AGSSourceLocation, $DisktoUse, $FilepathtoKickstartROM
$ScriptContent = @"
blank "$TempFolderPath\Clean.vhd" 10mb
write "$TempFolderPath\Clean.vhd" \disk$DisktoUse --skip-unused-sectors FALSE
mbr init \disk$DisktoUse
mbr part add \disk$DisktoUse 0xb 1073741824 --start-sector 2048
mbr part format \disk$DisktoUse 1 EMU68BOOT
mbr part add \disk$DisktoUse 0x76 58gb --start-sector 2099200
rdb init \disk$DisktoUse\mbr\2
rdb filesystem add \disk$DisktoUse\mbr\2 "$FileSystemFolder\pfs3aio" PFS3
rdb part add "\disk$DisktoUse\mbr\2" DH0 PFS3 1gb --buffers 300 --max-transfer 0xffffff --mask 0x7ffffffe --no-mount False --bootable True --boot-priority 1
rdb part format "\disk$DisktoUse\mbr\2" 1 Workbench
rdb part add "\disk$DisktoUse\mbr\2" DH1 PFS3 2gb --buffers 300 --max-transfer 0xffffff --mask 0x7ffffffe --no-mount False --bootable False --boot-priority 99
rdb part format "\disk$DisktoUse\mbr\2" 2 Work
rdb part add "\disk$DisktoUse\mbr\2" DH2 PFS3 4gb --buffers 300 --max-transfer 0xffffff --mask 0x7ffffffe --no-mount False --bootable False --boot-priority 99
rdb part format "\disk$DisktoUse\mbr\2" 3 Music
rdb part add "\disk$DisktoUse\mbr\2" DH3 PFS3 4gb --buffers 300 --max-transfer 0xffffff --mask 0x7ffffffe --no-mount False --bootable False --boot-priority 99
rdb part format "\disk$DisktoUse\mbr\2" 4 Media
rdb part add "\disk$DisktoUse\mbr\2" DH4 PFS3 4gb --buffers 300 --max-transfer 0xffffff --mask 0x7ffffffe --no-mount False --bootable False --boot-priority 99
rdb part format "\disk$DisktoUse\mbr\2" 5 AGS_Drive
rdb part add "\disk$DisktoUse\mbr\2" DH5 PFS3 8gb --buffers 300 --max-transfer 0xffffff --mask 0x7ffffffe --no-mount False --bootable False --boot-priority 99
rdb part format "\disk$DisktoUse\mbr\2" 6 Games
rdb part add "\disk$DisktoUse\mbr\2" DH6 PFS3 8gb --buffers 300 --max-transfer 0xffffff --mask 0x7ffffffe --no-mount False --bootable False --boot-priority 99
rdb part format "\disk$DisktoUse\mbr\2" 7 Premium
rdb part add "\disk$DisktoUse\mbr\2" DH7 PFS3 4gb --buffers 300 --max-transfer 0xffffff --mask 0x7ffffffe --no-mount False --bootable False --boot-priority 99
rdb part format "\disk$DisktoUse\mbr\2" 8 Emulators1
rdb part add "\disk$DisktoUse\mbr\2" DH13 PFS3 4gb --buffers 300 --max-transfer 0xffffff --mask 0x7ffffffe --no-mount False --bootable False --boot-priority 99
rdb part format "\disk$DisktoUse\mbr\2" 9 WHD_Demos
rdb part add "\disk$DisktoUse\mbr\2" DH14 PFS3 8gb --buffers 300 --max-transfer 0xffffff --mask 0x7ffffffe --no-mount False --bootable False --boot-priority 99
rdb part format "\disk$DisktoUse\mbr\2" 10 WHD_Games
rdb part add "\disk$DisktoUse\mbr\2" DH15 PFS3 8gb --buffers 300 --max-transfer 0xffffff --mask 0x7ffffffe --no-mount False --bootable False --boot-priority 99
rdb part format "\disk$DisktoUse\mbr\2" 11 Emulators2
fs c "$AGSSourceLocation\Workbench.hdf\rdb\1" "\disk$DisktoUse\MBR\2\rdb\DH0\" -r -md -q
fs c "$AGSSourceLocation\Work.hdf\rdb\1" "\disk$DisktoUse\MBR\2\rdb\DH1\" -r -md -q
fs c "$AGSSourceLocation\Music.hdf\rdb\1" "\disk$DisktoUse\MBR\2\rdb\DH2\" -r -md -q
fs c "$AGSSourceLocation\Media.hdf\rdb\1" "\disk$DisktoUse\MBR\2\rdb\DH3\" -r -md -q
fs c "$AGSSourceLocation\AGS_Drive.hdf\rdb\1" "\disk$DisktoUse\MBR\2\rdb\DH4\" -r -md -q
fs c "$AGSSourceLocation\Games.hdf\rdb\1" "\disk$DisktoUse\MBR\2\rdb\DH5\" -r -md -q
fs c "$AGSSourceLocation\Premium.hdf\rdb\1" "\disk$DisktoUse\MBR\2\rdb\DH6\" -r -md -q
fs c "$AGSSourceLocation\Emulators.hdf\rdb\1" "\disk$DisktoUse\MBR\2\rdb\DH7\" -r -md -q
fs c "$AGSSourceLocation\WHD_Demos.hdf\rdb\1" "\disk$DisktoUse\MBR\2\rdb\DH13\" -r -md -q
fs c "$AGSSourceLocation\WHD_Games.hdf\rdb\1" "\disk$DisktoUse\MBR\2\rdb\DH14\" -r -md -q
fs c "$AGSSourceLocation\Emulators2.hdf\rdb\1" "\disk$DisktoUse\MBR\2\rdb\DH15\" -r -md -q
fs c "$FilepathtoKickstartROM" \disk$DisktoUse\MBR\1\kick.rom 
fs c "$TempFolderPath\FilestoAdd\Emu68Boot" \disk$DisktoUse\MBR\1\ -r -md -q
fs mkdir \disk$DisktoUse\MBR\1\SHARED\SaveGames
fs c "\disk$DisktoUse\MBR\2\rdb\DH0\s\startup-sequence" "\disk$DisktoUse\MBR\2\rdb\DH0\s\startup-sequence.bak"
fs c "\disk$DisktoUse\MBR\2\rdb\DH0\s\user-startup" "\disk$DisktoUse\MBR\2\rdb\DH0\s\user-startup.bak"
fs c "\disk$DisktoUse\MBR\2\rdb\DH0\s\AGS-Stuff" "\disk$DisktoUse\MBR\2\rdb\DH0\s\AGS-Stuff.bak"
fs c \disk$DisktoUse\MBR\2\rdb\DH0\c\whdload \disk$DisktoUse\MBR\2\rdb\DH0\c\whdload.ori
fs c "$TempFolderPath\FilestoAdd\Workbench" \disk$DisktoUse\MBR\2\rdb\DH0 -r -md -q -f
fs c "$TempFolderPath\FilestoAdd\AGS_Drive" \disk$DisktoUse\MBR\2\rdb\DH4 -r -md -q -f
fs c "\disk$DisktoUse\MBR\2\rdb\DH0\Devs\monitors\HD720*" "\disk$DisktoUse\MBR\2\rdb\DH0\storage\monitors"
fs c "\disk$DisktoUse\MBR\2\rdb\DH0\Devs\monitors\HighGFX*" "\disk$DisktoUse\MBR\2\rdb\DH0\storage\monitors"
fs c "\disk$DisktoUse\MBR\2\rdb\DH0\Devs\monitors\SuperPlus*" "\disk$DisktoUse\MBR\2\rdb\DH0\storage\monitors"
fs c "\disk$DisktoUse\MBR\2\rdb\DH0\Devs\monitors\Xtreme*" "\disk$DisktoUse\MBR\2\rdb\DH0\storage\monitors"
"@

# 5. Write to File
$ScriptContent | Out-File -FilePath $ScriptOutputFile -Encoding utf8 -Force
Write-Host "HST Imager script generated at: $ScriptOutputFile" -ForegroundColor Green

# 6. FINAL CONFIRMATION
Write-Host "`n====================================================" -ForegroundColor Yellow
Write-Host "            READY TO WRITE TO DISK" -ForegroundColor Yellow
Write-Host "====================================================" -ForegroundColor Yellow
Write-Host "Target Disk:       \disk$DisktoUse" -ForegroundColor Red
Write-Host "Source Folder:     $AGSSourceLocation"
Write-Host "Kickstart ROM:     $FilepathtoKickstartROM"
Write-Host "Command File:      $ScriptOutputFile"
Write-Host "----------------------------------------------------"
Write-Host "WARNING: This will ERASE all data on \disk$DisktoUse." -ForegroundColor Red
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