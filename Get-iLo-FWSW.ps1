<#
 .SYNOPSIS
  Get iLO Firmware and Software information.

 .DESCRIPTION
  Queries HP iLO Redfish REST API for Firmware and Software, outputs as CSV.
  Version: 0.1.1

 .PARAMETER iLoIP
  (Alias -i) Mandatory. IP or hostname of the iLO interface.

 .PARAMETER HostName
  (Alias -h) Optional. Name of the host. This is used just to form the output CSV filename, 
  with dots (".") replaced with underscores ("_"). iLoIP will be used instead if omitted.

 .PARAMETER Username
  (Alias -u) Optional. iLO username (default: Administrator).

 .PARAMETER Password
  (Alias -p) Optional. iLO password. If omitted, prompts interactively.
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
    [string]$Password
)

if (-not $HostName) {
    $HostName = $iLoIP -replace '\.', '_'
}

if (-not $Password) {
    $SecurePwd = Read-Host -AsSecureString "Enter iLO password"
    $BSTR = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePwd)
    $Password = [Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
}

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

# Helper function for REST call with basic auth
function Invoke-Redfish {
    param(
        [string]$Uri
    )
    $headers = @{
        Authorization = "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$Username`:$Password"))
    }
    try {
        $response = Invoke-RestMethod -Uri $Uri -Headers $headers -Method Get -UseBasicParsing
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
Write-Host "Get Firmwares List"
$baseUri = "https://$iLoIP/redfish/v1/UpdateService/FirmwareInventory/"
$fwList = Invoke-Redfish $baseUri

if (-not $fwList) {
    Write-Host "Aborting: Could not retrieve firmware inventory from iLO." -ForegroundColor Red
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
            }
        }
    }
}

# Software
Write-Host "Get Softwares List"
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
            }
        }
    }
}

# Export CSV
$outFile = ".\${HostName}-iLo_FWSW_List.csv"
if ($CSV_Array.Count -eq 0) {
    Write-Host "No firmware or software information could be retrieved." -ForegroundColor Yellow
    exit 2
}
$CSV_Array | Export-Csv -Path $outFile -NoTypeInformation -Encoding Default
Write-Host "Exported results to $outFile"
