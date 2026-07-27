#!/bin/bash
#
# add_matrix_user.sh
#
# Helper for admins to create additional Matrix (Synapse) accounts on an
# existing deployment created by deploy_matrix.sh. Wraps Synapse's
# register_new_matrix_user tool, which uses the registration_shared_secret
# in homeserver.yaml, so it works even though open registration is disabled.
#
# Usage:
#   ./add_matrix_user.sh                          # interactive prompts
#   ./add_matrix_user.sh -u alice                 # prompt only for password/admin
#   ./add_matrix_user.sh -u alice -p 'S3cret!' -a # fully non-interactive admin
#   ./add_matrix_user.sh -u bob -p 'S3cret!'      # fully non-interactive, regular user
#
# Flags:
#   -u USERNAME   Matrix localpart (e.g. "alice" for @alice:yourdomain)
#   -p PASSWORD   Account password (skips the password prompt)
#   -a            Make the account an administrator
#   -c PATH       Path to docker-compose project dir (default: ~/matrix)
#   -h            Show this help text
#
set -euo pipefail

PROJECT_DIR="${HOME}/matrix"
CONTAINER_NAME="matrix-synapse"
USERNAME=""
PASSWORD=""
MAKE_ADMIN="no"

usage() {
    grep '^#' "$0" | sed -n '2,/^set -e/p' | sed '$d; s/^# \{0,1\}//'
    exit 0
}

while getopts ":u:p:c:ah" opt; do
    case "${opt}" in
        u) USERNAME="${OPTARG}" ;;
        p) PASSWORD="${OPTARG}" ;;
        a) MAKE_ADMIN="yes" ;;
        c) PROJECT_DIR="${OPTARG}" ;;
        h) usage ;;
        \?) echo "Unknown option: -${OPTARG}" >&2; exit 1 ;;
        :) echo "Option -${OPTARG} requires an argument." >&2; exit 1 ;;
    esac
done

HOMESERVER_YAML="${PROJECT_DIR}/synapse/data/homeserver.yaml"

# ---------------------------------------------------------------------------
# Sanity checks
# ---------------------------------------------------------------------------

if [[ ! -f "${HOMESERVER_YAML}" ]]; then
    echo "ERROR: Could not find homeserver.yaml at ${HOMESERVER_YAML}" >&2
    echo "Pass the correct project directory with -c, e.g.:" >&2
    echo "    $0 -c /path/to/matrix" >&2
    exit 1
fi

if ! docker ps --format '{{.Names}}' | grep -qx "${CONTAINER_NAME}"; then
    echo "ERROR: Container '${CONTAINER_NAME}' is not running." >&2
    echo "Start the stack first, e.g.:" >&2
    echo "    cd ${PROJECT_DIR} && docker compose up -d" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Gather input
# ---------------------------------------------------------------------------

echo "=== Matrix Account Creation ==="
echo

if [[ -z "${USERNAME}" ]]; then
    read -rp "New user localpart (e.g. 'alice'): " USERNAME
fi

if [[ -z "${USERNAME}" ]]; then
    echo "ERROR: A username is required." >&2
    exit 1
fi

if [[ -z "${PASSWORD}" ]]; then
    read -rsp "Password for ${USERNAME} (leave empty to auto-generate): " PASSWORD
    echo
    if [[ -z "${PASSWORD}" ]]; then
        PASSWORD="$(openssl rand -base64 18)"
        echo "No password entered - generated one automatically."
    fi
fi

if [[ "${MAKE_ADMIN}" == "no" ]]; then
    read -rp "Make this account an administrator? [y/N]: " ADMIN_ANSWER
    case "${ADMIN_ANSWER,,}" in
        y|yes) MAKE_ADMIN="yes" ;;
        *) MAKE_ADMIN="no" ;;
    esac
fi

# ---------------------------------------------------------------------------
# Create the account
# ---------------------------------------------------------------------------

REGISTER_ARGS=(
    register_new_matrix_user
    http://localhost:8008
    -c /data/homeserver.yaml
    -u "${USERNAME}"
    -p "${PASSWORD}"
)

if [[ "${MAKE_ADMIN}" == "yes" ]]; then
    REGISTER_ARGS+=(-a)
else
    REGISTER_ARGS+=(--no-admin)
fi

echo
echo "Creating account @${USERNAME}:... (admin: ${MAKE_ADMIN}) ..."

docker exec -i "${CONTAINER_NAME}" "${REGISTER_ARGS[@]}"

echo
echo "=== Account created ==="
echo "Username:  ${USERNAME}"
echo "Password:  ${PASSWORD}"
echo "Admin:     ${MAKE_ADMIN}"
echo
echo "Share these credentials with the user securely (e.g. a password manager"
echo "or a channel other than plain email/chat), and have them change the"
echo "password after first login if this was auto-generated."