#!/bin/bash

backed_user="opaq"

STOP=0
trap "STOP=1" INT

#############################################
# Check if VPN interface exists + real internet
#############################################
check_internet() {
    if ! timeout 1 curl -s --head https://1.1.1.1 >/dev/null 2>&1; then
        return 1
    fi
}

#############################################
# Clean exit (kills VPN first)
#############################################
clean_exit() {
    echo "Network unavailable or stop requested. Cleaning up..."
    sudo pkill -f openvpn >/dev/null 2>&1
    exit 1
}

#############################################
# Ensure internet before starting
#############################################
if ! check_internet; then
    clean_exit
fi

#############################################
# Restart VPN
#############################################
sudo pkill -f openvpn >/dev/null 2>&1
sudo openvpn --config /root/backup.ovpn --verb 0 --mute 20 &>/dev/null &

echo "Connecting to VPN..."

#############################################
# Wait for VPN tunnel
#############################################
until check_internet; do
    if [ "$STOP" -eq 1 ]; then clean_exit; fi
    echo "Waiting for VPN Tunnel..."
    sleep 1
done

echo "VPN connected."

#############################################
# Begin backup
#############################################
find /home/"$backed_user" -type f \
  -not -path "/home/$backed_user/.config/*" \
  -not -path "/home/$backed_user/.cache/*" \
  -not -path "/home/$backed_user/.local/*" \
  -not -path "/home/$backed_user/.*" \
  -not -path "*/.*" \
  -not -name ".*" \
  -not -name "*.tmp" \
  -not -name "*.swp" \
  -not -name "*.log" \
  -not -name "*.deb" \
  -not -name "*.iso" \
  -print0 |
while IFS= read -r -d '' f; do

    if [ "$STOP" -eq 1 ]; then clean_exit; fi

    if ! check_internet; then clean_exit; fi

    echo "Copying: $f"

    timeout 5 scp -q -i /root/id_rsa "$f" $backed_user@10.8.0.1:/home/$backed_user/Backup/
    SCP_STATUS=$?

    if [ $SCP_STATUS -ne 0 ]; then
        clean_exit
    fi

done

#############################################
# Stop VPN
#############################################
echo "killing vpn quietly"
sudo pkill -f openvpn >/dev/null 2>&1
