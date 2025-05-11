<#
 .SYNOPSIS
  Estimates the required Datastore size for a virtual machine (VM) after changing its memory allocation.

 .DESCRIPTION
  This script calculates the required Datastore size based on the intended memory allocation and 
  occupancy rate. If the VM does not exist (indicated by the -Offline switch), the calculation is 
  based on user-specified disk size and memory size. However, the -Offline mode can also be used 
  for existing VMs when estimating storage requirements without connecting to a vCenter server.

  Version: 1.1.2

  The script supports both connected and offline scenarios. For connected scenarios, it retrieves 
  details such as current memory, Datastore name, and disk usage from a vCenter server. For offline 
  scenarios (using -Offline), the user provides the necessary inputs without requiring a connection 
  to a vSphere environment.

  The calculation uses the formula:
    (required size) = (disk size + new memory size) / (occupancy rate)

  Notes:
  - The script does not account for temporary files (e.g., log files and snapshots), making it 
    suitable for high-level storage planning.
  - Default Datastore occupancy rate is 80% if not provided by the user.
  - Adjust the "vCenter connection info" section for your environment. These settings are ignored in -Offline mode.

 .PARAMETER MemorySize
  (Alias -m) Mandatory. Intended future size of memory in GB.

 .PARAMETER VmName
  (Alias -n) Mandatory unless -Offline is specified. Specifies the VM name.

 .PARAMETER OccupancyRate
  (Alias -r) Optional. A number between 0 and 1 (e.g., 0.75) representing the desired maximum Datastore 
  occupancy rate. Defaults to 0.8 if not provided.

 .PARAMETER Offline
  Switch. Indicates that the calculation will be performed without connecting to a vCenter server. 
  Must be used with -DiskSize.

 .PARAMETER DiskSize
  (Alias -d) Mandatory when -Offline is specified. Specifies the total size of VM disks in GB.

 .EXAMPLE
  # Calculate the required Datastore size for an existing VM after expanding its memory to 16GB.
  # Requires a vCenter connection.
  .\CalcVmDsSizeReq.ps1 -MemorySize 16 -VmName VM001

 .EXAMPLE
  # Estimate the Datastore size for an imaginary VM with 10GB of memory and a total disk size of 200GB, 
  # assuming the total size (disk + memory swap) will fill 85% of the Datastore.
  # Does not require a vCenter connection. You can optionally add '-VmName NewVM002' for clarity or as a reminder.
  .\CalcVmDsSizeReq.ps1 -MemorySize 10 -Offline -DiskSize 200 -OccupancyRate 0.85
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
  [switch]$Offline,

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
    $connRetry = 2
    $connRetryInterval = 2

    # Arguments validation
    if ($PSBoundParameters.Count -eq 0) {
        Get-Help $MyInvocation.InvocationName
        exit
    }

    if (-not $PSBoundParameters.ContainsKey('MemorySize')) {
        throw "Error: -MemorySize is a mandatory parameter and must be specified."
    }

    if ($PSBoundParameters.ContainsKey('Offline')) {
        if (-not $PSBoundParameters.ContainsKey('DiskSize')) {
            throw "Error: -DiskSize must be specified when using -Offline."
        }
    } else {
        if (-not $PSBoundParameters.ContainsKey('VmName')) {
            throw "Error: -VmName is a mandatory parameter unless -Offline is specified."
        }
    }

    if ($PSBoundParameters.ContainsKey('OccupancyRate')) {
        if ($OccupancyRate -le 0 -or $OccupancyRate -ge 1) {
            throw "Error: -OccupancyRate must be a number greater than 0 and less than 1 (e.g., 0.75)."
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

    if (! $Offline) {
        if (-not (Get-Module VMware.VimAutomation.Core)) {
            Write-Output "Loading VMware PowerCLI module, this may take a while..."
            Import-Module VMware.VimAutomation.Core -ErrorAction SilentlyContinue
        }

        VIConnect

        $vm = Get-VM -Name $VmName
        if ($null -eq $vm) {
            Write-Host "Error, No such Virtual Machine $VmName" -ForegroundColor Red
            Write-Host "Use -Offline option if you are trying estimation for a VM not yet deployed." -ForegroundColor Red
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

        Disconnect-VIServer -Server $vcserver -Confirm:$false
    }
    else {
        if (! $VmName) { $VmName = "N/A" }

        $currentMemoryGB = 0
        $currentDisksGB = $DiskSize
        $currentDSName = "N/A"
        $currentCapacityGB = 0
    }

    # Estimate total required DS size with new memory
    $futureRequiredGB = [math]::Round(($currentDisksGB + $MemorySize) / $OccupancyRate, 2)
    $increaseNeededGB = [math]::Round($futureRequiredGB - $currentCapacityGB, 2)

    # Reporting
    Write-Host "-------------------------------"
    Write-Host "VM Name              : $VmName"
    Write-Host "Current Memory Size  : $currentMemoryGB GB"
    Write-Host "New Memory Size      : $MemorySize GB"
    if ($Offline) {
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
