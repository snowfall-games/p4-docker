#!/bin/bash

if [ ! -d "$P4ROOT/etc" ]; then
    echo >&2 "First time installation, copying configuration from /etc/perforce to $P4ROOT/etc and relinking"
    mkdir -p "$P4ROOT/etc"
    cp -r /etc/perforce/* "$P4ROOT/etc/"
fi

mv /etc/perforce /etc/perforce.orig
ln -s "$P4ROOT/etc" /etc/perforce

if ! p4dctl list 2>/dev/null | grep -q "$NAME"; then
    /opt/perforce/sbin/configure-helix-p4d.sh "$NAME" -n -p "$P4PORT" -r "$P4ROOT" -u "$P4USER" -P "${P4PASSWD}" --case "$P4CASE" --unicode
fi

p4 configure set $P4NAME#server.depot.root=$P4DEPOTS
p4 configure set $P4NAME#journalPrefix=$P4CKP/$JNL_PREFIX
p4 configure set net.rfc3484=1

# Verify P4PORT before starting
echo "Configuring server with P4PORT: $P4PORT"
p4dctl start -t p4d "$NAME"

# Give the server time to bind to IPv6
sleep 5

# Check what the server is actually listening on
echo "Checking server binding..."
netstat -tlnp 2>/dev/null | grep 1666 || echo "No binding found on port 1666"

# Configure Unreal Engine file types per Epic Games documentation
p4 typemap -i < /usr/local/bin/unreal-typemap.txt
