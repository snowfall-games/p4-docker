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

# Configure AWS CLI credentials
export AWS_ACCESS_KEY_ID="$S3_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$S3_SECRET_ACCESS_KEY"
export AWS_DEFAULT_REGION="${S3_REGION:-auto}"

# Railway Buckets (and most S3-compatible stores) require path-style addressing.
# Virtual-hosted-style would try to resolve <bucket>.storage.railway.app which doesn't exist.
aws configure set default.s3.addressing_style path

# Perforce S3 Address format (exported so awk can read via ENVIRON)
export S3_ADDR_LINE="Address: s3,url:${S3_ENDPOINT},bucket:${S3_BUCKET},accessKey:${S3_ACCESS_KEY_ID},secretKey:${S3_SECRET_ACCESS_KEY}"

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

MIGRATION_FAILED=0

# Process each depot (process substitution keeps loop in main shell)
while read -r line; do
    name=$(echo "$line" | awk '{print $2}')
    type=$(echo "$line" | awk '{print $4}')

    # Guard against empty depot name (malformed output could cause rm -rf on parent dir)
    if [ -z "$name" ]; then
        continue
    fi

    # Skip non-local depot types
    case "$type" in
        spec|unload|archive|stream|remote|graph|tangent|trait)
            continue
            ;;
    esac

    # Check if depot already has an S3 address
    current_address=$(p4 depot -o "$name" | grep "^Address:" | sed 's/^Address:[[:space:]]*//')

    if echo "$current_address" | grep -q "^s3,"; then
        # Depot already on S3 — refresh credentials
        echo "Refreshing S3 credentials for depot: $name"
        if ! set_depot_address "$name"; then
            echo "ERROR: Failed to refresh credentials for depot: $name"
            MIGRATION_FAILED=1
        fi
    else
        # Local depot — migrate to S3
        local_path="${P4DEPOTS}/${name}"

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
            # No local files but not yet on S3 — just set the Address
            echo "Setting S3 Address for depot: $name"
            if ! set_depot_address "$name"; then
                echo "ERROR: Failed to set S3 Address for depot: $name"
                MIGRATION_FAILED=1
            fi
        fi
    fi
done < <(p4 depots)

if [ "$MIGRATION_FAILED" -ne 0 ]; then
    echo "S3 depot migration completed with warnings."
else
    echo "S3 depot migration complete."
fi
