# Tech Design: S3-Backed Perforce Depot Migration on Railway

## Problem Statement

Railway has a 500GB volume limit with no option to expand. Perforce Helix Core's versioned file archives (currently 200-500GB) need to migrate to unlimited S3 storage.

## Chosen Approach: New S3 Depot + Full Migration

Create a new depot backed by Cloudflare R2, migrate all files, update client mappings, then remove the old depot. This provides the cleanest architecture with all files in S3.

---

## Current p4-docker Directory Structure

```
/p4
├── root/          # P4ROOT - metadata, db.* files, license
│   ├── etc/       # Server configuration
│   └── logs/      # Server logs
├── depots/        # P4DEPOTS - versioned file archives (THIS IS WHAT GROWS)
└── checkpoints/   # P4CKP - journals and checkpoints
```

**Environment Variables:**
- `P4HOME=/p4`
- `P4ROOT=/p4/root`
- `P4DEPOTS=/p4/depots`
- `P4CKP=/p4/checkpoints`
- `P4NAME=snowfall-main`

---

## Critical Requirements

### Perforce Version
**Must be 2024.1 or later** for S3 support on non-archive depot types.

Current Dockerfile already uses `ubuntu:noble` (24.04) and installs `p4-server` package. Verify version after deployment.

### Downtime Estimate
For 200-500GB of data:
- **Migration time:** 2-6 hours (depends on file count, not just size)
- **Client reconfiguration:** Variable (depends on team size)

---

## Architecture

```
BEFORE:
┌─────────────────────────────────────┐
│ Railway Container                    │
│ ┌─────────────────────────────────┐ │
│ │ /p4/root      - metadata (small)│ │
│ │ /p4/depots    - files (LARGE)   │ │
│ │ /p4/checkpoints - journals      │ │
│ │ Total: 200-500GB on volume      │ │
│ └─────────────────────────────────┘ │
└─────────────────────────────────────┘

AFTER:
┌─────────────────────────────────────┐
│ Railway Container                    │
│ ┌─────────────────────────────────┐ │
│ │ /p4/root      - metadata (small)│ │
│ │ /p4/checkpoints - journals      │ │
│ │ depot-s3 → S3 backend           │ │
│ └──────────────┬──────────────────┘ │
└────────────────│────────────────────┘
                 │ S3 API
                 ▼
   ┌─────────────────────────────┐
   │     Cloudflare R2           │
   │  All versioned files        │
   │  Unlimited storage          │
   └─────────────────────────────┘
```

---

## Implementation Plan

### Phase 1: Prerequisites (Before Migration Day)

#### 1.1 Verify Dockerfile (p4-docker)

**File:** `p4-docker/Dockerfile`

The p4-docker Dockerfile already uses `ubuntu:noble` and installs `p4-server`.

**Verify the installed version supports S3:**
```bash
# After deploying, run inside the container:
p4 -V
# Must show 2024.1 or later for S3 support on non-archive depots
```

**Note:** The Dockerfile uses deprecated `apt-key add`. Consider updating to modern GPG handling (optional):
```dockerfile
# Modern GPG key handling (optional improvement):
RUN wget -qO - https://package.perforce.com/perforce.pubkey | gpg --dearmor > /usr/share/keyrings/perforce-archive-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/perforce-archive-keyring.gpg] http://package.perforce.com/apt/ubuntu noble release" > /etc/apt/sources.list.d/perforce.list
```

#### 1.2 Create Cloudflare R2 Bucket

1. Log into Cloudflare Dashboard → R2
2. Create bucket: `snowfall-helix-depot`
3. Create API token with permissions:
   - `s3:GetObject`
   - `s3:PutObject`
   - `s3:DeleteObject`
   - `s3:ListBucket`
4. Save credentials:
   - Account ID: `<your-account-id>`
   - Access Key ID: `<generated>`
   - Secret Access Key: `<generated>`

#### 1.3 Add Railway Environment Variables

In Railway Dashboard → Service → Variables:

```
R2_ACCOUNT_ID=<cloudflare-account-id>
R2_ACCESS_KEY_ID=<r2-access-key>
R2_SECRET_ACCESS_KEY=<r2-secret-key>
R2_BUCKET_NAME=snowfall-helix-depot
```

