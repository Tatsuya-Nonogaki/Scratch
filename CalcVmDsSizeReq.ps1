<#
 .SYNOPSIS
  Estimates the required datastore size for a virtual machine (VM) after changing its memory allocation.

 .DESCRIPTION
  This script calculates the required datastore size based on the intended memory allocation and 
  occupancy rate. If the VM does not exist yet (indicated by the -scratch switch), the calculation is 
  based on user-specified disk size and memory size.
  Version: 1.1.0

  The script supports both existing VMs (by connecting to a vCenter server) and hypothetical scenarios 
  without requiring a working vSphere environment. For existing VMs, it retrieves details such as current 
  memory, Datastore name and disk usage. For non-existent VMs (using -scratch), the user provides the 
  necessary inputs for the calculation.

  The calculation uses the formula:
    (required size) = (disk size + new memory size) / (occupancy rate)

  Notes:
  - The script does not account for temporary files (e.g., VM swap files), making it suitable for high-level storage planning.
  - Default datastore occupancy rate is 80% if not provided by the user.
  - Adjust the "vCenter connection info" section for your environment. These settings are ignored in -scratch mode.

 .PARAMETER MemorySize
  (Alias -m) Mandatory. Intended future size of memory in GB.

 .PARAMETER VmName
  (Alias -n) Mandatory unless -scratch is specified. Specifies the VM name.

 .PARAMETER OccupancyRate
  (Alias -r) Optional. A number between 0 and 1 (e.g., 0.75) representing the desired maximum datastore 
  occupancy rate. Defaults to 0.8 if not provided.

 .PARAMETER scratch
  Switch. Indicates that the VM does not exist yet. Must be used with -DiskSize.

 .PARAMETER DiskSize
  (Alias -d) Mandatory when -scratch is specified. Specifies the total size of VM disks in GB.
#>
[CmdletBinding()]
Param(
  [Parameter(Position=0)]
  [Alias("m")]
  [int]$MemorySize,

  [Parameter(Position=1)]
  [Alias("n")]
  [string]$VmName,

  [Parameter()]
  [Alias("r")]
  [double]$OccupancyRate,

  [Parameter()]
  [switch]$scratch,

  [Parameter()]
  [Alias("d")]
  [int]$DiskSize
)

begin {
    # Desired maximum Datastore occupancy rate (e.g., 80%)
    $storeOccupancyRate = 0.8
    
    # vCenter connection info
    $vcserver = 'vcsa1.mydomain.com'
    $vcport = 443
    #$vcuser = 'Administrator@vsphere.local'
    #$vcpasswd = 'DonKnow'
    $connRetry = 1
    $connRetryInterval = 2

    # Arguments validation
    if ($PSBoundParameters.Count -eq 0) {
        Get-Help $MyInvocation.InvocationName
        exit
    }

    # Validate MemorySize (Mandatory for all cases)
    if (-not $PSBoundParameters.ContainsKey('MemorySize')) {
        throw "Error: -MemorySize is a mandatory parameter and must be specified."
    }

    if ($PSBoundParameters.ContainsKey('scratch')) {
        if (-not $PSBoundParameters.ContainsKey('DiskSize')) {
            throw "Error: -DiskSize must be specified when using -scratch."
        }
    } else {
        if (-not $PSBoundParameters.ContainsKey('VmName')) {
            throw "Error: -VmName is a mandatory parameter unless -scratch is specified."
        }
    }

    if ($PSBoundParameters.ContainsKey('OccupancyRate')) {
        if ($OccupancyRate -le 0 -or $OccupancyRate -ge 1) {
            throw "Error: -OccupancyRate must be a number greater than 0 and less than 1 (e.g., 0.8)."
        }
    } else {
        $OccupancyRate = $storeOccupancyRate
    }
}

