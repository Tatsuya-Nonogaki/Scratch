# Cloud-init Ready: Linux VM Deployment Kit on vSphere (English)

This kit automates deployment of cloud-init-enabled Linux virtual machines on vSphere.  
The management side uses PowerShell / PowerCLI (Windows admin host is assumed). The workflow is split into four phases:

**Phase 1:** Clone from VM Template  
**Phase 2:** Guest initialization on the clone  
**Phase 3:** Create and attach a cloud-init seed ISO, boot and let cloud-init run  
**Phase 4:** Cleanup — detach & remove seed ISO and disable cloud-init permanently

This is the English version of the README. It follows the finalized Japanese draft and includes the operational guidance and cautions needed for public consumption.

---

Table of contents
- Overview
- What this kit complements in cloud-init
- Key files
- Requirements and pre-setup (admin host and template VM)
- Quick start
- Phases — When to run / When not to run (public-facing guidance)
  - Phase 1..4 concise descriptions and cautions
- Template infra: what is changed and why
- mkisofs / ISO creation notes
- Operational recommendations
- Troubleshooting (common cases)
- Logs & debugging
- License

---

## Overview

This kit automates the common workflow required to create cloud-init-driven VMs from a vSphere template:

- **Phase 1:** Create a clone from a VM Template
- **Phase 2:** Prepare the clone to accept cloud-init
- **Phase 3:** Generate a cloud-init seed (user-data, meta-data, optional network-config), create an ISO (cidata), upload it to a datastore and attach it to the clone's CD drive, then boot the VM and wait for cloud-init to complete
- **Phase 4:** Detach and remove the seed ISO from the datastore, then place /etc/cloud/cloud-init.disabled on the guest to prevent future automatic runs (can be selectively omitted)

The main control program is `cloudinit-linux-vm-deploy.ps1` (PowerShell). The kit includes the `infra/` helper files to prepare base configuration of cloud-init to be cloned while keeping the template safe from accidental cloud-init execution.

---

## What this kit complements in cloud-init (key points)

This kit is not intended to replace cloud-init but to complement operational gaps commonly found in real-world vSphere deployments:

- Filesystem expansion beyond root: kit-specific handling to reformat/resync swap devices and expand other filesystems (not just root)
- NetworkManager adjustments for Ethernet connections (for example: enforce IPv6 disabled, ignore-auto-routes/ignore-auto-dns)
- Template safety: template-level blocking of cloud-init and an explicit process to re-enable it on the clone
- Admin-host-driven creation / upload / attach of a cloud-init seed ISO and automated completion detection (quick-check + completion polling)
- Logs and generated artifacts are retained under `spool/<new_vm_name>/` on the admin host for auditing and troubleshooting
- Using PowerShell `-Verbose` shows important internal steps in the console to assist debugging

**Important:** This kit assumes the intended lifecycle is **template** -> **new clone** -> **initialization** -> **personalization**. It is not designed to "retrofit" cloud-init onto already running production VMs that you want to change later (at the time being).

---

## Key files

- `cloudinit-linux-vm-deploy.ps1` — main PowerShell deployment script (implements phases 1–4)
- `params/vm-settings_example.yaml` — parameter example (copy and edit per-VM)
- `templates/original/*_template.yaml` — cloud-init user-data / meta-data / network-config templates
- `scripts/init-vm-cloudinit.sh` — script transferred and run on the clone in Phase 2
- `infra/prevent-cloud-init.sh` — place on the template to disable automatic cloud-init
- `infra/cloud.cfg`, `infra/99-template-maint.cfg` — template-optimized cloud.cfg and additional config
- `infra/enable-cloudinit-service.sh` — helper to ensure cloud-init services enabled on the template VM
- `infra/req-pkg-cloudinit.txt`, `infra/req-pkg-cloudinit-full.txt` — package lists
- `spool/` — the script writes per-VM output to spool/<new_vm_name>/ (`dummy.txt` is included only for this empty folder to exist in GitHub repository)

---

## Requirements / Pre-setup

Admin host (PowerShell environment — Windows is the primary target):
- Windows (PowerShell) or PowerShell Core (Windows admin host is assumed)
- VMware PowerCLI (VMware.VimAutomation.Core)
- powershell-yaml module
- mkisofs (Win32 mkisofs from cdrtfe is the expected binary by default; see mkisofs notes below)
- Clone or unzip this repository. The repository contains a pre-created `spool/` directory (a dummy file is included so the folder exists). The script will create `spool/<new_vm_name>/` at runtime.

