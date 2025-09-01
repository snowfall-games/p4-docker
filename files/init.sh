#!/bin/bash

# Enable IPv6 at runtime
echo 0 > /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null || true
echo 0 > /proc/sys/net/ipv6/conf/default/disable_ipv6 2>/dev/null || true
echo 0 > /proc/sys/net/ipv6/conf/lo/disable_ipv6 2>/dev/null || true

# Verify IPv6 is available
echo "Checking IPv6 availability..."
if [ -f /proc/net/if_inet6 ]; then
    echo "IPv6 is available"
    cat /proc/net/if_inet6
else
    echo "IPv6 is NOT available - this may cause connection issues"
fi

# Setup directories
mkdir -p "$P4ROOT"
mkdir -p "$P4DEPOTS"
mkdir -p "$P4CKP"

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
until p4 info -s 2> /dev/null; do sleep 1; done
echo "Perforce Server [RUNNING]"

## Remove all triggers
echo "Triggers:" | p4 triggers -i
