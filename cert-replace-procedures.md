### Overall policy
- Use `vCert` instead of now discouraged `fixcerts.py` for stability, if possible. Use the most recent version of either tool.  
  > **Note:** One invaluable advantage of `fixcerts.py` is the capability to specify an extended validity period of renewed certificates (`--validityDays <DAYS>`).  
  > The actual period of generated certificates **cannot exceed the expiry of the vCSA root CA**—even if a longer value is specified, certificates will expire at the root CA's end date.
- Enable logging of the terminal application as far as possible  
  It is strongly recommended to run the commands, including the execution of the `vCert.py`/`fixcerts.py` on a `SSH` session with a terminal software, e.g., `PuTTY` or OS standard `ssh`.

#### Pre-Renewal Checklist
- **Always take a cold VM snapshot of the targetted vCSA, once shutting it down, before making any changes.**
- Before modifying anything, take the list of current status of certificates, by a shell one-liner:
    ```
    for store in $(/usr/lib/vmware-vmafd/bin/vecs-cli store list | grep -v TRUSTED_ROOT_CRLS); do echo "[*] Store :" $store; /usr/lib/vmware-vmafd/bin/vecs-cli entry list --store $store --text | grep -ie "Alias" -ie "Not Before" -ie "Not After"; done
    ```
- Check the health of the vCenter Server  
  - Service status (can be checked on VAMI graphically)
     ```
     service-control --status --all
     ```
  - Check for prior errors in:
    - **`/var/log/vmware/vmcad/`**

      Mainly:
      - certificate-manager.log  _#Manual certificate operations_
      - vmcad.log                _#VMCA service and certificate lifecycle events_
      - vmca-audit.log           _#Audit trail of certificate changes_

      Optionally:
      - vmcad-syslog.log         _#system-level VMCA events_

    - **`/var/log/vmware/sso/`**

       Mainly:
       - sts-health-status.log    _#STS health and certificate issues_
       - ssoAdminServer.log       _#SSO server operations and errors_
       - vmware-identity-sts.log  _#Secure Token Service (STS) and identity events_

       Optionally:
       - tokenservice.log         _#Token service operations_
       - sso-config.log           _#SSO configuration changes/events_
       - openidconnect.log        _#OpenID Connect related authentication events_

---

### Procedures for vCert
Always use its interactive navigation. (Command-line options are very limited)

#### Procedures
1. **Run vCert.py:**  
   Start by just `./vCert.py`. If you pass `--user <user@vphere> --password <pswd>`, authentication prior to each authoritative operation is omitted.

2. **Check current certificate status:**  
   In the main menu, select "1. Check current certificate status" and proceed.

3. **Try full-auto renewal first:**  
   Choose "6. Reset all certificates with VMCA-signed certificates" in the main menu and proceed.

4. **Service restart prompt:**  
   Answer "N" (default) to "Restart VMware services [N]: " prompt, if succeeded or failed.

5. **Check logs for errors after vCert.py runs:**  
   - Review `/var/log/vmware/vmcad/` and `/var/log/vmware/vmware/sso/` for signs of certificate renewal problems.
   - Check the own log files of vCert.py. Official Web document say (extract);  
     > The script will create `/var/log/vmware/vCert/vCert.log` (which will be included in a support bundle), and a directory in /root/vCert-master with the name format YYYYMMDD, which will include several sub-directories for staging, backups, etc. Other than certificate backup files, the temporary files are deleted when the vCert tool exits.

6. **Post-renewal verification and service restart:**  
   - If the recreation of certificates was successful, choose "8. Restart services" in the main menu. (This will take some time.)
   - After services restart, re-run the certificate status one-liner above to confirm expiry dates are updated.
   - Also check for any vCenter alerts or certificate-related warnings in the UI.

