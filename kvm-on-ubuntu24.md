# KVM on Ubuntu Linux 24.04 (and 22.04 mayby)

## 1. 基本方針

* **仮想マシンはLVM論理ボリュームで管理**
  - 高速スナップショット・コピーが可能
  - バックアップと再構築が容易
* **ネットワークはブリッジ接続**
  - ゲストがLANの一員として振る舞える

---

## 2. ホスト初期セットアップ

### 必要パッケージ

```bash
apt update
apt install qemu-kvm libvirt-daemon-system libvirt-clients \
                 bridge-utils virt-manager virtinst cloud-image-utils
```

* **virt-manager** → GUI管理（VNC接続、スナップショット）
* **cloud-image-utils** → クラウドイメージ展開（小さなVM構築が速い）

### Ubuntu Pro + ESM確認

```bash
pro status
```

* `esm-apps` / `esm-infra` が `enabled` になっていることを確認

---

## 3. LVMの構成

### 実験用ボリュームグループ作成

※SSDやNVMe上の空き領域を使う

```bash
# 例: /dev/nvme0n1p3 を実験用に確保済みとする
pvcreate /dev/nvme0n1p3
vgcreate vg_vm /dev/nvme0n1p3
```

### VM用の論理ボリューム作成例

```bash
# 20GBのディスク領域を "testvm" 用に作成
lvcreate -L 20G -n testvm vg_vm
```

---

## 4. ネットワーク設定（ブリッジ）

### Disable `virbr0`

```bash
virsh net-autostart default --disable
virsh net-destroy default
```

### Delete or disable NetworkManager profiles

1. **Find the NetworkManager profile**:

   ```bash
   nmcli connection show
   ```

2. **Delete or disable it**:

   * Delete:

     ```bash
     nmcli connection delete "Ethernet1"
     ```
   * Or disable without deleting:

     ```bash
     nmcli connection modify "Ethernet1" connection.autoconnect no
     nmcli connection down "Ethernet1"
     mv /etc/netplan/90-NM-xxxxxxxx.yaml{,.disabled}
     # 90-NM-xx..yaml is a yaml file generated from NM configuration. To locate the file name, read the contents.
     # You must also do the same to NM WiFi connections if exist. **Any yaml files with `renderer: NetworkManager` must not exist!
     ```
     > **Need to re-enable it?**
     > ```bash
     > mv /etc/netplan/90-NM-xxxxxxxx.yaml{.disabled,}
     > nmcli connection modify "Ethernet1" connection.autoconnect yes
     > nmcli connection up "Ethernet1"
     > ```
     > > See also **How to switch between netplan and NetworkManager**

3. **Disable and stop NetworkManager service**:

     ```bash
     systemctl disable NetworkManager.service --now
     ```

### Create the netplan config for a bridge backed by Ethernet

* Static address, gateway, and DNS are on the bridge, **not** the NIC.
* The physical interface (`enp3s0`) has no IP assigned — it’s just a bridge port.

 **Enable and activate `systemd-networkd.service`**

```bash
systemctl enable systemd-networkd --now
```

**`/etc/netplan/01-br0.yaml`**

```yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    enp3s0:
      dhcp4: no
      dhcp6: no
  bridges:
    br0:
      interfaces: [enp3s0]
      addresses:
        - 192.168.1.5/24
      routes:
        - to: default
          via: 192.168.1.252
      nameservers:
        addresses:
          - 202.224.32.1
          - 202.224.32.2
```

**Apply the config**

```bash
netplan generate
netplan apply
  
ip addr show br0
bridge link
```

**Tune the physical network interface**

  1. **`/etc/udev/rules.d/99-tune-enp3s0.rule`**  

     ```bash
     ACTION=="add", SUBSYSTEM=="net", KERNEL=="enp3s0", RUN+="/usr/sbin/ethtool -K enp3s0 gro off gso off tso off"
     ACTION=="add", SUBSYSTEM=="net", KERNEL=="enp3s0", RUN+="/usr/sbin/ethtool -G enp3s0 rx 2048 tx 2048"
     ```

  2. **Apply the rule**

     ```bash
     udevadm control --reload
     udevadm trigger --action=add
     ```
     or reboot.

**Update libvirt to use `br0`**

```bash
virsh net-define /dev/stdin <<EOF
<network>
  <name>br0-net</name>
  <forward mode="bridge"/>
  <bridge name="br0"/>
</network>
EOF

virsh net-list --all
virsh net-dumpxml br0-net
virsh net-autostart br0-net
virsh net-start br0-net
virsh net-info br0-net
```

