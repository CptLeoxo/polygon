#!/bin/sh
# Remove a student VLAN interface from the FreeBSD firewall.
# Install as /usr/local/sbin/destroy_vlan.sh (root:wheel, mode 0750).
#
#   destroy_vlan.sh <student_id 1-254> <parent_if>
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
IFNAME="${PARENT}.${VLAN}"

if ifconfig "$IFNAME" >/dev/null 2>&1; then
  echo "Removing VLAN ${IFNAME}"
  ifconfig "$IFNAME" destroy
else
  echo "VLAN ${IFNAME} not found"
fi
