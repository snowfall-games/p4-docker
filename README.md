# p4-docker

Docker image for Snowfall's Perforce Helix Core server, deployed on Railway.

## Build

```bash
./build.sh <tag>
# e.g. ./build.sh snowfall/helix-p4d:latest
```

## Usage

```sh
docker run --rm \
    --publish 1666:1666 \
    snowfall/helix-p4d:latest
```

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `NAME` | `snowfall-perforce` | Server instance name |
| `P4NAME` | `snowfall-main` | Server ID |
| `P4PORT` | `tcp6:1666` | Server listen address |
| `PORT` | `1666` | Exposed port |
| `P4USER` | `admin` | Super user |
| `P4PASSWD` | `SnowfallGames!` | Super user password |
| `P4CASE` | `-C0` | Case sensitivity (`-C0` = case-insensitive) |
| `P4CHARSET` | `utf8` | Server charset |

Override with `--env`:

```sh
docker run --rm \
    --publish 1666:1666 \
    --env P4PASSWD=securepassword \
    snowfall/helix-p4d:latest
```

For persistent data, volume mount `/p4`:

```sh
docker run -d \
    --publish 1666:1666 \
    --volume ~/.helix-p4d-home:/p4 \
    snowfall/helix-p4d:latest
```

### Directory Structure

```
/p4
├── root/          # P4ROOT - metadata, db.* files, license
│   ├── etc/       # Server configuration
│   └── logs/      # Server logs
├── depots/        # P4DEPOTS - versioned file archives
└── checkpoints/   # P4CKP - journals and checkpoints
```

## S3 Storage (Railway Bucket)

Depot archives can be stored in a Railway Bucket (S3-compatible) instead of local disk. This removes the 500GB Railway volume limit.

### Setup

Map Railway Bucket credentials to the service's environment variables:

```
S3_ENDPOINT=${{bucket.ENDPOINT}}
S3_BUCKET=${{bucket.BUCKET}}
S3_ACCESS_KEY_ID=${{bucket.ACCESS_KEY_ID}}
S3_SECRET_ACCESS_KEY=${{bucket.SECRET_ACCESS_KEY}}
S3_REGION=${{bucket.REGION}}
```

### How It Works

On every boot, `s3-migrate.sh` runs after the server starts:

1. Detects local depots and uploads their archives to S3 via `aws s3 sync`
2. Updates each depot's `Address` field to the S3 backend
3. Verifies file integrity with `p4 verify`
4. Removes local files to reclaim disk
5. Refreshes S3 credentials on depots already using S3

Changelist numbers, history, and depot names are preserved. If S3 env vars are not set, the script exits silently (backwards compatible).

### Credential Rotation

When credentials change, update the `S3_*` env vars and redeploy. The script refreshes the Address field on every boot.

### Rollback

To revert a depot to local storage:

```bash
aws s3 sync "s3://${S3_BUCKET}/${depot_name}/" "/p4/depots/${depot_name}/"
p4 depot -o ${depot_name} | sed '/^Address:/d' | p4 depot -i
```

Then remove the `S3_*` env vars to prevent re-migration.

## Checkpoint Restore

Place a checkpoint file in `/p4/checkpoints/` and create a symlink `latest` pointing to it. On boot, the server will restore from the checkpoint automatically.

## Credits

Originally based on https://github.com/p4paul/helix-docker and https://github.com/ambakshi/docker-perforce.
