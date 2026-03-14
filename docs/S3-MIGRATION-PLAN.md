# S3-Backed Perforce Depot Storage (Railway Bucket)

## Overview

Perforce depot archives are stored in a Railway Bucket (S3-compatible) to avoid Railway's 500GB volume limit. Migration happens automatically on container boot via `s3-migrate.sh`.

## How It Works

On every boot (`init.sh` and `restore.sh`), the `s3-migrate.sh` script:

1. **Exits early** if `S3_*` env vars are not set (backwards compatible)
2. **Detects local depots** without an S3 Address and migrates their files via `aws s3 sync`
3. **Updates the depot Address** to point to S3
4. **Runs `p4 verify`** to confirm file integrity
5. **Removes local files** to reclaim disk space
6. **Refreshes credentials** on depots already using S3 (handles key rotation)

Changelist numbers, history, and depot names are fully preserved — only the storage backend changes.

## Setup

### 1. Create a Railway Bucket

In Railway Dashboard, create a Bucket for the Helix Core service.

### 2. Map Environment Variables

In Railway Dashboard → Service → Variables, map the bucket credentials:

```
S3_ENDPOINT=${{bucket.ENDPOINT}}
S3_BUCKET=${{bucket.BUCKET}}
S3_ACCESS_KEY_ID=${{bucket.ACCESS_KEY_ID}}
S3_SECRET_ACCESS_KEY=${{bucket.SECRET_ACCESS_KEY}}
S3_REGION=${{bucket.REGION}}
```

### 3. Deploy

Deploy the updated Docker image. On first boot with S3 configured, existing local depots will be automatically migrated.

## Architecture

```
┌─────────────────────────────────────┐
│ Railway Container                    │
│ ┌─────────────────────────────────┐ │
│ │ /p4/root       - metadata       │ │
│ │ /p4/checkpoints - journals      │ │
│ │ depots → S3 backend             │ │
│ └──────────────┬──────────────────┘ │
└────────────────│────────────────────┘
                 │ S3 API
                 ▼
   ┌─────────────────────────────┐
   │     Railway Bucket          │
   │  All versioned files        │
   │  Unlimited storage          │
   └─────────────────────────────┘
```

**What stays on the Railway volume:**
- `/p4/root` — server metadata, db.* files, license
- `/p4/checkpoints` — journals and checkpoints

**What moves to S3:**
- `/p4/depots/*` — all versioned file archives

## Perforce S3 Address Format

```
s3,url:{endpoint},bucket:{bucket},accessKey:{key},secretKey:{secret}
```

## Requirements

- **Perforce 2024.1+** for S3 support on non-archive depot types
- **awscli** installed in the Docker image (added to Dockerfile)

## Credential Rotation

When Railway rotates bucket credentials, update the `S3_*` env vars and redeploy. The `s3-migrate.sh` script refreshes the Address field on every boot for all S3-backed depots.

## Verification

```bash
# Build and test locally
./build.sh snowfall/helix-p4d:test
docker run --rm snowfall/helix-p4d:test bash -c "which aws && cat /usr/local/bin/s3-migrate.sh"

# Inside a running container
p4 depot -o <depot-name> | grep Address
p4 verify //<depot-name>/...
```

## Rollback

To revert a depot to local storage:
1. `aws s3 sync s3://{bucket}/{name}/ /p4/depots/{name}/` — download files back
2. `p4 depot -o {name}` → remove the Address line → `p4 depot -i` — reset to local
3. Remove `S3_*` env vars to prevent re-migration
