<#
 .SYNOPSIS
  Exports list of VMs to a CSV file.

 .DESCRIPTION
  Exports list of Virtual Machines to a CSV file.
  Related configuration files: settings.ps1
  Version: 0.8

 .PARAMETER OutPath
  Path and name of output file. If not specified, <script_path>\vmout.txt
  is used. If EsxHost argument is specified too, filename defaults to 
  vmout-<EsxHost>.txt.

 .PARAMETER EsxHost
  Name of ESX Host where VMs reside. If not specified, all the VMs on all
  Hosts governed by this vCenter will be listed. Do note that this must
  be the name which vCenter recognizes the Host as.

 .PARAMETER Legacy
  If specified and $vcpasswd is not set in settings.ps1, the script tries to
  connect to vCenter using legacy VICredentialStore mechanism. Otherwise,
  modern SecretStore / VISecret is assumed.
  Instead of specifying this switch on every run, you can set the $Legacy
  parameter in settings.ps1 to $true to use legacy mode by default.

 .PARAMETER UpdatePassword
  If no valid credential was found in non-plain mode connection, only at the
  first connection try of the run, script will prompt you the vCenter password.
  If -UpdatePassword is also specified, the new credential will be saved
  to the correspondent credential store on successful connection.

 .PARAMETER Sort
  (Alias -s) Sort CSV by EsxiHost and VMName. Don't mind "Processing" console
  messages never be sorted though.
#>
[CmdletBinding()]
Param(
  [Parameter(Position=0)]
  [string]$OutPath,
  [Parameter(Position=1)]
  [string]$EsxHost,
  [Parameter()]
  [switch]$Legacy,
  [Parameter()]
  [switch]$UpdatePassword,
  [Parameter()]
  [Alias("s")]
  [switch]$Sort
)

$scriptdir = Split-Path -Path $myInvocation.MyCommand.Path -Parent
if (-Not (Test-Path "$scriptdir\settings.ps1")) {
    Write-Error "Can't read base setting file $scriptdir\settings.ps1"
    Exit 254
}
Write-Verbose -Message "Reading base settings from $scriptdir\settings.ps1"
. $scriptdir\settings.ps1

# Resolve Legacy mode between script switch and settings file
$useLegacy = $false
# Respect the script switch primarily even when '-Legacy:$false' is specified
if ($PSBoundParameters.ContainsKey('Legacy')) {
    $useLegacy = [bool]$Legacy
} elseif ($script:Legacy) {
    $useLegacy = [bool]$script:Legacy
}

if ($OutPath) {
    $PathOut = $OutPath
} else {
    if ($EsxHost) {
        $PathOut = $scriptdir + "\vmout-" + $EsxHost + ".txt"
    } else {
        $PathOut = $scriptdir + "\vmout.txt"
    }
} 

if (-Not (Test-Path "$scriptdir\VIConnect.ps1")) {
    Write-Error "Can't read function library file $scriptdir\VIConnect.ps1"
    Exit 254
}
Write-Verbose -Message "Reading function library file $scriptdir\VIConnect.ps1"
. $scriptdir\VIConnect.ps1

# Pass the update flag to the connection library (default: do not update)
if ($UpdatePassword) {
    $script:UpdatePassword = $true
} else {
    $script:UpdatePassword = $false
}

