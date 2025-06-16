<#
 .SYNOPSIS
  Get iLo Firmware and Software information.

 .DESCRIPTION
  Get iLo Firmware and Software information and export the result to a CSV file.
  Version: 0.1.0

 .PARAMETER iLoIP
  (Alias -i) Mandatory. IP interface address of the iLo.

 .PARAMETER HostName
  (Alias -n) Optional. Name of the host, which is used just to name the output CSV file, 
  with dots (".") replaced with underscores ("_"). iLoIP will be used instead If omitted.
#>
[CmdletBinding()]
Param(
  [Parameter(Mandatory=$true,Position=0)]
  [Alias("i")]
  [string]$iLoIP,

  [Parameter(Position=1)]
  [Alias("n")]
  [string]$HostName
)

$TempOutputEncoding = [Console]::OutputEncoding
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[System.Net.ServicePointManager]::SecurityProtocol = @([System.Net.SecurityProtocolType]::Ssl3,[System.Net.SecurityProtocolType]::Tls,[System.Net.SecurityProtocolType]::Tls11,[System.Net.SecurityProtocolType]::Tls12)

Add-Type @"
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
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy


$CSV_Array = @()
### Firmwares List
Write-Host "Get Firmwares List"
$uri = "https://" + $iLoIP + "/redfish/v1/UpdateService/FirmwareInventory/"
$cmd = ".\iLo_SendRestApi.bat $uri" 

$resultCmd = Invoke-Expression $cmd
$resultcount = $resultCmd.Count - 1

$std_json = $resultCmd[$resultcount] | ConvertFrom-Json
$Sw_Members = $std_json.Members

foreach ($Mem in $Sw_Members) {
   $uri = "https://" + $iLoIP + $Mem.'@odata.id'
   $cmd = ".\iLo_SendRestApi.bat $uri" 
   $resultCmd = Invoke-Expression $cmd

   $resultcount = $resultCmd.Count - 1

   $std_json = $resultCmd[$resultcount] | ConvertFrom-Json

   #CSVArray登録
   $List = [PSCustomObject][ordered]@{
      Type         = "Firmware"
      Id           = $std_json.id
      Description  = $std_json.Description
      Name         = $std_json.Name
      Version      = $std_json.Version
   } 
   $CSV_Array += $List
}

### Softwares List
Write-Host "Get Softwares List"
$uri = "https://" + $iLoIP + "/redfish/v1/UpdateService/SoftwareInventory/"
$cmd = ".\iLo_SendRestApi.bat $uri" 

$resultCmd = Invoke-Expression $cmd

$resultcount = $resultCmd.Count - 1

$std_json = $resultCmd[$resultcount] | ConvertFrom-Json

$Sw_Members = $std_json.Members

foreach ($Mem in $Sw_Members) {
   $uri = "https://" + $iLoIP + $Mem.'@odata.id'
   $cmd = ".\iLo_SendRestApi.bat $uri" 
   $resultCmd = Invoke-Expression $cmd

   $resultcount = $resultCmd.Count - 1

   $std_json = $resultCmd[$resultcount] | ConvertFrom-Json
   #CSVArray登録
   $List = [PSCustomObject][ordered]@{
      Type         = "Software"
      Id           = $std_json.id
      Description  = $std_json.Description
      Name         = $std_json.Name
      Version      = $std_json.Version
   } 
   $CSV_Array += $List
}

#[PSCustomObject]$CSV_Array | Format-Table
$OutFileName = ".\" + $HostName + "_FW_SW_List.csv"
[PSCustomObject]$CSV_Array | Export-Csv $OutFileName -Encoding Default -NoTypeInformation

[Console]::OutputEncoding = $TempOutputEncoding
