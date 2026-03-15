#!/bin/bash

# Perforce Maintenance Script
# Runs on every boot: rotates journals via checkpoint and cleans up old logs.
# Called from init.sh after server is running and authenticated.

echo "Perforce maintenance starting..."

# --- Journal Rotation via Checkpoint ---
# A checkpoint snapshots the full database state. Once created, all prior
# journals (incremental transaction logs) are no longer needed for recovery.
# Without this, journals grow indefinitely.

echo "Creating checkpoint (this may take a moment)..."
if p4 admin checkpoint 2>&1; then
    echo "Checkpoint created successfully."

    # The checkpoint is written to the journalPrefix location.
    # After checkpoint, p4d rotates the journal automatically (journal -> journal.N).
    # Remove old rotated journals to reclaim disk. Keep the 2 most recent as safety margin.
    JOURNAL_DIR=$(dirname "$P4JOURNAL")
    if [ -d "$JOURNAL_DIR" ]; then
        # Rotated journals are named journal.N (e.g., journal.1, journal.2)
        # Sort numerically, skip the 2 newest, delete the rest.
        old_journals=$(ls -1 "$JOURNAL_DIR"/journal.[0-9]* 2>/dev/null | sort -t. -k2 -n | head -n -2)
        if [ -n "$old_journals" ]; then
            echo "$old_journals" | while read -r f; do
                rm -f "$f"
                echo "Removed old journal: $f"
            done
        fi

        # Also clean up old checkpoint files (keep 2 most recent)
        old_checkpoints=$(ls -1 "$JOURNAL_DIR"/*.ckp.* 2>/dev/null | sort -t. -k2 -n | head -n -2)
        if [ -n "$old_checkpoints" ]; then
            echo "$old_checkpoints" | while read -r f; do
                rm -f "$f"
                echo "Removed old checkpoint: $f"
            done
        fi
    fi
else
    echo "WARNING: Checkpoint failed — skipping journal cleanup"
fi

# --- Log Rotation ---
# P4LOG is a single file that grows forever. Truncate if over 100MB.
if [ -f "$P4LOG" ]; then
    log_size=$(stat -c%s "$P4LOG" 2>/dev/null || echo 0)
    if [ "$log_size" -gt 104857600 ]; then
        echo "Rotating log file ($((log_size / 1048576))MB)..."
        cp "$P4LOG" "${P4LOG}.prev"
        truncate -s 0 "$P4LOG"
        echo "Log rotated. Previous log saved as ${P4LOG}.prev"
    fi
fi

echo "Perforce maintenance complete."