Function List-VM {
    PROCESS {
		Write-Output "Gathering VM Information"
		$Report = @()

		foreach ($vm in Get-VM) {
			$VMHostName = $VM.VMHost.Name

			if ($script:EsxHost) {
				if ($VMHostName -ne $script:EsxHost) {
					continue
				}
			}

			Write-Output ("Processing " + $vm.Name + "`ton " + $VMHostName)

			#All global info here
			$vNicInfo = $vm |Get-NetworkAdapter |Sort -Property @{Expression={(-split $_.Name)[2]}}

			#Hardware Version
			$rawver = $vm.HardwareVersion
			#$rawver = $vm.ExtensionData.config.Version
			$vmversion = $rawver.trimstart("vmx-")

			#FQDN - AD domain name
			$OriginalHostName = $vm.ExtensionData.Guest.Hostname

			#All hardisk individual capacity
			$TotalHDDs = $vm.ProvisionedSpaceGB -as [int]

			#Associated Datastores
			#$datastore = ($(Get-Datastore -vm $vm) -split ", ") -join ","
			$dslist = @()
			$vm.DatastoreIdList |Foreach { $dslist += (Get-View -id $_).Name }
			$datastore = $dslist -join ","

			#VM Macaddress
			$maclist = @()
			$vNicInfo |Foreach { $maclist += $_.MacAddress }
			$mac = $maclist -join ","

			#vNic Type
			$nictypelist = @()
			$vNicInfo |Foreach { $nictypelist += $_.Type }
			$vnic = $nictypelist -join ","

			#Virtual Port group Info
			$pglist = @()
			$vNicInfo |Foreach { $pglist += $_.NetworkName }
			$portgroup = $pglist -join ","

			#IP Address
			#$IPs = $vm.Guest.IPAddress -join "," #$vm.Guest.IPAddres[0] <#it will take first ip#>
			$iplist = @()
			Foreach ($nic in $vNicInfo) { $iplist += ($vm.Guest.Nics |Where{$_.Device.Name -eq $nic.Name}).IPAddress }
			$IPs = $iplist -join ","

			$Vmresult = New-Object PSObject
			$Vmresult | add-member -MemberType NoteProperty -Name "EsxiHost" -Value $VM.VMHost
			$Vmresult | add-member -MemberType NoteProperty -Name "VMName" -Value $vm.Name
			$Vmresult | add-member -MemberType NoteProperty -Name "PowerState" -Value $vm.PowerState
			$Vmresult | add-member -MemberType NoteProperty -Name "Total-HDD(GB)" -Value $TotalHDDs
			$Vmresult | add-member -MemberType NoteProperty -Name "Datastore" -Value $datastore
			$Vmresult | add-member -MemberType NoteProperty -Name "vCPU" -Value $vm.NumCpu
			$Vmresult | Add-Member -MemberType NoteProperty -Name CPUSocket -Value $vm.ExtensionData.config.hardware.NumCPU
			$Vmresult | Add-Member -MemberType NoteProperty -Name Corepersocket -Value $vm.ExtensionData.config.hardware.NumCoresPerSocket
			$Vmresult | add-member -MemberType NoteProperty -Name "RAM(GB)" -Value $vm.MemoryGB
			$Vmresult | add-member -MemberType NoteProperty -Name "Hardware Version" -Value $vmversion
			$Vmresult | add-member -MemberType NoteProperty -Name "Setting-OS" -Value $VM.ExtensionData.summary.config.guestfullname
			$Vmresult | add-member -MemberType NoteProperty -Name "Installed-OS" -Value $vm.guest.OSFullName
			$Vmresult | add-member -MemberType NoteProperty -Name "Hostname" -Value $OriginalHostName
			$Vmresult | add-member -MemberType NoteProperty -Name "vNic" -Value $vnic
			$Vmresult | add-member -MemberType NoteProperty -Name "MacAddress" -Value $mac
			$Vmresult | add-member -MemberType NoteProperty -Name "Portgroup" -Value $portgroup
			$Vmresult | add-member -MemberType NoteProperty -Name "IP Address" -Value $IPs

			$Report += $Vmresult
		}

		Write-Output "Output file: $PathOut"
		if ($Sort) {
			$report | Sort EsxiHost,VMName | Export-Csv -Path $PathOut -NoTypeInformation -Encoding default
		} else {
			$report | Export-Csv -Path $PathOut -NoTypeInformation -Encoding default
		}
    }
}

if (-Not (get-module VMware.VimAutomation.Core)) {
    Write-Output "Loading vSphere PowerCLI. This may take a while..."
    Import-Module VMware.VimAutomation.Core -ErrorAction SilentlyContinue
}

if ($useLegacy) {
    VIConnectLegacy
} else {
    VIConnect
}

List-VM

Write-Output "Disconnecting from $vcserver"
Disconnect-VIServer -Server $vcserver -Confirm:$false
