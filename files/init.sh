#!/bin/bash

# Enable error handling (but not debug mode to avoid stderr noise)
set -e

echo "Perforce Server starting..."
echo "Environment variables:"
echo "P4HOME=$P4HOME"
echo "P4ROOT=$P4ROOT"
echo "P4DEPOTS=$P4DEPOTS"
echo "P4CKP=$P4CKP"
echo "P4PORT=$P4PORT"
echo "P4USER=$P4USER"
echo "NAME=$NAME"

# Setup directories with proper permissions
mkdir -p "$P4ROOT"
mkdir -p "$P4DEPOTS"
mkdir -p "$P4CKP"
mkdir -p "$P4ROOT/logs"

echo "127.0.0.1 p4-snowfall.railway.internal" >> /etc/hosts

# Restore checkpoint if symlink latest exists
if [ -L "$P4CKP/latest" ]; then
    echo "Restoring checkpoint..."
	/usr/local/bin/restore.sh
	rm "$P4CKP/latest"
else
	echo "Create empty or start existing server..."
	/usr/local/bin/setup.sh
fi

# Check if server is accessible
echo "Checking if Perforce server is running..."

# Check server using the configured P4PORT (with protocol prefix)
if P4PORT="$P4PORT" p4 info -s 2> /dev/null; then
    echo "Perforce Server [RUNNING] on $P4PORT"
else
    echo "ERROR: Perforce server is not responding"
    
    # Show P4 server logs immediately
    echo "=== P4 Server Logs ==="
    if [ -f "$P4ROOT/logs/log" ]; then
        echo "Full P4 server log:"
        cat "$P4ROOT/logs/log"
    else
        echo "No P4 log file found at $P4ROOT/logs/log"
    fi
    
    exit 1
fi

# Now that server is running, login
echo "Logging in to Perforce server..."
p4 login <<EOF
$P4PASSWD
EOF

# Update typemap
echo "Updating typemap..."
p4 typemap -i < /usr/local/bin/p4-typemap.txt

echo "Perforce server initialization completed successfully!"
