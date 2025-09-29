#!/bin/bash

if [ ! -d "$P4ROOT/etc" ]; then
    echo >&2 "First time installation, copying configuration from /etc/perforce to $P4ROOT/etc and relinking"
    mkdir -p "$P4ROOT/etc"
    cp -r /etc/perforce/* "$P4ROOT/etc/"
fi

mv /etc/perforce /etc/perforce.orig
ln -s "$P4ROOT/etc" /etc/perforce

if ! p4dctl list 2>/dev/null | grep -q "$NAME"; then
    # Use just the port number for initial configuration
    /opt/perforce/sbin/configure-helix-p4d.sh "$NAME" -n -p "$P4TCP" -r "$P4ROOT" -u "$P4USER" -P "${P4PASSWD}" --case "$P4CASE" --unicode
fi

# Start server with initial IPv4 configuration
p4dctl start -t p4d "$NAME"

# Wait for server to be ready, then reconfigure for IPv6
sleep 3
echo "Reconfiguring server for IPv6 binding..."

# Login first, then configure
P4PORT="$P4TCP" P4USER="$P4USER" p4 login <<EOF
$P4PASSWD
EOF

# Now set the IPv6 configuration
P4PORT="$P4TCP" P4USER="$P4USER" p4 configure set $NAME#P4PORT="$P4PORT"

# Restart server with new IPv6 configuration
p4dctl restart -t p4d "$NAME"
sleep 3

p4 configure set $P4NAME#server.depot.root=$P4DEPOTS
p4 configure set $P4NAME#journalPrefix=$P4CKP/$JNL_PREFIX

# Configure Unreal Engine file types per Epic Games documentation
p4 typemap -i < /usr/local/bin/p4-typemap.txt
