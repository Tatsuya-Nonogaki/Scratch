---

## Password and userAccountControl related Handling Matrix

### ChangePasswordAtLogon  

| Password Set     | ChangePasswordAtLogon (column/flag) | userAccountControl 0x80000  | Action                            | Notes                     |
|------------------|-------------------------------------|-----------------------------|-----------------------------------|---------------------------|
| Yes              | TRUE/positive                       | don't care                  | Set -ChangePasswordAtLogon $true  | Works as intended         |
| Yes              | FALSE/negative                      | don't care                  | Set -ChangePasswordAtLogon $false | Works as intended         |
| Yes              | blank/missing                       | Set                         | Set -ChangePasswordAtLogon $true  | Works as intended         |
| Yes              | blank/missing                       | Not set                     | Do not set                        | Silently ignore           |
| No               | positive/negative                   | don't care                  | Do not set                        | Warn                      |
| No               | blank/missing                       | Set                         | Do not set                        | Warn                      |
| No               | blank/missing                       | Not Set                     | Do not set                        | Silently ignore           |

---

## **Summary**  

- You should **not** make the `Password` column mandatory for all users.
- Only set `ChangePasswordAtLogon` if a password is present.
- This avoids error storms and keeps the CSV format flexible for both enabled and disabled accounts.

---
