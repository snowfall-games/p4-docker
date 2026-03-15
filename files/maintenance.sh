#!/bin/bash

# Perforce Maintenance Script
# Runs on every boot: rotates journals via checkpoint and cleans up old logs.
# Called from init.sh after server is running and authenticated.

echo "Perforce maintenance starting..."

# --- Journal Rotation via Checkpoint ---
# A checkpoint snapshots the full database state. Once created, all prior
# journals (incremental transaction logs) are no longer needed for recovery.
# Without this, journals grow indefinitely.

# Resolve the actual journal directory from Perforce's journalPrefix config.
# journalPrefix is often a relative path (e.g. ../journals/snowfall-perforce) resolved from P4ROOT.
P4ROOT_ACTUAL=$(p4 info | grep "^Server root:" | sed 's/^Server root:[[:space:]]*//')
JOURNAL_PREFIX_RAW=$(p4 configure show journalPrefix 2>/dev/null | grep "^journalPrefix=" | sed 's/^journalPrefix=//' | sed 's/ .*//')

if [ -n "$JOURNAL_PREFIX_RAW" ]; then
    JOURNAL_DIR=$(cd "$P4ROOT_ACTUAL" && cd "$(dirname "$JOURNAL_PREFIX_RAW")" 2>/dev/null && pwd)
    JOURNAL_BASE=$(basename "$JOURNAL_PREFIX_RAW")
else
    JOURNAL_DIR=$(dirname "$P4JOURNAL")
    JOURNAL_BASE="journal"
fi
echo "Journal directory: $JOURNAL_DIR (prefix: ${JOURNAL_BASE:-journal})"

echo "Creating checkpoint (this may take a moment)..."
if p4 admin checkpoint 2>&1; then
    echo "Checkpoint created successfully."

    # After checkpoint, p4d rotates the journal (journal -> prefix.jnl.N).
    # Remove old rotated journals to reclaim disk. Keep the most recent only.
    if [ -d "$JOURNAL_DIR" ]; then
        old_journals=$(ls -1 "$JOURNAL_DIR"/*.jnl.* 2>/dev/null | sort -t. -k3 -n | head -n -1)
        if [ -n "$old_journals" ]; then
            echo "$old_journals" | while read -r f; do
                size=$(du -sh "$f" 2>/dev/null | cut -f1)
                rm -f "$f"
                echo "Removed old journal: $f ($size)"
            done
        fi

        # Also clean up old checkpoint files (keep most recent only)
        old_checkpoints=$(ls -1 "$JOURNAL_DIR"/*.ckp.* 2>/dev/null | grep -v '\.md5$' | sort -t. -k3 -n | head -n -1)
        if [ -n "$old_checkpoints" ]; then
            echo "$old_checkpoints" | while read -r f; do
                rm -f "$f" "${f}.md5"
                echo "Removed old checkpoint: $f"
            done
        fi
    fi
else
    echo "WARNING: Checkpoint failed — skipping journal cleanup"
fi

# --- Log Cleanup ---
# P4LOG can grow very large. Truncate if over 100MB (no backup — not worth the disk).
if [ -f "$P4LOG" ]; then
    log_size=$(stat -c%s "$P4LOG" 2>/dev/null || echo 0)
    if [ "$log_size" -gt 104857600 ]; then
        echo "Truncating log file ($((log_size / 1048576))MB)..."
        truncate -s 0 "$P4LOG"
        echo "Log truncated."
    fi
fi
# Remove any old .prev log files from prior rotations
rm -f "${P4LOG}.prev" 2>/dev/null

echo "Perforce maintenance complete."