7. **If the recreation failed, fully or partially:**  
   1. Select "1. Check current certificate status" in the main menu to check which certificates failed.
   2. Also, check with the one-liner command:
      ```
      for store in $(/usr/lib/vmware-vmafd/bin/vecs-cli store list | grep -v TRUSTED_ROOT_CRLS); do echo "[*] Store :" $store; /usr/lib/vmware-vmafd/bin/vecs-cli entry list --store $store --text | grep -ie "Alias" -ie "Not Before" -ie "Not After"; done
      ```
   3. Try recreating certificates per Certificate-Type, by selecting "3. Manage certificates" in the main menu and proceeding to the specific sub menu such as "2. Solution User certificates". Check the status of the certificates again.
      > *Refer to the certificate-type chart for correct menu entries.*
   4. After complete renewal of all the failed certificates, go back to the main menu and select "8. Restart services". (This will take some time.)

8. **Final health check:**  
   Check the health of the vCenter Server as described before, and confirm that all certificates have been successfully renewed and that services are operating normally.

---

**Tips:**
- **Always snapshot before any changes!**  
- **After renewal, verify expiry dates using the shell one-liner and check for vCenter alerts.**
- **Check logs after each major operation for hidden errors.**

---

### Procedures for fixcerts.py
It is sometimes reported that `fixcerts.py` has difficulties in stability; for example, some certificates may fail to renew while others succeed. **Staged renewal per certificate-type, instead of renewing all at once, is recommended to minimize the risk of failures.** Always use the newest version (`fixcerts_3_2.py` at the time of writing).

#### Procedures
1. **Run fixcerts.py per certificate-type:**  
   - Execute the script for each certificate-type individually, using appropriate command-line options. For example:
     ```
     ./fixcerts.py replace --certType machinessl --validityDays 3650 --serviceRestart False
     ```
     **Key Points:**  
     - Change the `--certType` argument for each run to match the certificate-type.  
       *Refer to the certificate-type chart for correct values (e.g. `machinessl`, `solutionusers`, `sms`, `data-encipherment`, etc.).*
     - Use the `--validityDays` option to extend certificate validity, if desired.  
       **Note:** The actual period of generated certificates **cannot exceed the expiry of the root CA**—even if a longer value is specified, the certificates will expire at the root CA's end date.
     - Always set `--serviceRestart False` for each run. You will restart services after all renewals are complete.
     - Consider passing the `--debug` option to increase verbosity and aid troubleshooting.
     - Consider running the script in an SSH session with logging enabled to capture all console output.
     - **Note:** `fixcerts.py` does not provide an interactive menu; all operations are done via command-line arguments.

2. **Verify certificate renewal after each type:**  
   - After each certificate-type renewal, run the certificate status one-liner to confirm expiry dates have changed:
     ```
     for store in $(/usr/lib/vmware-vmafd/bin/vecs-cli store list | grep -v TRUSTED_ROOT_CRLS); do echo "[*] Store :" $store; /usr/lib/vmware-vmafd/bin/vecs-cli entry list --store $store --text | grep -ie "Alias" -ie "Not Before" -ie "Not After"; done
     ```
   - Review for any certificates that were not updated.

3. **Check logs for errors after each run:**  
   - Check standard system logs for issues:
     - `/var/log/vmware/vmcad/`
     - `/var/log/vmware/vmware/sso/`
   - Check `fixcerts.py`'s own log file:  
     - `fixcerts.log` (found in the current working directory where the script was executed).

4. **Troubleshoot and retry failed renewals:**  
   - If any certificate-type fails to renew, attempt rerunning fixcerts.py for that type.
   - Use the `--debug` option for more detailed error output.
   - If failures persist, consider manual renewal using `vecs-cli` or consult official product support documentation.

5. **Restart services after all renewals:**  
   - Once all certificate-types have been renewed successfully, restart vCSA services to apply changes by running:
     ```
     service-control --stop --all && service-control --start --all
     ```
     > This is the recommended and safe method to restart services, as used internally by fixcerts.py itself.

6. **Final health check and post-renewal verification:**  
   - Run service health check as described previously:
     ```
     service-control --status --all
     ```
   - Re-run the certificate status one-liner to confirm all expiry dates.
   - Check the vCenter UI for any certificate-related warnings or alerts.

---

**Tips:**
- **Always snapshot before any changes!**
- **After renewal, verify expiry dates using the shell one-liner and check for vCenter alerts.**
- **Check logs, including `fixcerts.log`, after each major operation for hidden errors.**
- **Use the `--debug` option for more detailed troubleshooting if issues arise.**
