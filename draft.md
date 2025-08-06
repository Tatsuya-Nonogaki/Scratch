## Password and userAccountControl related Handling Matrix

### ChangePasswordAtLogon  

| Password Set     | ChangePasswordAtLogon (column) | userAccountControl 0x80000  | Action                            | Notes           |
|------------------|--------------------------------|-----------------------------|-----------------------------------|-----------------|
| Yes              | TRUE/positive                  | don't care                  | Set-ADUser -ChangePasswordAtLogon $true  |                 |
| Yes              | FALSE/negative                 | don't care                  | Set-ADUser -ChangePasswordAtLogon $false |                 |
| Yes              | blank/missing                  | Set                         | Set-ADUser -ChangePasswordAtLogon $true  | Existing logic  |
| Yes              | blank/missing                  | Not set                     | Silently ignore                   |                 |
| No               | TRUE/positive                  | don't care                  | Warn and Do not set               |                 |
| No               | FALSE/negative                 | don't care                  | Set-ADUser -ChangePasswordAtLogon $false |                 |
| No               | blank/missing                  | Set                         | Warn and Do not set               | Existing logic  |
| No               | blank/missing                  | Not Set                     | Silently ignore                   |                 |

---