Template VM (example: RHEL9):
- open-vm-tools
- cloud-init, cloud-utils-growpart (dracut-config-generic is optional if you need dracut operations)
- A CD/DVD drive present on the VM (seed ISO is attached to the CD drive)
- Copy `infra/` to the template and run `prevent-cloud-init.sh` as root to protect the template

Line endings:
- PowerShell scripts and params YAML: CRLF (Windows)
- Guest shell scripts and cloud-init templates: LF (Unix)

---

## Quick start (short path)

1. Clone or unzip this repo on the Windows admin host and install PowerCLI / powershell-yaml.
2. On the template VM:
   - copy `infra/` into the template filesystem and run:
     ```sh
     cd infra
     sudo ./prevent-cloud-init.sh
     ```
     This installs `/etc/cloud/cloud-init.disabled`, replaces `/etc/cloud/cloud.cfg` with the kit-optimized config and installs `99-template-maint.cfg`.
   - Shutdown the VM and convert to a vSphere Template.
3. On the admin host:
   - Copy `params/vm-settings_example.yaml` to a new filename you prefer (example: `params/vm-settings_myvm01.yaml`) and edit it. Tip: use the same name in the file name and `new_vm_name` parameter to keep things clear.
4. Run the deploy script:
   ```powershell
   .\cloudinit-linux-vm-deploy.ps1 -Phase 1,2,3 -Config .\params\vm-settings_myvm01.yaml
   ```
   - You may run single phases (`-Phase 1`) or continuous sequences (`-Phase 1,2,3`). Non-contiguous phase lists like `-Phase 1,3` are not supported and will fail.
5. Generated files and logs are placed in `spool/<new_vm_name>/` on the admin host.

Note: The repository includes `spool/` (a dummy file exists so the folder is present after clone/unzip). You do not need to create it manually.

---

## Phases — When to run / When not to run (public guidance)

Important: Phase selection must be a contiguous ascending list (single phase allowed). Examples:
- Valid: `-Phase 1` or `-Phase 1,2,3`
- Invalid: `-Phase 1,3` (non-contiguous)

Phase 1–3 form the typical deployment flow. Phase 4 is a post-processing operation with different semantics and is recommended to be run after confirming Phase 3 succeeded.

### Phase 1 — Automatic Cloning
Purpose:
- Create a new VM by cloning the Template VM and apply specified vSphere-level hardware settings (CPU, memory, disk sizes).

Notes / When to run:
- Run when you want to create a brand new VM from the template.
- This phase does not perform guest power-on or shutdown (power operations are handled in later phases).

Cautions / When not to run:
- Don't run if a VM with the same name already exists on the vCenter (the script checks and aborts).
- This kit is not intended to perform subsequent "retrofit" cloud-init operations on an already running, unrelated VM.

High-level steps:
1. Validate no VM name collision
2. Resolve resource pool / datastore / host / portgroup from params
3. New-VM clone operation
4. Apply CPU / memory settings
5. Resize vmdk entries defined in params.disks

Result:
- A new VM object appears in vCenter (usually left powered off until later phases).

### Phase 2 — Guest Initialization
Purpose:
- Run guest-side initialization to remove template protections and prepare the clone to accept cloud-init. After this phase completes the VM is left powered on so administrators can log in and verify or perform adjustments.

When to run:
- After Phase 1 (or on a clone you just created) when you need to remove template-level blocking files and clear cloud-init state before personalization.

Cautions:
- Ensure the `params.username` and `params.password` credentials are correct and that VMware Tools (open-vm-tools) is running inside the guest — the script uses `Invoke-VMScript` and `Copy-VMGuestFile`.
- The kit expects to remove template-level blocking files; ensure the init script is appropriate for your distribution.

High-level steps:
1. Power on the VM (respecting `-NoRestart` behavior and prompting if necessary)
2. Create `$workDirOnVM` and ensure ownership
3. Transfer `scripts/init-vm-cloudinit.sh` into the guest and run it (this script does the following main tasks):
   - subscription-manager cleanup (RHEL)
   - Remove existing NetworkManager Ethernet connection profiles (Ethernet only)
   - Run `cloud-init clean`
   - Truncate `/etc/machine-id`
   - Remove `/etc/cloud/cloud-init.disabled` (re-enable cloud-init)
   - Remove `/etc/cloud/cloud.cfg.d/99-template-maint.cfg`
   - Create `/etc/cloud/cloud.cfg.d/99-override.cfg` to set `preserve_hostname: false` and `manage_etc_hosts: false`
