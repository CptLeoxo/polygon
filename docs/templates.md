# Building the lab templates

Intentionally vulnerable machines: keep them on isolated student VLANs only.

## Metasploitable 2

```sh
VMID=142
mkdir -p /var/lib/vz/images/$VMID && cd /var/lib/vz/images/$VMID
wget https://sourceforge.net/projects/metasploitable/files/Metasploitable2/metasploitable-linux-2.0.0.zip
unzip metasploitable-linux-2.0.0.zip
cd Metasploitable2-Linux/
qemu-img convert -O qcow2 Metasploitable.vmdk Metasploitable.qcow2

qm create $VMID --name Meta2-template --memory 4096 --cores 2 \
   --net0 virtio,bridge=vmbr1 --boot c --bootdisk ide0
qm importdisk $VMID Metasploitable.qcow2 local-lvm
qm set $VMID --ide0 local-lvm:vm-$VMID-disk-0
qm template $VMID
```

If the template should live on Ceph, import to your Ceph storage instead of `local-lvm`
so that clones can start on any node.

## Metasploitable 3

Build the VM with the upstream Metasploitable 3 project (VirtualBox/Vagrant), export it as
an OVA, and import it into Proxmox (`qm importovf`), then `qm template <vmid>`. Use the
`e1000` NIC model, as in `labs/lab3-metasploitable3.yaml`.

## DVWA

Install DVWA in a Debian/Ubuntu VM by following the official guide:
<https://github.com/digininja/DVWA>. Notes:

- Use a **dedicated, unique database password**, not the sample one from the guide.
- DVWA needs `allow_url_include = On` in `php.ini` for its file-inclusion exercises. That
  setting is only acceptable because the machine is isolated.
- Do not `chmod -R 777` the web root; give `www-data` write access only to the folders DVWA
  asks for (uploads, config).
- Convert the finished VM to a template: `qm template <vmid>`.

## Kali student template

Install Kali, update it, remove history and SSH host keys, set a **per-course** password or
inject SSH keys at deployment time, then `qm template <vmid>`.

## Moving disks between nodes / into Ceph

```sh
# Stream a local LVM disk directly into Ceph (pool "ceph")
qemu-img convert -p -f raw /dev/<vg>/vm-<vmid>-disk-0 -O raw - \
  | ssh root@<node> 'rbd import - ceph/vm-<new_vmid>-disk-0'

# Copy a qcow2 image to another node
scp /var/lib/vz/images/<vmid>/vm-<vmid>-disk-0.qcow2 root@<node>:/tmp/
```

After importing a disk, edit `/etc/pve/nodes/<node>/qemu-server/<vmid>.conf` to attach it.
