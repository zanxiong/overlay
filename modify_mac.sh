#!/bin/sh

MAC_R="/etc/udev/rules.d/99-custom-mac.rules"

VENDER="00:11:22"

# Get the default network interface
#INTERFACE=$(ip route | grep default | awk '{print $5}')

# Generate a random MAC address
NEW_MAC=$VENDER$(hexdump -n 3 -e '1/1 ":%02X"' /dev/urandom)

#echo "default nic $INTERFACE"
echo "new MAC $NEW_MAC"

if [ -f $MAC_R ]; then
        echo "$MAC_R file exist, did you aready have the mac rules? skip mac modication!"
else
        sudo tee -a $MAC_F << EOF
ACTION=="add", SUBSYSTEM=="net", ATTR{address}=="88:88:88:88:87:88", RUN+="/sbin/ip link set dev %k address $NEW_MAC"
EOF
fi

echo "modify mac done!"
