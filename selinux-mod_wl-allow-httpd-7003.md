# Manage SELinux to Allow httpd to Access Port 7003 (or Else)/TCP

## Install Prerequisite Packages (RHEL9)

```bash
dnf install policycoreutils-devel selinux-policy-devel
# Optional:
dnf install setools-console
```

---

## See What Is Going On

```bash
ausearch -c http
```

Example output:

```
type=AVC msg=audit(1752813896.450:64983): avc:  denied  { name_connect } for  pid=2766333 comm="httpd" dest=7003 scontext=system_u:system_r:httpd_t:s0 tcontext=system_u:object_r:unreserved_port_t:s0 tclass=tcp_socket permissive=0
```

---

## Automatic Way (Moderate Security - All `unreserved_ports` Are Allowed from httpd)

### Preview the Resultant Rule

```bash
ausearch -c httpd | audit2allow -R
```

### Auto-Generate .te Module

```bash
ausearch -c httpd --raw | audit2allow -M myhttpd_mod_wl
```

Then continue to [SE Module Build and Install (Common)](#se-module-build-and-install-common)

---

## Controlled Way (More Secure)

### Check if Port 7003 is Assigned

```bash
semanage port -l | grep -w '700[0-9]' | grep tcp
```

Example:

```
afs3_callback_port_t           tcp      7001
afs_pt_port_t                  tcp      7002
gatekeeper_port_t              tcp      1721, 7000
```

### Check for Multiple Ports or Ranges (See Also Tips)

```bash
echo $(semanage port -l | awk '$1=="afs3_callback_port_t" && $2=="tcp" {$1=$2=""; print $0}')
```

### Delete Existing Assignment If Safe to Do

```bash
semanage port -d -p tcp 7003
```

> Otherwise, reuse an appropriate predefined label.

### Tips: Expand Port Ranges

```bash
semanage port -l | awk '$1=="afs3_callback_port_t" && $2=="tcp" {$1=$2=""; print $0}' | \
  tr ',' '\n' | while read p; do
    if [[ "$p" == *-* ]]; then seq ${p%-*} ${p#*-}; else echo $p; fi
done
```

---

## Prepare Module Directory

```bash
mkdir -p myhttpd_mod_wl
cd myhttpd_mod_wl
```

---

## Create a Port Type Module (Use Underscores in Names)

### File: `myhttpd_wls_type.te`

```te
module myhttpd_wls_type 1.0;

require {
    attribute port_type;
}

type httpd_wls_port_t;
typeattribute httpd_wls_port_t port_type;
```

### Build and Install Port-Type Module

```bash
checkmodule -M -m -o myhttpd_wls_type.mod myhttpd_wls_type.te
semodule_package -o myhttpd_wls_type.pp -m myhttpd_wls_type.mod
semodule -i myhttpd_wls_type.pp
semodule -lfull | grep myhttpd_wls_type
```

---

## Create a Domain Type Module for Your Custom Executable here, if the Domain Type is your own `mysvcd_t` instead of predefined `httpd_t`

### 1. Define Exec Type and Domain Type, with Transition for systemd

#### File: `mysvcd.te`
```te
module mysvcd 1.0;

require {
    type systemd_t;
    type mysvcd_t;
    type mysvcd_exec_t;
    type httpd_wls_port_t;
    class tcp_socket name_connect;
    class process transition;
    class file { execute read open };
}

# Define the domain type for your daemon
type mysvcd_t;

# Define the exec type for your binary
type mysvcd_exec_t;
files_type(mysvcd_exec_t)

# Allow systemd to read/open/execute your binary
allow systemd_t mysvcd_exec_t:file { read open execute };

# Transition: When systemd_t executes mysvcd_exec_t, the process transitions to mysvcd_t
type_transition systemd_t mysvcd_exec_t:process mysvcd_t;

# Allow your service domain to connect to the custom port type
allow mysvcd_t httpd_wls_port_t:tcp_socket name_connect;
```

### 2. Build and Install Domain Module

```bash
checkmodule -M -m -o mysvcd.mod mysvcd.te
semodule_package -o mysvcd.pp -m mysvcd.mod
semodule -i mysvcd.pp
semodule -lfull | grep mysvcd
```

### 3. Label Your Binary with the Exec Type

```bash
semanage fcontext -a -t mysvcd_exec_t "/opt/mypkg/mysvcd"
restorecon -v /opt/mypkg/mysvcd
```

---

## Create the Main Module

### File: `myhttpd_mod_wl.te` (Simple)

```te
module myhttpd_mod_wl 1.0;

require {
    type httpd_t;
    type httpd_wls_port_t;
    class tcp_socket name_connect;
}

allow httpd_t httpd_wls_port_t:tcp_socket name_connect;
```

Or..

### File: `myhttpd_mod_wl.te` (Includes Predefined Label)

```te
module myhttpd_mod_wl 1.0;

require {
    type httpd_t;
    type httpd_wls_port_t;
    type afs3_callback_port_t;
    class tcp_socket name_connect;
}

allow httpd_t httpd_wls_port_t:tcp_socket name_connect;
allow httpd_t afs3_callback_port_t:tcp_socket name_connect;
```

### Or.. if the Domain Type is your own `mysvcd_t`, File: `myhttpd_mod_wl.te` is like this
> Using the same module name though it should be e.g., `mysvcd_mod_wl` in this case, to simplify the subsequent explanation.

```te
module myhttpd_mod_wl 1.0;

require {
    type mysvcd_t;
    type httpd_wls_port_t;
    class tcp_socket name_connect;
}

allow mysvcd_t httpd_wls_port_t:tcp_socket name_connect;
```

---

## SE Module Build and Install (Common)

```bash
checkmodule -M -m -o myhttpd_mod_wl.mod myhttpd_mod_wl.te
semodule_package -o myhttpd_mod_wl.pp -m myhttpd_mod_wl.mod
semodule -i myhttpd_mod_wl.pp

# Verify installation
semodule -lfull | grep myhttpd_mod_wl
ls -l /var/lib/selinux/targeted/active/modules/*/myhttpd_mod_wl

# Check actual permission rule
sesearch --allow -s httpd_t -t httpd_wls_port_t -c tcp_socket -p name_connect
# (If using automatic audit2allow)
sesearch --allow -s httpd_t -t unreserved_port_t -c tcp_socket -p name_connect
```

---

## Port Assignment (for Manual Build)

```bash
semanage port -a -t httpd_wls_port_t -p tcp 7003
semanage port -a -t httpd_wls_port_t -p tcp 7005
```

### Verify Assignment

```bash
echo $(semanage port -l | awk '$1=="httpd_wls_port_t" && $2=="tcp" {$1=$2=""; print $0}')
```

---

## Start and Verify with systemd (in the case of your own domain type `mysvcd_t`)

Start your service via systemd, and check the running process label:

```bash
systemctl start mysvcd.service
ps -Z -C mysvcd
```
You should see `mysvcd_t` in the process label.

---

## Uninstall the Module (if you ought to do in the future...)

```bash
semodule -r myhttpd_mod_wl
semodule -lfull | grep myhttpd_mod_wl
```
