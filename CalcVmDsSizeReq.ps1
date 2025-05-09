<#
 .SYNOPSIS
  Calculates required datastore size for a VM after increasing its memory.

 .DESCRIPTION
  This script connects to a vCenter server, locates a specified virtual machine, 
  and calculates the required datastore size based on the intended memory 
  expansion and a target datastore occupancy rate. It assumes the VM shares a 
  dedicated datastore with no other VMs, and uses the formula:  
   (required size) = (disk size + new memory size) / (occupancy rate).
  
  The script does not take into account temporary files such as VM swap files, 
  and is intended for high-level storage planning.  
  Version: 1.1.0
  
  Note: Adjust the values in the "vCenter connection info" section before use, 
  however, those are not used when running in -scratch mode (see below).
  
 .PARAMETER MemorySize
  (Alias -m) Mandatory. Intended future size of memory in GB.

 .PARAMETER VmName
  (Alias -n) Mandatory unless -scratch is specified. The name of VM.

 .PARAMETER OccupancyRate
  (Alias -r) Desired maximum Datastore occupancy rate, which must be a number 
  greater than 0 and less than 1 (e.g., 0.75). This option can be used to 
  override the default value defined in the script.

 .PARAMETER scratch
  Switch option to indicate the VM doesn't exist yet. -DiskSize (below) must 
  be accompanied with it.

 .PARAMETER DiskSize
  (Alias -d) Mandatory when -scratch is used. Specifies sum total of the VM 
  disks in GB. 
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
    # Arguments validation
    if ($PSBoundParameters.Count -eq 0) {
        Get-Help $MyInvocation.InvocationName
        exit
    }

    if (-not $PSBoundParameters.ContainsKey('DNPath')) {
        if ($PSBoundParameters.ContainsKey('DCDepth') -and -not $PSBoundParameters.ContainsKey('DNPrefix')) {
            throw "Error: -DNPrefix must be specified when using -DCDepth."
        }
        if (-not $PSBoundParameters.ContainsKey('DNPrefix')) {
            throw "Error: One of -DNPath or -DNPrefix is required."
        }
    }

    if ($PSBoundParameters.ContainsKey('DNPath') -and ($PSBoundParameters.ContainsKey('DNPrefix') -or $PSBoundParameters.ContainsKey('DCDepth'))) {
        throw "Error: -DNPath cannot be used together with -DNPrefix or -DCDepth."
    }


    # Desired maximum Datastore occupancy rate (e.g., 80%)
    $storeOccupancyRate = 0.8

    if ($null -eq $OccupancyRate -or 0 -eq $OccupancyRate) {
        $OccupancyRate = $storeOccupancyRate
    } elseif ($OccupancyRate -le 0 -or $OccupancyRate -ge 1) {
        Write-Host "OccupancyRate must be a number greater than 0 and less than 1 (e.g., 0.8)" -ForegroundColor Red
        Exit 1
    }

    # vCenter connection info
    $vcserver = 'vcsa1.mydomain.com'
    $vcport = 443
    #$vcuser = 'Administrator@vsphere.local'
    #$vcpasswd = 'DonKnow'
    $connRetry = 1
    $connRetryInterval = 2
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
        $datastore = ($vm | Get-Datastore)

        # Get current memory and storage specifications
        $currentMemoryGB = $vm.MemoryGB
        $currentDisksGB = ($vm | Get-HardDisk | Measure-Object -Property CapacityGB -Sum).Sum
        $currentCapacityGB = [math]::Round($datastore.CapacityGB, 2)

        # Estimate total required DS size with new memory
        $futureRequiredGB = [math]::Round(($currentDisksGB + $MemorySize) / $OccupancyRate, 2)
        $increaseNeededGB = [math]::Round($futureRequiredGB - $currentCapacityGB, 2)

        Disconnect-VIServer -Server $vcserver -Confirm:$false
    }
    else {
        $vm = "N/A"
        $datastore = "N/A"

        $currentMemoryGB = 0
        $currentDisksGB = $DiskSize
        $currentCapacityGB = 0

        # Estimate total required DS size with new memory
        $futureRequiredGB = [math]::Round(($DiskSize + $MemorySize) / $OccupancyRate, 2)
        $increaseNeededGB = [math]::Round($futureRequiredGB - $currentCapacityGB, 2)
    }

    # Reporting
    Write-Host "------------------------"
    Write-Host "VM Name              : $VmName"
    Write-Host "Current Memory Size  : $currentMemoryGB GB"
    Write-Host "New Memory Size      : $MemorySize GB"
    if ($scratch) {
        Write-Host "New Disk Size        : $currentDisksGB GB"
    } else {
        Write-Host "Current Disk Size    : $currentDisksGB GB"
    }
    Write-Host "Target Occupancy     : $($OccupancyRate * 100)%"
    Write-Host "Current DS Size      : $currentCapacityGB GB"
    Write-Host "Future DS Size Req.  : $futureRequiredGB GB"
    Write-Host "Additional Space Req.: $increaseNeededGB GB"
    Write-Host "------------------------"

}

