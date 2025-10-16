#!/bin/bash

# Enable error handling and debugging
set -e
set -x

echo "Starting setup.sh script..."

if [ ! -d "$P4ROOT/etc" ]; then
    echo >&2 "First time installation, copying configuration from /etc/perforce to $P4ROOT/etc and relinking"
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

# Start server with initial IPv4 configuration
echo "Starting Perforce server..."
if ! p4dctl start -t p4d "$NAME"; then
    echo "ERROR: Failed to start Perforce server"
    # Try to get more information about the failure
    p4dctl status -t p4d "$NAME"
    exit 1
fi
echo "Server started successfully"

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
