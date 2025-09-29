#!/bin/bash

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
# Try IPv6 first, then fallback to IPv4 if needed
if P4PORT="tcp6:[::]:$P4TCP" p4 info -s 2> /dev/null; then
    echo "Perforce Server [RUNNING] on IPv6"
elif P4PORT="$P4TCP" p4 info -s 2> /dev/null; then
    echo "Perforce Server [RUNNING] on IPv4"
    # Wait a bit longer and try IPv6 again in case server is still restarting
    sleep 5
    until P4PORT="tcp6:[::]:$P4TCP" p4 info -s 2> /dev/null || P4PORT="$P4TCP" p4 info -s 2> /dev/null; do 
        echo "Waiting for server..."
        sleep 2
    done
    echo "Perforce Server [RUNNING]"
else
    echo "Waiting for server to start..."
    until p4 info -s 2> /dev/null; do sleep 1; done
    echo "Perforce Server [RUNNING]"
fi

# Update typemap
echo "Updating typemap..."
p4 typemap -i < /usr/local/bin/p4-typemap.txt