process {

    Function VIConnect {
        PROCESS {
            For ($i = 1; $i -le $connRetry; $i++) {
                if ((!$vcuser -Or !$vcpasswd) -Or ($vcuser.length -lt 1 -Or $vcpasswd.length -lt 1)) {
                    Write-Output "Connect-VIServer $vcserver -Port $vcport -Force"
                    Connect-VIServer $vcserver -Port $vcport -Force -WarningAction SilentlyContinue -ErrorAction Continue -ErrorVariable myErr
                } else {
                    Write-Output "Connect-VIServer $vcserver -Port $vcport -User $vcuser -Password ******** -Force"
                    Connect-VIServer $vcserver -Port $vcport -User $vcuser -Password $vcpasswd -Force -WarningAction SilentlyContinue -ErrorAction Continue -ErrorVariable myErr
                }
                if ($?) { break }

                if ($i -eq $connRetry) {
                    Write-Host "Connection attempts exceeded retry limit" -ForegroundColor Red
                    Exit 1
                }

                Write-Host "Retrying in $connRetryInterval seconds...`r`n" -ForegroundColor Yellow
                Start-Sleep -s $connRetryInterval
            }
        }
    }

    if (! $scratch) {
        if (-not (Get-Module VMware.VimAutomation.Core)) {
            Write-Output "Loading VMware PowerCLI module, this may take a while..."
            Import-Module VMware.VimAutomation.Core -ErrorAction SilentlyContinue
        }

        VIConnect

        $vm = Get-VM -Name $VmName
        if ($null -eq $vm) {
            Write-Host "Error, No such Virtual Machine $VmName" -ForegroundColor Red
            Disconnect-VIServer -Server $vcserver -Confirm:$false
            Exit 1
        }

        $datastore = ($vm | Get-Datastore)
        if ($null -eq $datastore) {
            Write-Host "Error ocurred while retrieving Datastore information" -ForegroundColor Red
            Disconnect-VIServer -Server $vcserver -Confirm:$false
            Exit 1
        }

        # Get current memory and storage specifications
        $currentMemoryGB = $vm.MemoryGB
        $currentDisksGB = ($vm | Get-HardDisk | Measure-Object -Property CapacityGB -Sum).Sum
        $currentDSName = $($datastore.Name)
        $currentCapacityGB = [math]::Round($datastore.CapacityGB, 2)

        # Estimate total required DS size with new memory
        $futureRequiredGB = [math]::Round(($currentDisksGB + $MemorySize) / $OccupancyRate, 2)
        $increaseNeededGB = [math]::Round($futureRequiredGB - $currentCapacityGB, 2)

        Disconnect-VIServer -Server $vcserver -Confirm:$false
    }
    else {
        if (! $VmName) { $VmName = "N/A" }
        $datastore = "N/A"

        $currentMemoryGB = 0
        $currentDisksGB = $DiskSize
        $currentDSName = "N/A"
        $currentCapacityGB = 0

        # Estimate total required DS size with new memory
        $futureRequiredGB = [math]::Round(($DiskSize + $MemorySize) / $OccupancyRate, 2)
        $increaseNeededGB = [math]::Round($futureRequiredGB - $currentCapacityGB, 2)
    }

    # Reporting
    Write-Host "-------------------------------"
    Write-Host "VM Name              : $VmName"
    Write-Host "Current Memory Size  : $currentMemoryGB GB"
    Write-Host "New Memory Size      : $MemorySize GB"
    if ($scratch) {
        Write-Host "New Disk Size        : $currentDisksGB GB"
    } else {
        Write-Host "Current Disk Size    : $currentDisksGB GB"
    }
    Write-Host "Target Occupancy     : $($OccupancyRate * 100)%"
    Write-Host "Current Datastore    : $currentDSName"
    Write-Host "Current DS Size      : $currentCapacityGB GB"
    Write-Host "Future DS Size Req.  : $futureRequiredGB GB"
    Write-Host "Additional Space Req.: $increaseNeededGB GB"
    Write-Host "-------------------------------"

}
