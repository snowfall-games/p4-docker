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
    # Extract port number from P4PORT (e.g., "1666" from "tcp6:[::]:1666")
    PORT_NUM=$(echo "$P4PORT" | grep -oE '[0-9]+$')
    echo "Configuring server to listen on port: $PORT_NUM"
    if ! /opt/perforce/sbin/configure-helix-p4d.sh "$NAME" -n -p "$PORT_NUM" -r "$P4ROOT" -u "$P4USER" -P "${P4PASSWD}" --case "$P4CASE" --utf8; then
        echo "ERROR: Failed to configure Perforce server"
        exit 1
    fi
    echo "Server configuration completed successfully"
else
    echo "Server $NAME already configured"

    echo "Setting P4PORT to $P4PORT"
    p4d -r "$P4ROOT/root" "-cset $NAME#P4PORT=$P4PORT"

    echo "=== P4 Server Configuration ==="
    if [ -f "$P4ROOT/etc/p4dctl.conf.d/$NAME.conf" ]; then
        echo "Perforce server config file ($P4ROOT/etc/p4dctl.conf.d/$NAME.conf):"
        cat "$P4ROOT/etc/p4dctl.conf.d/$NAME.conf"
    else
        echo "No Perforce server config file found at $P4ROOT/etc/p4dctl.conf.d/$NAME.conf"
    fi
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
p4d -V -r $P4ROOT/root

# Upgrade database schema if needed (required when restoring from older backups)
echo "Upgrading database schema if needed..."
p4d -r "$P4ROOT/root" -xu

# Start server with initial IPv4 configuration
echo "Starting $NAME Perforce server on P4PORT: $P4PORT..."

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
