# vCenter Server FQDN or IP address
$vcserver = 'vcsa1.mydomain.com'

# vCenter HTTPS port. Change this only if you are not using the default 443.
$vcport = 443

# vCenter login user
# NOTE:
#   - $vcuser should normally NOT be commented out.
#   - This script expects a user name to always be provided.
$vcuser  = 'Administrator@vsphere.local'

# Optional: vCenter password (plain text)
#   - If set, the script uses legacy plain password mode:
#       Connect-VIServer -User $vcuser -Password $vcpasswd
#   - It is not recommended for production site from a security perspective
#     though it may be convenient in lab / build environments.
#$vcpasswd = 'ChangeMe!'

#   - When using SecretStore / VISecret for credential management, keep the
#     above $vcpasswd line commented out, and:
#     - Install the Microsoft.PowerShell.SecretManagement and
#       Microsoft.PowerShell.SecretStore modules if they are missing
#       (both PowerShell 7 and Windows PowerShell 5.1+ are supported).
#     - Download Modules/VISecret from GitHub:
#         @vmware-archive/PowerCLI-Example-Scripts
#       and place it under a PSModulePath location as VMware.VISecret.
#     - Then, in a PowerShell console, run:
#         Import-Module VMware.VISecret
#         Initialize-VISecret -Vault "VMwareSecretStore"
#       (the password for $vcuser@$vcserver will be prompted at the first
#       successful login and stored in the SecretVault)

# Number of connection retries when connecting to vCenter fails
$connRetry = 2

# Connection retry interval in seconds
$connRetryInterval = 5

# Optional: SecretManagement / VISecret vault name
#   - If $vcpasswd is NOT set, the script will try to use SecretStore / VISecret.
#   - If $Vault is NOT defined here, the script falls back to $VaultDefault
#     defined in the script itself (typically "VMwareSecretStore").
#   - NOTE:
#       * $VaultDefault corresponds to the default used by Initialize-VISecret
#         in the VMware.VISecret module at the time of writing.
#       * Future versions of VISecret may change that default. For stable,
#         production use it is RECOMMENDED to explicitly set $Vault here instead
#         of relying on the script default.
#   - In plain password mode, $Vault variable below will never be used.
$VaultDefault = 'VMwareSecretStore'
$Vault        = 'VMwareSecretStore'
