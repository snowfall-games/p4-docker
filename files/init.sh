#!/bin/bash

# Setup directories with proper permissions
mkdir -p "$P4ROOT"
mkdir -p "$P4DEPOTS"
mkdir -p "$P4CKP"
mkdir -p "$P4ROOT/logs"

# Ensure perforce user owns the directories
chown -R perforce:perforce "$P4HOME"
chmod -R 755 "$P4HOME"

# Restore checkpoint if symlink latest exists
if [ -L "$P4CKP/latest" ]; then
    echo "Restoring checkpoint..."
	restore.sh
	rm "$P4CKP/latest"
else
	echo "Create empty or start existing server..."
	setup.sh
fi

p4 login <<EOF
$P4PASSWD
EOF

echo "Perforce Server starting..."

# Wait for server to be accessible - try both IPv4 and IPv6
echo "Waiting for server to start..."
MAX_ATTEMPTS=30
ATTEMPT=0

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    # Try IPv6 first
    if P4PORT="tcp6:[::]:$P4TCP" p4 info -s 2> /dev/null; then
        echo "Perforce Server [RUNNING] on IPv6"
        export P4PORT="tcp6:[::]:$P4TCP"
        break
    # Fallback to IPv4
    elif P4PORT="$P4TCP" p4 info -s 2> /dev/null; then
        echo "Perforce Server [RUNNING] on IPv4"
        export P4PORT="$P4TCP"
        break
    fi
    
    ATTEMPT=$((ATTEMPT + 1))
    echo "Waiting for server... (attempt $ATTEMPT/$MAX_ATTEMPTS)"
    sleep 2
done

if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
    echo "ERROR: Server failed to start after $MAX_ATTEMPTS attempts"
    exit 1
fi

# Update typemap
echo "Updating typemap..."
p4 typemap -i < /usr/local/bin/p4-typemap.txt