#### 1.4 Deploy Updated Dockerfile

Deploy the Perforce 2024.1+ update **before** migration day. Verify the version:

```bash
p4 -V
# Should show: Rev. P4/LINUX.../2024.1/...
```

---

### Phase 2: Pre-Migration (Migration Day - Hour 0)

#### 2.1 Notify Users

Send notice that Perforce will be unavailable and clients will need reconfiguration.

#### 2.2 Create Backup

```bash
# Connect to Railway container
railway shell

# Create checkpoint (p4-docker has a helper script)
p4 admin checkpoint
# Or use: /usr/local/bin/latest_checkpoint.sh

# Record current state
p4 depots > /tmp/depots-before.txt
p4 files //depot/... > /tmp/files-before.txt
p4 changes -m 100 //depot/... > /tmp/changes-before.txt

# Note the file count and size
p4 sizes -s //depot/...
du -sh $P4DEPOTS    # /p4/depots
du -sh $P4ROOT      # /p4/root (metadata)
du -sh $P4CKP       # /p4/checkpoints
```

#### 2.3 Lock Server

```bash
# Prevent new submits during migration
p4 configure set server.locks.dir=/data/locks
mkdir -p /data/locks

# Verify lock is active
p4 lockstat
```

---

### Phase 3: Create New S3-Backed Depot

#### 3.1 Create Parallel Depot with Different Name

```bash
# Create new S3-backed depot with temporary name
cat <<EOF | p4 depot -i
Depot: depot-s3
Type: local
Address: s3,url:https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com,bucket:${R2_BUCKET_NAME},accessKey:${R2_ACCESS_KEY_ID},secretKey:${R2_SECRET_ACCESS_KEY}
Description:
    S3-backed depot (migrated from local depot)
Map: depot-s3/...
EOF

# Verify depot was created
p4 depot -o depot-s3
```

---

### Phase 4: Migrate Files

#### 4.1 Use p4 duplicate to Copy Files

The `p4 duplicate` command copies files between depots while preserving history:

```bash
# Duplicate all files from old depot to new S3 depot
# This copies metadata AND versioned files
p4 duplicate //depot/... //depot-s3/...
```

**Note:** For 200-500GB, this will take several hours. The files are transferred through the server to S3.

#### 4.2 Monitor Progress

```bash
# In another terminal, monitor the progress
watch -n 60 'p4 files //depot-s3/... | wc -l'

# Or check R2 bucket size in Cloudflare dashboard
```

#### 4.3 Verify Migration

```bash
# Compare file counts
OLD_COUNT=$(p4 files //depot/... | wc -l)
NEW_COUNT=$(p4 files //depot-s3/... | wc -l)
echo "Old: $OLD_COUNT, New: $NEW_COUNT"

# Verify with p4 verify
p4 verify //depot-s3/...

# Spot check some files
p4 print //depot-s3/path/to/important/file.txt | head
```

---

### Phase 5: Update Client Mappings

#### 5.1 Notify Users to Update Workspaces

All users need to update their client workspace mappings from `//depot/...` to `//depot-s3/...`

**Option A: Users update manually**
```bash
# User runs:
p4 client

# Change:
#   //depot/... //clientname/...
# To:
#   //depot-s3/... //clientname/...
```

**Option B: Admin bulk update (if using client templates)**
```bash
# List all clients
p4 clients

# For each client, update the mapping
for client in $(p4 clients -e '*' | awk '{print $2}'); do
    p4 client -o $client | sed 's|//depot/|//depot-s3/|g' | p4 client -i
done
```

#### 5.2 Update CI/CD and Automation

Update any automation, CI/CD pipelines, or scripts that reference `//depot/...`

---

### Phase 6: Cleanup

#### 6.1 Verify Everything Works

```bash
# Test a sync from new depot
p4 sync //depot-s3/...

# Test a submit to new depot
echo "test" > /tmp/test.txt
p4 -c testclient add /tmp/test.txt
p4 -c testclient submit -d "Test S3 storage"
```

#### 6.2 Obliterate Old Depot (After Verification Period)

