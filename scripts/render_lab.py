#!/usr/bin/env python3
"""Render a Terraform main.tf for one Polygon lab.

main.tf = terraform/templates/base.tf (once)
        + terraform/templates/lab.tf.j2 (rendered once for all students)

Usage:
    render_lab.py --lab labs/lab1-dvwa.yaml --count 5
    render_lab.py --lab labs/lab1-dvwa.yaml --ids 3,7,10-12

Prints the output directory (and nothing else) on stdout, so shell scripts can
capture it. Progress and errors go to stderr.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

import yaml
from jinja2 import Environment, FileSystemLoader, StrictUndefined

ROOT = Path(__file__).resolve().parent.parent
TEMPLATES = ROOT / "terraform" / "templates"
DEFAULT_OUT = ROOT / "terraform" / "labs"

# Must match VLAN_BASE in firewall/create_vlan.sh and destroy_vlan.sh.
VLAN_BASE = 10
MAX_STUDENT_ID = 254

NAME_RE = re.compile(r"^[a-z][a-z0-9-]{0,30}$")
DISK_TYPES = {"scsi", "ide", "sata", "virtio"}

VM_DEFAULTS = {
    "cores": 2,
    "sockets": 1,
    "memory": 4096,
    "qemu_os": "l26",
    "nic_model": "virtio",
    "bridge": "vmbr1",
    "full_clone": False,  # linked clone - the template must be a template
    "cloudinit": False,
}
DISK_DEFAULTS = {"type": "scsi", "size": 32, "storage": "ceph"}


def die(msg: str) -> "None":
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(1)


def parse_ids(text: str) -> list[int]:
    """'1,2,5-8' -> [1, 2, 5, 6, 7, 8]"""
    ids: set[int] = set()
    for part in text.split(","):
        part = part.strip()
        if not part:
            continue
        m = re.fullmatch(r"(\d+)(?:-(\d+))?", part)
        if not m:
            die(f"invalid student id list: {text!r}")
        lo = int(m.group(1))
        hi = int(m.group(2) or lo)
        if hi < lo:
            die(f"invalid range: {part!r}")
        ids.update(range(lo, hi + 1))
    return sorted(ids)


def load_lab(path: Path) -> dict:
    try:
        raw = yaml.safe_load(path.read_text(encoding="utf-8"))
    except (OSError, yaml.YAMLError) as exc:
        die(f"cannot read {path}: {exc}")
    if not isinstance(raw, dict):
        die(f"{path}: top level must be a mapping")

    for key in ("name", "lab_id", "nodes", "vms"):
        if key not in raw:
            die(f"{path}: missing required key '{key}'")

    if not NAME_RE.match(str(raw["name"])):
        die("name must match ^[a-z][a-z0-9-]{0,30}$")
    if not isinstance(raw["lab_id"], int) or not 1 <= raw["lab_id"] <= 99:
        die("lab_id must be an integer 1-99")
    if not raw["nodes"] or not all(isinstance(n, str) and n for n in raw["nodes"]):
        die("nodes must be a non-empty list of Proxmox node names")
    if not raw["vms"]:
        die("vms must be a non-empty list")

    seen_ids: set[int] = set()
    seen_names: set[str] = set()
    vms = []
    for i, vm in enumerate(raw["vms"], start=1):
        where = f"vms[{i}]"
        for key in ("id", "name", "template"):
            if key not in vm:
                die(f"{where}: missing required key '{key}'")
        if not isinstance(vm["id"], int) or not 1 <= vm["id"] <= 99:
            die(f"{where}: id must be an integer 1-99 (last octet and VMID suffix)")
        if vm["id"] in seen_ids:
            die(f"{where}: duplicate vm id {vm['id']}")
        if not NAME_RE.match(str(vm["name"])):
            die(f"{where}: name must match ^[a-z][a-z0-9-]{{0,30}}$")
        if vm["name"] in seen_names:
            die(f"{where}: duplicate vm name {vm['name']}")
        seen_ids.add(vm["id"])
        seen_names.add(vm["name"])

        merged = {**VM_DEFAULTS, **vm}
        merged["disk"] = {**DISK_DEFAULTS, **(vm.get("disk") or {})}
        if merged["disk"]["type"] not in DISK_TYPES:
            die(f"{where}: disk.type must be one of {sorted(DISK_TYPES)}")
        for key in ("cores", "sockets", "memory"):
            if not isinstance(merged[key], int) or merged[key] < 1:
                die(f"{where}: {key} must be a positive integer")
        if not isinstance(merged["disk"]["size"], int) or merged["disk"]["size"] < 1:
            die(f"{where}: disk.size must be a positive integer (GiB)")
        for key in ("full_clone", "cloudinit"):
            if not isinstance(merged[key], bool):
                die(f"{where}: {key} must be true or false")
        vms.append(merged)

    return {**raw, "vms": vms}


def build_students(ids: list[int], nodes: list[str]) -> list[dict]:
    if not ids:
        die("no students selected")
    bad = [i for i in ids if not 1 <= i <= MAX_STUDENT_ID]
    if bad:
        die(f"student ids must be 1-{MAX_STUDENT_ID}, got {bad}")
    return [
        {
            "id": sid,
            "vlan": sid + VLAN_BASE,
            # Stable placement: the same student always lands on the same node.
            "node": nodes[(sid - 1) % len(nodes)],
        }
        for sid in ids
    ]


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--lab", required=True, type=Path, help="lab definition (YAML)")
    group = ap.add_mutually_exclusive_group(required=True)
    group.add_argument("--count", type=int, help="students 1..N")
    group.add_argument("--ids", help="explicit student ids, e.g. 3,7,10-12")
    ap.add_argument("--out-dir", type=Path, default=DEFAULT_OUT, help="parent directory for generated labs")
    args = ap.parse_args()

    lab = load_lab(args.lab)

    if args.count is not None:
        if args.count < 1:
            die("--count must be >= 1")
        ids = list(range(1, args.count + 1))
    else:
        ids = parse_ids(args.ids)
    students = build_students(ids, lab["nodes"])

    env = Environment(
        loader=FileSystemLoader(TEMPLATES),
        undefined=StrictUndefined,
        trim_blocks=True,
        lstrip_blocks=True,
        keep_trailing_newline=True,
    )
    body = env.get_template("lab.tf.j2").render(lab=lab, students=students)
    base = (TEMPLATES / "base.tf").read_text(encoding="utf-8")

    out_dir = args.out_dir / lab["name"]
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "main.tf").write_text(base.rstrip("\n") + "\n\n" + body, encoding="utf-8")

    print(
        f"rendered lab '{lab['name']}' for {len(students)} student(s) "
        f"({len(students) * len(lab['vms'])} VMs) -> {out_dir / 'main.tf'}",
        file=sys.stderr,
    )
    print(out_dir)


if __name__ == "__main__":
    main()
