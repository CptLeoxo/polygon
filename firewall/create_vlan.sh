#!/bin/sh
# Create a student VLAN interface with its gateway on the FreeBSD firewall.
# Install as /usr/local/sbin/create_vlan.sh (root:wheel, mode 0750).
#
#   create_vlan.sh <student_id 1-254> <parent_if>
#   e.g. create_vlan.sh 12 igb3  ->  igb3.22 with 10.12.0.1/16
set -eu

# Must match VLAN_BASE in scripts/render_lab.py.
VLAN_BASE=10

usage() {
  echo "usage: $0 <student_id 1-254> <parent_if>" >&2
  exit 1
}

[ $# -eq 2 ] || usage
ID="$1"
PARENT="$2"

case "$ID" in ''|*[!0-9]*|0*) usage ;; esac
[ "$ID" -ge 1 ] && [ "$ID" -le 254 ] || usage
case "$PARENT" in ''|*[!A-Za-z0-9]*) usage ;; esac

VLAN=$((VLAN_BASE + ID))
GW="10.${ID}.0.1/16"
IFNAME="${PARENT}.${VLAN}"

if ifconfig "$IFNAME" >/dev/null 2>&1; then
  echo "VLAN ${VLAN} already exists (${IFNAME})."
  exit 0
fi

echo ">>> Creating VLAN ${VLAN} on ${PARENT}"
ifconfig "$IFNAME" create vlan "$VLAN" vlandev "$PARENT"
ifconfig "$IFNAME" inet "$GW" up
echo "Interface ${IFNAME} up with ${GW}"
