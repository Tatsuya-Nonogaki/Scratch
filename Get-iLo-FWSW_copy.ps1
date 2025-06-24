<#
 .SYNOPSIS
  Obtains iLO Firmware and Software information.

 .DESCRIPTION
  Queries HP iLO Redfish REST API for Firmware and Software, outputs in CSV format.
  Version: 0.1.3.N2

 .PARAMETER iLoIP
  (Alias -i) Mandatory. IP or hostname of the iLO interface.

 .PARAMETER HostName
  (Alias -h) Optional. Name of the host. This is used just to form the output CSV filename, 
  with dots (".") replaced with underscores ("_"). iLoIP will be used instead if omitted.

 .PARAMETER Username
  (Alias -u) Optional. iLO username (default: Administrator).

 .PARAMETER Password
  (Alias -p) Optional. iLO password. If omitted, prompts interactively.
 
 .PARAMETER OutPath
  (Alias -o) Optional. Folder path where you want to save the output CSV.
  Path selection dialog will prompt you to choose, if omitted.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [Alias("i")]
    [string]$iLoIP,

    [Parameter()]
    [Alias("h")]
    [string]$HostName,

    [Parameter()]
    [Alias("u")]
    [string]$Username = "Administrator",

    [Parameter()]
    [Alias("p")]
    [string]$Password,

    [Parameter()]
    [Alias("o")]
    [string]$OutPath
)

$scriptdir = Split-Path -Path $myInvocation.MyCommand.Path -Parent

if (-not $HostName) {
    $HostName = $iLoIP -replace '\.', '_'
}

# Folder selection dialog
function Get-Folder {
    Add-Type -AssemblyName System.Windows.Forms
    $folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
    $folderBrowser.Description = "Select the output folder"
    $folderBrowser.SelectedPath = $scriptdir
    if ($folderBrowser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $selectedPath = $folderBrowser.SelectedPath
        return $selectedPath
    }
    return ""
}

# Determine output folder path
$outputFolderPath = ""
if (-not $OutPath) {
    $outputFolderPath = Get-Folder
} else {
    $outputFolderPath = $OutPath
}
if (-not $outputFolderPath) {
    $outputFolderPath = '.'
}
$outputFolderPath = $outputFolderPath.TrimEnd('\','/')

if (-not (Test-Path -Path $outputFolderPath -PathType Container)) {
    Write-Host "ERROR: Output folder '$outputFolderPath' does not exist." -ForegroundColor Red
    exit 3
}

# Interactive password prompt
if (-not $Password) {
    $SecurePwd = Read-Host -AsSecureString "Enter iLO password"
    $BSTR = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePwd)
    $Password = [Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
}

# psversion check
function Test-PSVersion7 {
	if ( $PSVersionTable.PSversion.Major -lt 7 ) { $ret = $false } else { $ret = $true }
	return $ret
}

# Helper function for REST call with basic auth
function Invoke-Redfish {
    param(
        [string]$Uri
    )

    try {
        if( Test-PSVersion7 ){
            $SecurePassword = ConvertTo-SecureString -String $Password -AsPlainText -Force
            $cred = New-Object System.Management.Automation.PSCredential($Username, $SecurePassword)
            $response = Invoke-RestMethod -Uri $Uri -Authentication Basic -Credential $cred -Method Get -UseBasicParsing -SkipCertificateCheck -SkipHttpErrorCheck

        } else {
            # Ignore SSL errors
            if (-not ("TrustAllCertsPolicy" -as [type])) {
                add-type @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
    public bool CheckValidationResult(
        ServicePoint srvPoint, X509Certificate certificate,
        WebRequest request, int certificateProblem) {
        return true;
        }
    }
"@
            }
            [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy

            $headers = @{
                Authorization = "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$Username`:$Password"))
            }
            $response = Invoke-RestMethod -Uri $Uri -Headers $headers -Method Get -UseBasicParsing
        }
        return $response
    } catch {
        # Check if the error is a 401/403 (unauthorized/forbidden)
        if ($_.Exception.Response -and $_.Exception.Response.StatusCode.value__ -in 401,403) {
            Write-Host "ERROR: Authentication to iLO failed. Please check your username and password." -ForegroundColor Red
        } else {
            Write-Host "Failed to query $Uri : $_" -ForegroundColor Red
        }
        return $null
    }
}

$CSV_Array = @()

# Firmware
Write-Host "Get Firmware List"
$baseUri = "https://$iLoIP/redfish/v1/UpdateService/FirmwareInventory/"
$fwList = Invoke-Redfish $baseUri

if (-not $fwList) {
    Write-Host "Aborting: Could not retrieve firmware inventory from iLO." -ForegroundColor Red
    [Console]::OutputEncoding = $TempOutputEncoding
    exit 1
}

if ($fwList -and $fwList.Members) {
    foreach ($mem in $fwList.Members) {
        $item = Invoke-Redfish ("https://$iLoIP" + $mem.'@odata.id')
        if ($item) {
            $CSV_Array += [PSCustomObject]@{
                Type        = "Firmware"
                Id          = $item.Id
                Description = $item.Description
                Name        = $item.Name
                Version     = $item.Version
                Position    = $item.Oem.Hpe.DeviceContext
            }
        }
    }
}

# Software
Write-Host "Get Software List"
$baseUri = "https://$iLoIP/redfish/v1/UpdateService/SoftwareInventory/"
$swList = Invoke-Redfish $baseUri

if (-not $swList) {
    Write-Host "WARNING: Could not retrieve software inventory from iLO." -ForegroundColor Yellow
}

if ($swList -and $swList.Members) {
    foreach ($mem in $swList.Members) {
        $item = Invoke-Redfish ("https://$iLoIP" + $mem.'@odata.id')
        if ($item) {
            $CSV_Array += [PSCustomObject]@{
                Type        = "Software"
                Id          = $item.Id
                Description = $item.Description
                Name        = $item.Name
                Version     = $item.Version
                Position    = ""
            }
        }
    }
}

# Export CSV
$outFile = "${outputFolderPath}\${HostName}-iLo_FWSW_List.csv"
if ($CSV_Array.Count -eq 0) {
    Write-Host "No firmware or software information could be retrieved." -ForegroundColor Yellow
    [Console]::OutputEncoding = $TempOutputEncoding
    exit 2
}
$CSV_Array | Export-Csv -Path $outFile -NoTypeInformation -Encoding Default
Write-Host "Exported results to $outFile"
