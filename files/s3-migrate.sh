#!/bin/bash

# S3 Migration Script for Perforce Depots
# Migrates local depot archives to S3 (Railway Bucket) and refreshes credentials.
# Called from init.sh after server is running and authenticated.

# Exit early if S3 is not configured
if [ -z "$S3_ENDPOINT" ] || [ -z "$S3_BUCKET" ] || [ -z "$S3_ACCESS_KEY_ID" ] || [ -z "$S3_SECRET_ACCESS_KEY" ]; then
    echo "S3 not configured, skipping depot migration."
    exit 0
fi

echo "S3 depot migration starting..."

# Resolve the actual depot root from Perforce (may differ from $P4DEPOTS env var).
# The value can be a relative path (e.g. ../archives) resolved from P4ROOT.
P4ROOT_ACTUAL=$(p4 info | grep "^Server root:" | sed 's/^Server root:[[:space:]]*//')
DEPOT_ROOT_RAW=$(p4 configure show server.depot.root 2>/dev/null | grep "^server.depot.root=" | sed 's/^server.depot.root=//' | sed 's/ .*//')

if [ -n "$DEPOT_ROOT_RAW" ]; then
    if [[ "$DEPOT_ROOT_RAW" = /* ]]; then
        DEPOT_ROOT="$DEPOT_ROOT_RAW"
    else
        # Relative path — resolve from P4ROOT
        DEPOT_ROOT=$(cd "$P4ROOT_ACTUAL" && cd "$DEPOT_ROOT_RAW" 2>/dev/null && pwd)
    fi
else
    DEPOT_ROOT="$P4ROOT_ACTUAL"
fi
echo "Depot root: $DEPOT_ROOT"

# Configure AWS CLI credentials
export AWS_ACCESS_KEY_ID="$S3_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$S3_SECRET_ACCESS_KEY"
export AWS_DEFAULT_REGION="${S3_REGION:-auto}"

# Railway Buckets (and most S3-compatible stores) require path-style addressing.
# Virtual-hosted-style would try to resolve <bucket>.storage.railway.app which doesn't exist.
aws configure set default.s3.addressing_style path

# Perforce S3 Address format (exported so awk can read via ENVIRON)
# URL includes bucket path for path-style addressing (required by Railway Buckets / S3-compatible stores).
# Region set to "auto" for SigV4 signing compatibility.
export S3_ADDR_LINE="Address: s3,url:${S3_ENDPOINT}/${S3_BUCKET},bucket:${S3_BUCKET},region:auto,accessKey:${S3_ACCESS_KEY_ID},secretKey:${S3_SECRET_ACCESS_KEY}"

# set_depot_address: Sets the Address field on a depot spec.
# Strips any existing Address line, then injects the new one after the Type line.
# Uses awk with ENVIRON to avoid sed/shell special-character issues with credentials.
# Runs in a subshell with pipefail so any pipeline stage failure is caught.
set_depot_address() {
    local depot_name="$1"
    (
        set -o pipefail
        p4 depot -o "$depot_name" | awk '
            /^Address:/ { next }
            /^Type:/ { print; print ENVIRON["S3_ADDR_LINE"]; next }
            { print }
        ' | p4 depot -i
    )
}

# remove_depot_address: Removes the Address field from a depot spec (reverts to local storage).
remove_depot_address() {
    local depot_name="$1"
    (
        set -o pipefail
        p4 depot -o "$depot_name" | awk '
            /^Address:/ { next }
            { print }
        ' | p4 depot -i
    )
}

MIGRATION_FAILED=0

# Process each depot (process substitution keeps loop in main shell)
while read -r line; do
    name=$(echo "$line" | awk '{print $2}')
    type=$(echo "$line" | awk '{print $4}')

    # Guard against empty depot name (malformed output could cause rm -rf on parent dir)
    if [ -z "$name" ]; then
        continue
    fi

    # Skip depot types without local file storage
    case "$type" in
        spec|unload|remote|trait)
            continue
            ;;
    esac

    # Check if depot already has an S3 address
    current_address=$(p4 depot -o "$name" | grep "^Address:" | sed 's/^Address:[[:space:]]*//')

    if echo "$current_address" | grep -q "^s3,"; then
        # Depot has S3 Address — check if S3 actually has data for this depot
        s3_file_count=$(aws s3 ls "s3://${S3_BUCKET}/${name}/" --endpoint-url "$S3_ENDPOINT" 2>/dev/null | head -1 | wc -l)

        if [ "$s3_file_count" -eq 0 ]; then
            # S3 is empty for this depot — revert to local storage
            echo "WARNING: Depot $name has S3 Address but no data in S3 — reverting to local storage"
            if remove_depot_address "$name"; then
                echo "Reverted depot to local storage: $name"
            else
                echo "ERROR: Failed to revert depot: $name"
                MIGRATION_FAILED=1
            fi
        else
            # S3 has data — refresh credentials
            echo "Refreshing S3 credentials for depot: $name"
            if ! set_depot_address "$name"; then
                echo "ERROR: Failed to refresh credentials for depot: $name"
                MIGRATION_FAILED=1
            fi
        fi
    else
        # Local depot — migrate to S3 if it has files
        local_path="${DEPOT_ROOT}/${name}"

        if [ -d "$local_path" ] && [ "$(ls -A "$local_path" 2>/dev/null)" ]; then
            echo "Migrating depot to S3: $name"

            # Sync local files to S3
            if ! aws s3 sync "$local_path/" "s3://${S3_BUCKET}/${name}/" --endpoint-url "$S3_ENDPOINT"; then
                echo "ERROR: Failed to sync depot to S3: $name"
                MIGRATION_FAILED=1
                continue
            fi

            # Update depot Address to S3
            if ! set_depot_address "$name"; then
                echo "ERROR: Failed to set S3 Address for depot: $name — local files preserved"
                MIGRATION_FAILED=1
                continue
            fi
            echo "Updated depot Address for: $name"

            # Verify depot integrity (skip if depot has no submitted files)
            if p4 files "//${name}/..." >/dev/null 2>&1; then
                echo "Verifying depot: $name"
                if p4 verify "//${name}/..." 2>&1; then
                    echo "Verification passed for: $name"
                    rm -rf "$local_path"
                    echo "Removed local files for: $name"
                else
                    echo "WARNING: Verification had issues for: $name — local files preserved"
                    MIGRATION_FAILED=1
                fi
            else
                echo "No submitted files in depot: $name — skipping verify"
                rm -rf "$local_path"
                echo "Removed local files for: $name"
            fi
        else
            echo "Skipping depot $name — no local files at $local_path"
        fi
    fi
done < <(p4 depots)

if [ "$MIGRATION_FAILED" -ne 0 ]; then
    echo "S3 depot migration completed with warnings."
else
    echo "S3 depot migration complete."
fi
