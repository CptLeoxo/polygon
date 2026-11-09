# Setup guide

All hostnames and addresses are examples. Adapt them to your environment.

## 1. Proxmox: API token for Terraform

Do not use `root@pam`. Create a dedicated role, user and token on any cluster node:

```sh
pveum role add Polygon -privs "Datastore.AllocateSpace Datastore.Audit Pool.Allocate \
  Sys.Audit Sys.Console Sys.Modify VM.Allocate VM.Audit VM.Clone VM.Config.CDROM \
  VM.Config.Cloudinit VM.Config.CPU VM.Config.Disk VM.Config.HWType VM.Config.Memory \
  VM.Config.Network VM.Config.Options VM.Migrate VM.Monitor VM.PowerMgmt SDN.Use"

pveum user add terraform@pve
pveum aclmod / -user terraform@pve -role Polygon
pveum user token add terraform@pve polygon --privsep 0
```

The last command prints the token secret **once**. Put it in `terraform/terraform.tfvars`
(`pm_api_token_id = "terraform@pve!polygon"`). The exact privilege list can differ between
Proxmox versions; if Terraform reports a permission error, add the privilege it names.

## 2. Proxmox: templates

Linked clones (`full_clone = false`) require that the source is a **template**
(`qm template <vmid>`). A running VM cannot be linked-cloned. The template names must match
the `template:` values in `labs/*.yaml`:

| Template | Used for |
|---|---|
| `Student32-template` | Kali student workstation |
| `DVWA-template` | Lab 1 target |
| `Meta2-template` | Lab 2 target |
| `Meta3-template` | Lab 3 target |

See [templates.md](templates.md) for how to build them.

## 3. Firewall (FreeBSD)

```sh
pkg install -y sudo wireguard-tools

# helper scripts
install -m 0750 -o root -g wheel firewall/create_vlan.sh  /usr/local/sbin/create_vlan.sh
install -m 0750 -o root -g wheel firewall/destroy_vlan.sh /usr/local/sbin/destroy_vlan.sh

# dedicated SSH user, key-only
pw useradd polygon -m -s /bin/sh -c "Polygon automation"
mkdir -p /home/polygon/.ssh
cat trainer_id_ed25519.pub >> /home/polygon/.ssh/authorized_keys
chown -R polygon:polygon /home/polygon/.ssh && chmod 700 /home/polygon/.ssh && chmod 600 /home/polygon/.ssh/authorized_keys

# sudo for exactly these two scripts, nothing else
cat > /usr/local/etc/sudoers.d/polygon <<'SUDO'
polygon ALL=(root) NOPASSWD: /usr/local/sbin/create_vlan.sh, /usr/local/sbin/destroy_vlan.sh
SUDO
chmod 440 /usr/local/etc/sudoers.d/polygon
visudo -cf /usr/local/etc/sudoers.d/polygon
```

Then adapt `firewall/fw-main/rc.conf.example` and `pf.conf` (copy to `/etc/rc.conf` entries and
`/etc/pf.conf`), create the WireGuard config from `wg0.conf.example`, and check the rules:

```sh
pfctl -nf /etc/pf.conf   # syntax check
pfctl -f /etc/pf.conf    # load
```

Test the VLAN scripts by hand before using Terraform:

```sh
sudo create_vlan.sh 12 igb3     # igb3.22 with 10.12.0.1/16
ifconfig igb3.22
sudo destroy_vlan.sh 12 igb3
```

## 4. Control node ("Trainer")

```sh
# Terraform: https://developer.hashicorp.com/terraform/install
python3 -m venv .venv && . .venv/bin/activate
pip install -r requirements.txt

cp terraform/terraform.tfvars.example terraform/terraform.tfvars   # then edit it

# the key used for the firewall must be loaded into ssh-agent
eval "$(ssh-agent -s)" && ssh-add ~/.ssh/id_ed25519
```

## 5. Create and destroy a lab

```sh
./scripts/lab.sh create  labs/lab1-dvwa.yaml --count 5        # students 1..5
./scripts/lab.sh create  labs/lab1-dvwa.yaml --ids 3,7,10-12  # explicit student ids
./scripts/lab.sh status  lab1
./scripts/lab.sh destroy lab1
```

`create` is declarative: running it again with a different student list adds the new
students and **removes** those no longer listed.

To render without applying (for review): `python3 scripts/render_lab.py --lab labs/lab1-dvwa.yaml --count 2`
writes `terraform/labs/lab1/main.tf`.

If you do not want Terraform to touch the firewall, set `manage_fw_vlan = false` in your tfvars
(you then create the VLAN gateways yourself).