**IMPORTANT:** Wait at least 1-2 weeks before obliterating to ensure no issues.

```bash
# When ready to reclaim space:
p4 obliterate -y //depot/...

# Delete the old depot
p4 depot -d depot

# Verify local storage freed
df -h /p4
du -sh $P4DEPOTS    # /p4/depots - should be mostly empty now
du -sh $P4ROOT      # /p4/root - metadata stays
```

#### 6.3 (Optional) Rename New Depot Back

If you want to use the original `depot` name:

```bash
# This requires recreating the depot with a different name
# Perforce doesn't support renaming depots directly

# Alternative: Keep depot-s3 name and update documentation
```

---

### Phase 7: Unlock Server

```bash
# Remove lock
p4 configure unset server.locks.dir

# Create post-migration checkpoint
p4 admin checkpoint

# Announce migration complete
```

---

## Migration Script

A helper script is available at `files/migrate-to-s3-depot.sh` that automates the migration steps.

---

## Verification Steps

1. **Perforce version check**
   ```bash
   p4 -V
   # Must show 2024.1 or later
   ```

2. **New depot exists with S3 address**
   ```bash
   p4 depot -o depot-s3 | grep Address
   # Should show: Address: s3,url:https://...
   ```

3. **Files accessible from S3**
   ```bash
   p4 print //depot-s3/path/to/file.txt
   ```

4. **Submit works**
   ```bash
   # In a workspace mapped to depot-s3
   p4 add newfile.txt
   p4 submit -d "Test S3 storage"
   ```

5. **R2 bucket shows objects**
   - Check Cloudflare Dashboard → R2 → snowfall-helix-depot

---

## Client Migration Guide (For Users)

### Update Your Workspace

1. Open P4V or run `p4 client`
2. Find the "View" mapping section
3. Change all references from `//depot/...` to `//depot-s3/...`
4. Save and sync

**Before:**
```
//depot/... //myworkspace/...
```

**After:**
```
//depot-s3/... //myworkspace/...
```

---

## Rollback Plan

### If migration fails before obliterate:
- Old depot is still intact
- Revert client mappings
- Delete the depot-s3 depot: `p4 depot -d -f depot-s3`

### If issues found after obliterate:
- Restore from checkpoint
- Restore versioned files from backup
- This is why we wait 1-2 weeks before obliterate

---

## Timeline Summary

| Phase | Duration | Description |
|-------|----------|-------------|
| Prerequisites | 1-2 days | Update Dockerfile, create R2 bucket, deploy |
| Pre-migration | 30 min | Checkpoint, lock server |
| Migration | 2-6 hours | Create depot, duplicate files |
| Client updates | Variable | Users update workspace mappings |
| Verification | 1-2 weeks | Monitor, test, verify |
| Cleanup | 1 hour | Obliterate old depot |

---

## Cost Estimate

| Item | Cost |
|------|------|
| R2 Storage (500GB) | ~$7.50/month |
| Class A ops | ~$2-5/month |
| Egress | **Free** |
| **Total** | **~$10-15/month** |

---

## Risk Assessment

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Client disruption | High | Clear communication, documentation |
| Duplicate fails mid-way | Low | Checkpoint before, can restart |
| S3 latency impacts users | Medium | Monitor, consider proxy |
| Data loss | Very Low | Checkpoint + don't obliterate immediately |

---

## Summary

This migration plan for **p4-docker**:
1. **Verifies Perforce 2024.1+** (p4-docker already uses ubuntu:noble)
2. **Creates a new S3-backed depot** (depot-s3) pointing to Cloudflare R2
3. **Duplicates all files** from /p4/depots to R2, preserving history
4. **Requires client remapping** from //depot/... to //depot-s3/...
5. **Enables obliteration** of old depot after verification period
6. **Frees /p4/depots** storage on Railway volume

**Key paths in p4-docker:**
- Metadata: `/p4/root` (stays on Railway volume)
- Depot files: `/p4/depots` → moves to R2
- Checkpoints: `/p4/checkpoints` (stays on Railway volume)

**Trade-off:** Client disruption in exchange for clean, unlimited S3 storage.
