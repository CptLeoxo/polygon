#!/usr/bin/env bash
# Polygon lab orchestrator: render main.tf, run Terraform, tear down.
#
#   lab.sh create  <labs/labX.yaml> (--count N | --ids 3,7,10-12)
#   lab.sh destroy <lab-name>
#   lab.sh status  <lab-name>
#
# Credentials come from terraform/terraform.tfvars (override the path with
# POLYGON_TFVARS) or from TF_VAR_* environment variables.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
TF_DIR="$ROOT/terraform"
TF="${TERRAFORM_BIN:-terraform}"
VARFILE="${POLYGON_TFVARS:-$TF_DIR/terraform.tfvars}"

die() { echo "error: $*" >&2; exit 1; }

usage() {
  cat >&2 <<USAGE
usage:
  $0 create  <lab.yaml> (--count N | --ids LIST)
  $0 destroy <lab-name>
  $0 status  <lab-name>
USAGE
  exit 2
}

var_args=()
[ -f "$VARFILE" ] && var_args=(-var-file="$VARFILE")

lock_dir() {
  # one operation per lab at a time
  if command -v flock >/dev/null 2>&1; then
    exec 9>"$1/.lock"
    flock -n 9 || die "another operation is running for this lab"
  fi
}

lab_dir_for() {
  [[ "$1" =~ ^[a-z][a-z0-9-]{0,30}$ ]] || die "invalid lab name: $1"
  local dir="$TF_DIR/labs/$1"
  [ -d "$dir" ] || die "no such lab: $1 ($dir)"
  printf '%s' "$dir"
}

cmd_create() {
  [ $# -ge 3 ] || usage
  local lab_file="$1"; shift
  [ -f "$lab_file" ] || die "lab definition not found: $lab_file"

  local lab_dir
  lab_dir="$(python3 "$SCRIPT_DIR/render_lab.py" --lab "$lab_file" "$@")"

  lock_dir "$lab_dir"
  cd "$lab_dir"
  "$TF" init -input=false
  "$TF" plan -input=false -out=tfplan ${var_args[@]+"${var_args[@]}"}
  "$TF" apply -input=false tfplan
  rm -f tfplan
}

cmd_destroy() {
  [ $# -eq 1 ] || usage
  local lab_dir
  lab_dir="$(lab_dir_for "$1")"
  [ -f "$lab_dir/main.tf" ] || die "$lab_dir/main.tf is missing - nothing to destroy"

  lock_dir "$lab_dir"
  cd "$lab_dir"
  "$TF" init -input=false
  "$TF" destroy -input=false -auto-approve ${var_args[@]+"${var_args[@]}"}
  rm -f main.tf tfplan
  echo "lab '$1' destroyed, main.tf removed"
}

cmd_status() {
  [ $# -eq 1 ] || usage
  local lab_dir
  lab_dir="$(lab_dir_for "$1")"
  cd "$lab_dir"
  "$TF" state list
}

[ $# -ge 1 ] || usage
sub="$1"; shift
case "$sub" in
  create)  cmd_create "$@" ;;
  destroy) cmd_destroy "$@" ;;
  status)  cmd_status "$@" ;;
  *)       usage ;;
esac
