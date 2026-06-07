#!/bin/bash

backed_user="opaq"
LOGFILE="/var/log/backup_$(date +%F).log"
KEYFILE="/root/id_rsa"
VPNKEY="/root/backup.ovpn"
SERVER="10.8.0.1"
FOLDER_PATH="/home/$backed_user/Backup/"
STOP=0
trap "STOP=1" INT

timestamp() {
    date +"[%Y-%m-%d %H:%M:%S]"
}

log() {
    echo "$(timestamp) $1" | tee -a "$LOGFILE"
}

#############################################
# Check if VPN interface exists + real internet
#############################################
check_internet() {
    timeout 1 curl -s --head https://1.1.1.1 >/dev/null 2>&1
}

#############################################
# Clean exit (kills VPN first)
#############################################
clean_exit() {
    log "Network unavailable or stop requested. Cleaning up..."
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
sudo openvpn --config $VPNKEY --verb 0 --mute 20 &>/dev/null &

log "Connecting to VPN..."

#############################################
# Wait for VPN tunnel
#############################################
until check_internet; do
    if [ "$STOP" -eq 1 ]; then clean_exit; fi
    log "Waiting for VPN Tunnel..."
    sleep 1
done

log "VPN connected."

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

    log "Copying: $f"

    timeout 5 scp -q -i $KEYFILE "$f" "$backed_user"@$SERVER:$FOLDER_PATH
    SCP_STATUS=$?

    if [ $SCP_STATUS -ne 0 ]; then
        log "SCP failed for $f (status $SCP_STATUS)"
        clean_exit
    fi

done

#############################################
# Stop VPN
#############################################
log "killing vpn quietly"
sudo pkill -f openvpn >/dev/null 2>&1
