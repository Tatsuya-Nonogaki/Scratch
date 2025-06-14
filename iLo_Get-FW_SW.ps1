$Server_Name  = $args[0]
$Sever_iLo_IP = $args[1]

# $Server_Name  = "C_ESXi_iLo"
# $Sever_iLo_IP = "172.16.135.239"

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
$uri = "https://" + $Sever_iLo_IP + "/redfish/v1/UpdateService/FirmwareInventory/"
$cmd = ".\iLo_SendRestApi.bat $uri" 

$resultCmd = Invoke-Expression $cmd
$resultcount = $resultCmd.Count - 1

$std_json = $resultCmd[$resultcount] | ConvertFrom-Json
$Sw_Members = $std_json.Members

foreach ($Mem in $Sw_Members) {
   $uri = "https://" + $Sever_iLo_IP + $Mem.'@odata.id'
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
$uri = "https://" + $Sever_iLo_IP + "/redfish/v1/UpdateService/SoftwareInventory/"
$cmd = ".\iLo_SendRestApi.bat $uri" 

$resultCmd = Invoke-Expression $cmd

$resultcount = $resultCmd.Count - 1

$std_json = $resultCmd[$resultcount] | ConvertFrom-Json

$Sw_Members = $std_json.Members

foreach ($Mem in $Sw_Members) {
   $uri = "https://" + $Sever_iLo_IP + $Mem.'@odata.id'
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
$OutFileName = ".\" + $Server_Name + "_FW_SW_List.csv"
[PSCustomObject]$CSV_Array | Export-Csv $OutFileName -Encoding Default -NoTypeInformation

[Console]::OutputEncoding = $TempOutputEncoding
