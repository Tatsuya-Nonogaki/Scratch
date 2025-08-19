    # Group Data Import Mode
    if ($groupMode) {
        # Select the group file if not specified
        if (-not $GroupFile) {
            $GroupFile = Select-Input-File -type "group"
        }
        if (-not (Test-Path $GroupFile)) {
            Write-Error "Specified GroupFile does not exist"
            exit 1
        }

        # Warn if looks like a user file
        $groupFileName = Split-Path $GroupFile -Leaf
        if ($groupFileName -match '(?i)(^|[._ -])user([._ -]|s|$)') {
            Write-Host "Warning: The group file name implies it is a user data file." -ForegroundColor Yellow
            $resp = Read-Host "Continue anyway? [Y]/N"
            if ($resp -and $resp -match '^(n|no)$') {
                Write-Host "Aborted by user." -ForegroundColor Yellow
                exit 1
            }
        }

        Write-Host "Group File Path: $GroupFile"
        Write-Log "Group File Path: $GroupFile"
        Import-ADObject -filePath $GroupFile -objectClass "group"
    }

    # User Data Import Mode
    if ($userMode) {
        # Select the user file if not specified
        if (-not $UserFile) {
            $UserFile = Select-Input-File -type "user"
        }
        if (-not (Test-Path $UserFile)) {
            Write-Error "Specified UserFile does not exist"
            exit 1
        }

        # Warn if looks like a group file
        $userFileName = Split-Path $UserFile -Leaf
        if ($userFileName -match '(?i)(^|[._ -])group([._ -]|s|$)') {
            Write-Host "Warning: The user file name implies it is a group data file." -ForegroundColor Yellow
            $resp = Read-Host "Continue anyway? [Y]/N"
            if ($resp -and $resp -match '^(n|no)$') {
                Write-Host "Aborted by user." -ForegroundColor Yellow
                exit 1
            }
        }

        Write-Host "User File Path: $UserFile"
        Write-Log "User File Path: $UserFile"
        Import-ADObject -filePath $UserFile -objectClass "user"
    }

    # Computer Data Import Mode
    if ($computerMode) {
        # Select the computer file if not specified
        if (-not $ComputerFile) {
            $ComputerFile = Select-Input-File -type "computer"
        }
        if (-not (Test-Path $ComputerFile)) {
            Write-Error "Specified ComputerFile does not exist"
            exit 1
        }

        # Warn if looks like a user file
        $groupFileName = Split-Path $GroupFile -Leaf
        if ($groupFileName -match '(?i)(^|[._ -])user([._ -]|s|$)') {
            Write-Host "Warning: The group file name implies it is a user data file." -ForegroundColor Yellow
            $resp = Read-Host "Continue anyway? [Y]/N"
            if ($resp -and $resp -match '^(n|no)$') {
                Write-Host "Aborted by user." -ForegroundColor Yellow
                exit 1
            }
        }

        Write-Host "Computer File Path: $ComputerFile"
        Write-Log "Computer File Path: $ComputerFile"
        Import-ADObject -filePath $ComputerFile -objectClass "computer"
    }

    # Group Fixup/Fixate Mode
    if ($fixGroupMode) {
        # Select the group file if not specified
        if (-not $GroupFile) {
            $GroupFile = Select-Input-File -type "group"
        }
        if (-not (Test-Path $GroupFile)) {
            Write-Error "Specified GroupFile does not exist"
            exit 1
        }

        # Warn if looks like a user file
        $groupFileName = Split-Path $GroupFile -Leaf
        if ($groupFileName -match '(?i)(^|[._ -])user([._ -]|s|$)') {
            Write-Host "Warning: The group file name implies it is a user data file." -ForegroundColor Yellow
            $resp = Read-Host "Continue anyway? [Y]/N"
            if ($resp -and $resp -match '^(n|no)$') {
                Write-Host "Aborted by user." -ForegroundColor Yellow
                exit 1
            }
        }

        Write-Host "Group File Path: $GroupFile"
        Write-Log "Group File Path: $GroupFile"
        Fixup-GroupManagedBy -GroupFile $GroupFile -DNPath $DNPath
    }

