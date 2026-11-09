# Polygon

**Automated, isolated cyber-range labs for security education: Moodle → Terraform → Proxmox.**

Polygon provisions per-student virtual labs (Kali, DVWA, Metasploitable, …) on a Proxmox/Ceph cluster. Every student gets their own VLAN and address space behind a FreeBSD `pf` firewall, with WireGuard access for administrators. A lab is described in a small YAML file, rendered into Terraform, applied, and removed again with one command.

> ⚠️ **Warning:** Polygon deliberately deploys **intentionally vulnerable** machines (DVWA, Metasploitable). Never expose them to the internet or to a production network. See [Security notes](#security-notes).

## Features

- One isolated network (VLAN + /16) per student, created on demand and removed on teardown
- Labs defined as code (`labs/*.yaml`) and rendered to Terraform for *N* students
- Linked clones from templates for fast, space-efficient deployment
- Students spread round-robin across Proxmox nodes, with stable placement
- FreeBSD `pf` firewall: NAT, admin allow-list, WireGuard VPN, student-to-student isolation
- Predictable addressing: IP, VLAN and VMID are all derived from the student ID

## Architecture

```text
        [ Moodle -> Terraform -> Proxmox ]
                       │
              ┌────────┴────────┐
              │     fw-main     │
              │  Main firewall  │
              │    (FreeBSD)    │
              │-----------------│
              │ igb0  WAN       │  203.0.113.2/29   (example)
              │ igb1  MGMT      │  172.16.10.2/24   (example)
              │ igb3  TRUNK     │  tagged student VLANs
              │ wg0   VPN       │  192.168.200.1/24 (example)
              └────────┬────────┘
                       │  NAT
                  [ Internet ]
                       │  NAT
              ┌────────┴────────┐
              │    fw-client    │
              │ Secondary FW    │
              │    (FreeBSD)    │
              │-----------------│
              │ igb0  WAN       │  DHCP
              │ igb2  MGMT      │  192.168.33.5/24  (example)
              │ igb3  TRUNK     │  tagged VLANs
              │ wg0   VPN       │  192.168.200.2/24 (example)
              └────────┬────────┘
                       │
              ┌────────┴────────┐
              │ Switch (L2/VLAN)│
              └────────┬────────┘
                       │  trunk / tagged VLANs
                [ Student PCs / clients ]
```

> All IP addresses and hostnames in this repository are **examples**. Replace them with your own.

| Component | Role |
|---|---|
| Moodle | Front end where labs are requested and removed |
| Trainer (control node) | Runs `scripts/lab.sh`, Terraform and the renderer |
| Proxmox cluster | KVM hypervisors, VLAN-aware bridge `vmbr1` for lab traffic |
| Ceph | Shared storage for VM disks and templates |
| fw-main | Main FreeBSD firewall: NAT, VPN, per-student gateways |
| fw-client | Secondary FreeBSD firewall for client-side access |

## Addressing scheme

Every student has an ID (`student_id`, 1–254) that drives all addressing:

| Item | Formula | Example (student 3, lab 1, VM 2) |
|---|---|---|
| VM IP | `10.<student_id>.<lab_id>.<vm_id>` | `10.3.1.2` |
| Gateway (on firewall) | `10.<student_id>.0.1/16` | `10.3.0.1/16` |
| VLAN tag | `student_id + 10` | `13` |
| VMID | `lab_id * 100000 + student_id * 100 + vm_id` | `100302` |
| VM name | `<lab>-s<student_id>-<vm name>` | `lab1-s3-dvwa` |
| Node | `nodes[(student_id - 1) % len(nodes)]` | 3rd node |

Limits: `lab_id` 1–99, `vm id` 1–99, `student_id` 1–254.

## Repository layout

```text
polygon/
├── labs/                       # Lab definitions (one YAML per lab)
│   ├── lab1-dvwa.yaml
│   ├── lab2-metasploitable2.yaml
│   └── lab3-metasploitable3.yaml
├── scripts/
│   ├── lab.sh                  # create / destroy / status
│   └── render_lab.py           # YAML + templates -> terraform/labs/<lab>/main.tf
├── terraform/
│   ├── templates/
│   │   ├── base.tf             # provider + variables (copied once)
│   │   └── lab.tf.j2           # per-student resources (rendered N times)
│   └── terraform.tfvars.example
├── firewall/
│   ├── create_vlan.sh          # runs on the firewall
│   ├── destroy_vlan.sh
│   ├── fw-main/                # rc.conf, pf.conf, wg0.conf examples
│   └── fw-client/
├── proxmox/
│   └── interfaces.example      # network config of one Proxmox node
├── docs/
│   ├── setup.md                # full installation guide
│   └── templates.md            # building DVWA / Metasploitable / Kali templates
├── requirements.txt
└── LICENSE
```

## Quick start

Prerequisites: a Proxmox cluster with the lab templates, the FreeBSD firewall set up, Terraform ≥ 1.3, Python ≥ 3.9. The full walkthrough is in **[docs/setup.md](docs/setup.md)**.

```sh
python3 -m venv .venv && . .venv/bin/activate
pip install -r requirements.txt

cp terraform/terraform.tfvars.example terraform/terraform.tfvars   # edit: API token, firewall host

./scripts/lab.sh create  labs/lab1-dvwa.yaml --count 5         # students 1..5
./scripts/lab.sh create  labs/lab1-dvwa.yaml --ids 3,7,10-12   # specific student IDs
./scripts/lab.sh status  lab1
./scripts/lab.sh destroy lab1                                  # destroys VMs, VLANs and main.tf
```

### Lab definition

```yaml
name: lab1
lab_id: 1
nodes: [pve01, pve02, pve03]

vms:
  - id: 1
    name: kali
    template: Student32-template
    memory: 4096
    disk: { type: scsi, size: 32, storage: ceph }
  - id: 2
    name: dvwa
    template: DVWA-template
```

Optional per-VM keys and their defaults: `cores: 2`, `sockets: 1`, `memory: 4096`, `qemu_os: l26`, `nic_model: virtio`, `bridge: vmbr1`, `full_clone: false` (linked clone), `cloudinit: false` (set an IP via cloud-init), `disk: {type: scsi, size: 32, storage: ceph}`.

## How it works

1. A request arrives for *X* students and a lab (from Moodle or by hand).
2. `render_lab.py` writes `terraform/labs/<lab>/main.tf` = `base.tf` once + `lab.tf.j2` rendered for every student.
3. `lab.sh` runs `terraform init`, `plan` and `apply`.
4. For every student Terraform first creates the VLAN gateway on the firewall (`create_vlan.sh` over SSH), then clones the VMs and tags them with the student's VLAN.
5. On teardown `terraform destroy` removes the VMs, then the VLAN (`destroy_vlan.sh`), and `main.tf` is deleted.

Notes:

- **Linked clones require templates.** An offline template can be linked-cloned; a running VM cannot.
- `create` is declarative: re-running it with a different student list adds new students and removes the ones no longer listed.
- Each lab has its own directory and Terraform state, so labs can be created and destroyed independently.
- Student VLANs are created only when needed, so the firewall does not carry all 254 VLANs permanently.

## Firewall

Example configuration for FreeBSD is in [`firewall/`](firewall/): `rc.conf`, `pf.conf` (NAT, allow-listed admin access, WireGuard, student isolation) and a `wg0.conf` template. WireGuard keys are generated on the host and never stored in the repository:

```sh
umask 077
wg genkey | tee private.key | wg pubkey > public.key
```

Check rules before loading them: `pfctl -nf /etc/pf.conf`.

## Lab machines

| Machine | Purpose |
|---|---|
| Kali (student / trainer) | Attacker workstation |
| [DVWA](https://github.com/digininja/DVWA) | Web vulnerabilities: SQL injection, IDOR, XSS |
| Metasploitable 2 | Classic vulnerable Linux target |
| Metasploitable 3 | Vulnerable target (imported from the upstream build) |

See [docs/templates.md](docs/templates.md) for building the templates.

## Security notes

- **Isolation is the main control.** `pf.conf` blocks student-to-student and student-to-private-network traffic. Verify this after every change to the firewall.
- **No secrets in git.** Use an API token with a dedicated role (not `root@pam`), keep `terraform.tfvars` out of version control, and rotate any credential that has ever been written down in notes or commit history.
- **Least privilege.** The firewall SSH user may run only `create_vlan.sh` and `destroy_vlan.sh` via `sudo`; authentication is by key (ssh-agent).
- **TLS.** `pm_tls_insecure` defaults to `false`; enable it only for an isolated lab with a self-signed certificate.
- **Vulnerable by design.** DVWA and Metasploitable must stay on isolated lab networks with no inbound access from the internet.
- **Use responsibly.** This project is intended for authorised education and training only.

## Roadmap

- [ ] Web front end / Moodle integration (request and release labs)
- [ ] CephFS setup guide
- [ ] Backup and restore strategy for the range
- [ ] Automatic address and VLAN assignment for students
- [ ] Central logging and monitoring (Graylog / Grafana)
- [ ] Active Directory attack labs (Kerberos)
- [ ] Additional web-application labs (brute force, injection, IDOR)

## License

Copyright © 2024–2026. **All rights reserved.** The source is visible for reference only; use, copying, modification and redistribution require prior written permission. See [LICENSE](LICENSE).
