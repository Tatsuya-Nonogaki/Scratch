# vCenter Server FQDN or IP address
$vcserver = 'vcsa1.mydomain.com'

# vCenter HTTPS port. Change this only if you are not using the default 443.
$vcport = 443

# vCenter login user
#   - $vcuser should normally NOT be commented out.
#   - This script expects a user name to always be provided.
$vcuser  = 'Administrator@vsphere.local'

# Optional: vCenter password (plain text)
#   - If set, the script uses plain password mode:
#   - It is not recommended for production site from a security perspective.
#$vcpasswd = 'ChangeMe!'

# Optional: Legacy VICredentialStore mode
#   - If set to positive (true/True/yes/Yes) and $vcpasswd is empty,
#     script uses Legacy VICredentialStore mode by default,
#     so script's option "-Legacy" can be omitted at each run.
#$Legacy = true
#   - The password for $vcuser@$vcserver will be prompted at the first
#     login attempt and stored in the VICredentialStore if the login is
#     successful.

# When using SecretStore / VISecret credential management mode:
#   - Keep $vcpasswd line commented out and set $Legacy to negative or
#     comment it out either.
#   - Install the Microsoft.PowerShell.SecretManagement and
#     Microsoft.PowerShell.SecretStore modules if they are missing
#     (both PowerShell 7 and Windows PowerShell 5.1+ are supported).
#   - Download Modules/VISecret from GitHub:
#       @vmware-archive/PowerCLI-Example-Scripts
#     and place it under a PSModulePath location as VMware.VISecret.
#   - Then, to prepare the Secret Vault, in a PowerShell console, run:
#       Import-Module VMware.VISecret
#       Initialize-VISecret -Vault "VMwareSecretStore"
#     (see also $VaultDefault and $Vault below)
#   - The password for $vcuser@$vcserver will be prompted at the first
#     login attempt and stored in the SecretVault if the login succeeds.

# Optional: SecretManagement / VISecret vault name
#   - These variables are used only in non-plain, SecretStore mode. Legacy
#     VICredentialStore mode is not also the case, so can be left untouched.
#   - If $Vault is NOT defined here, the script falls back to
#     $VaultDefault (typically "VMwareSecretStore").
#   - NOTE:
#       * $VaultDefault corresponds to the default used by Initialize-VISecret
#         in the VMware.VISecret module at the time of writing.
#       * Future versions of VISecret may change that default. For stable
#         production use, it is RECOMMENDED to explicitly set $Vault and
#         $VaultDefault here instead of relying on the module's default.
$VaultDefault = 'VMwareSecretStore'
$Vault        = 'VMwareSecretStore'

# Number of connection retries when connecting to vCenter fails
$connRetry = 2

# Connection retry interval in seconds
$connRetryInterval = 5