4. Leave the VM powered on for verification and possible manual adjustments

Result:
- Clone is ready for cloud-init personalization (template protection removed, cloud-init caches cleaned), and VM remains powered on.

### Phase 3 — Cloud-init seed creation & personalization
Purpose:
- Render user-data / meta-data / network-config from templates + params, create a cidata ISO, upload it to a datastore, attach it to the VM's CD drive, boot the VM and wait for cloud-init to apply the configuration. The VM finishes Phase 3 in a powered-on state.

When to run:
- After Phase 2 (or when the clone is prepared) to apply cloud-init-driven personalization (hostname, users, SSH keys, network, filesystem/swap reconfiguration).

Cautions / constraints:
- If `/etc/cloud/cloud-init.disabled` remains on the guest, this phase is meaningless — the script checks early and aborts if found.
- Upload will fail if the target datastore path already contains an ISO with the same name. The script is intentionally conservative and will not overwrite an existing ISO. Typical resolution:
  - Run Phase 4 alone (with `-NoCloudReset` if you don't want to create `/etc/cloud/cloud-init.disabled`) to remove the existing ISO, or
  - Manually remove the ISO from the datastore.
- Re-running Phase 3 repeatedly (without running Phase 4) can lead to repeated SSH host key regeneration and duplicated NetworkManager connection profiles — be mindful and use Phase 4 to finalize once satisfied.
- `-NoRestart` can prevent an actual reboot that is required to pick up the seed ISO. The script warns and exits in that case.

High-level steps:
1. Render templates (user-data / meta-data / optional network-config). The kit will dynamically build a `runcmd` block for:
   - Additional filesystem `resize2fs` commands (kit extension)
   - Swap reinitialization scripts (kit-specific)
   - NetworkManager `nmcli` modifications for Ethernet interfaces only (ignore-auto-routes/ignore-auto-dns/ipv6.method disabled)
2. Generate an ISO with mkisofs (cidata volume label)
3. Upload ISO to the datastore path specified by `seed_iso_copy_store` (format: `[DATASTORE] path/`)
4. Attach the uploaded ISO to the clone's CD drive
5. Power on the VM and perform detection:
   - A quick-check helper script runs (generated by the kit) to determine if cloud-init artifacts were produced after the seed attach epoch
   - If quick-check suggests cloud-init ran, the script copies a `check-cloud-init.sh` to the guest and polls it until it returns READY (examples of checks: `cloud-init status --wait`, `boot-finished` mtime after seed attach, systemd cloud-final exit)
   - The `quick-check.sh` and `check-cloud-init.sh` are created and transferred for the detection process; normally they are removed from the guest after use (a local copy remains under `spool/<new_vm_name>/`)

Result:
- cloud-init has applied the personalization and the VM is ready (script determines completion). VM is left powered on.

### Phase 4 — Cleanup and finalization
Purpose:
- Detach the seed ISO from the VM, remove the ISO from the datastore, and by default create `/etc/cloud/cloud-init.disabled` on the guest to prevent automatic cloud-init runs on later boots. If `-NoCloudReset` is supplied, the creation of `/etc/cloud/cloud-init.disabled` is skipped while ISO detach/removal still happens.

When to run (recommended):
- After you have confirmed Phase 3 completed successfully. Phase 4 can also be run alone to remove a previously uploaded ISO (for example, to allow a subsequent Phase 3 re-run) — use `-NoCloudReset` if you want to keep cloud-init enabled but clear the datastore ISO.

Cautions:
- If VMware Tools is not running inside the guest, the script cannot create `/etc/cloud/cloud-init.disabled` remotely and Phase 4 will fail at that step. If disabling cloud-init is not required, use `-NoCloudReset` to skip that part.
- When executing Phase 4 solely to allow Phase 3 to be re-run, prefer `-NoCloudReset` to avoid locking cloud-init off.

High-level steps:
1. Detach CD/DVD media from the VM
2. Remove the uploaded ISO file from the datastore
3. Wait for VMware Tools and create `/etc/cloud/cloud-init.disabled` inside the guest (unless `-NoCloudReset` is specified)

Result:
- The seed is removed and optionally cloud-init is disabled permanently on the guest, preventing accidental re-run.

---

## Template infra — what we change and why

`infra/cloud.cfg` and `infra/99-template-maint.cfg` are tuned to make the source Template safe to operate and easy to clone:

The README documents only the parameters that have been intentionally changed from RHEL9 default; those are marked as [CHANGED] in the shipped `infra/cloud.cfg`. Key changes we apply (explicitly changed from RHEL9 defaults):

- users: [] — suppress default user creation (no cloud-user) [CHANGED]  
- disable_root: false — allow root SSH login on template (adjust per your policies) [CHANGED]  
- preserve_hostname: true — keep the template hostname (on clones we create `99-override.cfg` to set `preserve_hostname: false`) [CHANGED]  
- Most cloud-init modules are set to once / once-per-instance so the template and clones do not execute modules repeatedly or unexpectedly [CHANGED]  
- Package update/upgrade steps were removed from cloud-final to avoid accidental package changes during cloning [CHANGED]

Notes:
- SSH host key regeneration settings (e.g., `ssh_deletekeys`, `ssh_genkeytypes`) are left as RHEL9 defaults and are not intentionally changed by the kit. The README highlights only the settings listed above that were intentionally changed.

---

## mkisofs & ISO creation notes

- The kit assumes a Windows admin host and by default the script variable `$mkisofs` points to a Win32 mkisofs binary bundled with cdrtfe (https://sourceforge.net/projects/cdrtfe/). Adjust `$mkisofs` in the script's global variables if you use a different binary or a Linux environment (e.g., genisoimage under WSL).
- The ISO must be created with the volume label `cidata` and include user-data/meta-data/network-config files in the root so cloud-init recognizes it.
- Depending on the mkisofs implementation, you may need to adapt the `$mkArgs` used in the script (for encoding, Joliet flags, etc.). If mkisofs fails, confirm `$mkisofs` path and `$mkArgs` match your mkisofs binary.

---

## Operational recommendations

- Phase selection:
  - You may run any contiguous sequence of phases or a single phase. Non-contiguous selection (e.g., `-Phase 1,3`) will be rejected.
  - Prefer running Phase 4 as a separate step after you have confirmed Phase 3 succeeded (Phase 4 is a finalization step).
- VMware Tools:
  - Required for Phase 2/3/4 guest file operations. Verify `open-vm-tools` is installed and functioning on the guest.
- Credentials:
  - `params/*.yaml` contains credentials in plain form in the example. Treat those files as sensitive. Use credential stores or secure methods to protect secrets in production.
- spool directory:
  - The repository includes `spool/` with a dummy file so it exists after clone/unzip. The script creates `spool/<new_vm_name>/` and writes logs such as `spool/<new_vm_name>/deploy-YYYYMMDD.log` and generated seeds/ISOs there.

---

## Troubleshooting (common cases)

- cloud-init did not run
  - Check the clone does not still have `/etc/cloud/cloud-init.disabled` (Phase 2 must have removed it). Verify `scripts/init-vm-cloudinit.sh` returned success.
  - Inspect `spool/<new_vm_name>/cloudinit-seed/` to confirm generated user-data/meta-data/network-config content and timestamps.
  - Verify VMware Tools are running; if not, `Copy-VMGuestFile` and `Invoke-VMScript` will fail.
  - Check guest logs: `/var/log/cloud-init.log`, `/var/log/cloud-init-output.log`, and `/var/lib/cloud/instance/*`.

- ISO creation / upload failure
  - `$mkisofs` not found or wrong binary. Confirm `$mkisofs` path in the script or use a compatible mkisofs and update the script.
  - `seed_iso_copy_store` is malformed. Expected form: `[DATASTORE] path/` (example: `[COMMSTORE01] cloudinit-iso/`).
  - Datastore already contains an ISO file at that path (common when re-running Phase 3). Solution: run Phase 4 alone to remove the existing ISO, or manually delete the ISO from the datastore. When running Phase 4 only and you want to avoid creating `/etc/cloud/cloud-init.disabled`, use `-NoCloudReset`.

- Network configuration not applied as expected
  - Ensure `templates/original/network-config_template.yaml` and `params` `netifX.netdev` values match the guest's actual interface names (e.g., `ens192`). Also verify the mapping of vSphere NIC order (Network <index>) vs. guest device naming if your environment renumbers devices.

---

## Logs & debugging

- Detailed logs and generated files are stored on the admin host in `spool/<new_vm_name>/`. The primary log file is `spool/<new_vm_name>/deploy-YYYYMMDD.log` (the script writes additional files such as the generated seed ISO and copies of the rendered YAML).
- Run the PowerShell script with `-Verbose` to see important internal steps printed to the console for debugging.

---

## License

MIT License — see the repository LICENSE file for details.