---

**How to switch between netplan and NetworkManager**

#### Switch to netplan bridge mode (Mode A)
```bash
nmcli connection modify "Ethernet1" connection.autoconnect no
nmcli connection down "Ethernet1" || true
mv /etc/netplan/90-NM-xxxxxxxx.yaml{,.disabled}
# 90-NM-xx..yaml is a yaml file generated from NM configuration. To locate the file name, read the contents.

mv /etc/netplan/01-br0.yaml.disabled /etc/netplan/01-br0.yaml
netplan generate
netplan apply
```

#### Switch to NetworkManager mode (Mode B)
```bash
mv /etc/netplan/01-br0.yaml /etc/netplan/01-br0.yaml.disabled
netplan generate
netplan apply

mv /etc/netplan/90-NM-xxxxxxxx.yaml{.disabled,}
nmcli connection modify "Ethernet1" connection.autoconnect yes
nmcli connection up "Ethernet1"
```

---

## 5. VM作成例

### ISOから直接インストール

```bash
lvcreate -L 20G -n testvm vg_vm
virt-install \
  --name testvm \
  --memory 4096 \
  --vcpus 2 \
  --boot uefi \
  --disk path=/dev/vg_vm/testvm,bus=virtio \
  --cdrom /path/to/ubuntu-22.04.iso \
  --os-variant ubuntu22.04 \
  --network bridge=br0,model=virtio \
  --graphics spice
```

### クラウドイメージから即展開（高速）

```bash
# Ubuntu 22.04 クラウドイメージ取得
wget https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img

# LVMに展開
qemu-img convert -f qcow2 -O raw jammy-server-cloudimg-amd64.img /dev/vg_vm/testvm
```

`cloud-init`を使えば即ログイン可能。

---

## 6. Snapshot management

### Backup, Restore, Remove

  * Create a snapshot (Backup)
    ```bash
    lvcreate -s -n testvm_snap -L 4G /dev/vg_vm/testvm
    ```

  * Merge the snapshot (Restore/Revert)
    ```bash
    # Check LVs are not mounted
    findmnt -o SOURCE,TARGET /dev/vg_vm/testvm
    findmnt -o SOURCE,TARGET /dev/vg_vm/testvm_snap
    # If they are, stop the VM using it.
    
    # Deactivate the LVs
    lvchange --activate n vg_vm/testvm
    lvchange --activate n vg_vm/testvm_snap
    
    # Merge the snapshot
    lvconvert --merge testvm_snap
    
    # Activate the LV
    lvchange --activate y vg_vm/testvm
    ```

  * Watch the usage% of the snapshot LV
    ```bash
    lvs -a -o +data_percent
    # Example output
    LV            VG       Attr       LSize   ... Data% 
    testvm_snap  vg_vm    owi-aos---  48.00g
    testvm_snap  vg_vm    swi-a-s---   4.00g      1.14
    ```
    If growing higher, simply extend the snapshot LV. (Extending the snapshot LV does not disrupt the running VM or the snapshot itself)
    ```bash
    lvextend -L +2G /dev/vg_vm/testvm_snap
    ```

  * Remove a snapshot (Foreget)
    This just throws away the snapshot LV holding the journals since it was made. No *"Delta disk integration to main disk (vSphere)"* happens in LVM because the main LV stays alive and written even after the snapshot creation.
    ```bash
    lvremove /dev/vg_vm/testvm_snap
    ```

### 複製して別VM化

```bash
lvcreate -n testvm_clone -L 20G vg_vm
dd if=/dev/vg_vm/testvm of=/dev/vg_vm/testvm_clone bs=4M status=progress
# or, if the LV contains lots of unused blocks (zeros), you can save time by:
dd if=/dev/vg_vm/testvm of=/dev/vg_vm/testvm_clone bs=4M conv=sparse status=progressv
```

---

## 7. 運用ベストプラクティス

1. **VMは用途ごとにスナップショットベースで管理**

   * 実験で壊したら即ロールバック
2. **バックアップはLVMのスナップショットを外部にdd**

   * 速度優先なら`lvconvert --merge`で復旧
3. **ネットワークは基本ブリッジ、実験用にNATも併用可能**
4. **仮想ディスクは原則LVM直置き**

   * qcow2より高速、SSDならIO性能を活かせる

---
