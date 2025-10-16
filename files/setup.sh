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
    if ! /opt/perforce/sbin/configure-helix-p4d.sh "$NAME" -n -p "$P4TCP" -r "$P4ROOT" -u "$P4USER" -P "${P4PASSWD}" --case "$P4CASE" --unicode; then
        echo "ERROR: Failed to configure Perforce server"
        exit 1
    fi
    echo "Server configuration completed successfully"
else
    echo "Server $NAME already configured"
fi

# Install the Perforce license
echo "Installing Perforce license..."

# Debug: Check what license files exist before installation
echo "=== LICENSE DEBUG: Before installation ==="
echo "Checking for existing license files..."
if [ -f "$P4ROOT/license" ]; then
    echo "Found existing license at $P4ROOT/license:"
    cat "$P4ROOT/license"
else
    echo "No existing license file at $P4ROOT/license"
fi

echo "Source license file at /usr/local/bin/license:"
if [ -f "/usr/local/bin/license" ]; then
    cat "/usr/local/bin/license"
    echo "Installing license file..."
    cp "/usr/local/bin/license" "$P4ROOT/license"
    echo "License file installed at $P4ROOT/license"
else
    echo "WARNING: License file not found at /usr/local/bin/license"
fi

echo "=== LICENSE DEBUG: After installation ==="
echo "Final license file content:"
if [ -f "$P4ROOT/license" ]; then
    cat "$P4ROOT/license"
else
    echo "ERROR: No license file found after installation!"
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
    
    # Debug: Check what addresses Perforce detects
    echo "=== P4 LICENSE DEBUG: Server addresses ==="
    echo "Checking what IP and MAC addresses P4 detects..."
    if P4PORT="$P4TCP" P4USER="$P4USER" timeout 10 p4 license -L 2>/dev/null; then
        echo "Successfully got license address information"
    else
        echo "Could not get license address information (server may not be fully ready)"
    fi
    
    # Debug: Check current P4 configuration
    echo "=== P4 CONFIG DEBUG ==="
    echo "Current P4 configuration:"
    if P4PORT="$P4TCP" P4USER="$P4USER" timeout 10 p4 configure show 2>/dev/null; then
        echo "Successfully got P4 configuration"
    else
        echo "Could not get P4 configuration (server may not be fully ready)"
    fi
fi

# Wait for server to be ready, then reconfigure for IPv6
sleep 5
echo "Reconfiguring server for IPv6 binding..."

# Login first with IPv4 port
P4PORT="$P4TCP" P4USER="$P4USER" p4 login <<EOF
$P4PASSWD
EOF

# Now set the IPv6 configuration - use the actual IPv6 address format
P4PORT="$P4TCP" P4USER="$P4USER" p4 configure set $NAME#P4PORT="tcp6:[::]:$P4TCP"

# Stop the server cleanly before restart
p4dctl stop -t p4d "$NAME"
sleep 2

# Restart server with new IPv6 configuration
p4dctl start -t p4d "$NAME"
sleep 5

p4 configure set $P4NAME#server.depot.root=$P4DEPOTS
p4 configure set $P4NAME#journalPrefix=$P4CKP/$JNL_PREFIX
