#!/bin/bash

# Enable error handling (but not debug mode to avoid stderr noise)
set -e

echo "Starting setup.sh script..."

if [ ! -d "$P4ROOT/etc" ]; then
    echo "First time installation, copying configuration from /etc/perforce to $P4ROOT/etc and relinking"
    mkdir -p "$P4ROOT/etc"
    cp -r /etc/perforce/* "$P4ROOT/etc/"
fi

mv /etc/perforce /etc/perforce.orig
ln -s "$P4ROOT/etc" /etc/perforce

if ! p4dctl list 2>/dev/null | grep -q "$NAME"; then
    echo "Configuring new Perforce server: $NAME"
    # Use just the port number for initial configuration
    if ! /opt/perforce/sbin/configure-helix-p4d.sh "$NAME" -n -p "$P4PORT" -r "$P4ROOT" -u "$P4USER" -P "${P4PASSWD}" --case "$P4CASE" --unicode; then
        echo "ERROR: Failed to configure Perforce server"
        exit 1
    fi
    echo "Server configuration completed successfully"
else
    echo "Server $NAME already configured"
fi

# Install the Perforce license
echo "Installing Perforce license..."

echo "Source license file at /usr/local/bin/license:"
if [ -f "/usr/local/bin/license" ]; then
    cp "/usr/local/bin/license" "$P4ROOT/root/license"
    echo "License file installed at $P4ROOT/root/license"
else
    echo "WARNING: License file not found at /usr/local/bin/license"
fi

echo "Showing license information..."
p4d -V -r $P4ROOT

# Start server with initial IPv4 configuration
echo "Starting Perforce server..."

# Try to start the server
if ! p4dctl start -t p4d "$NAME"; then
    echo "ERROR: Failed to start Perforce server"
    
    # Show P4 logs if they exist
    echo "=== P4 Server Logs ==="
    if [ -f "$P4ROOT/logs/log" ]; then
        echo "Last 20 lines of $P4ROOT/logs/log:"
        tail -20 "$P4ROOT/logs/log"
    else
        echo "No log file found at $P4ROOT/logs/log"
    fi

    exit 1
else
    echo "Server started successfully"
fi

# Wait for server to be ready
sleep 5

# Login to configure server settings
echo "Logging in and configuring server settings..."
P4PORT="$P4PORT" P4USER="$P4USER" p4 login <<EOF
$P4PASSWD
EOF

# Configure server settings
p4 configure set $P4NAME#server.depot.root=$P4DEPOTS
p4 configure set $P4NAME#journalPrefix=$P4CKP/$JNL_PREFIX
