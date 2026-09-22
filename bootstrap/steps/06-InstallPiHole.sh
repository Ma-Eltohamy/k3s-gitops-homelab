#!/usr/bin/env bash
# Install Pi-hole on the homelab node and add local DNS records.
# USERNAME, USERPASSWORD, MACHINENAME, MACHINEIP come from bootstrap.sh
# set -euo pipefail

[[ -z "$USERNAME" ]]     && fail "USERNAME is not set"
[[ -z "$USERPASSWORD" ]] && fail "USERPASSWORD is not set"
[[ -z "$MACHINENAME" ]]  && fail "MACHINENAME is not set"
[[ -z "$MACHINEIP" ]]    && fail "MACHINEIP is not set"

# Ask for everything upfront
read -rp "pi-hole Web port [8080]: " WEBPORT
if [[ -z "$WEBPORT" ]]; then
  WEBPORT="8080"
fi
[[ "$WEBPORT" =~ ^[0-9]+$ ]] && (( WEBPORT > 0 && WEBPORT < 65536 )) \
  || fail "Invalid port: $WEBPORT"

read -rp "DNS interface [tailscale0]: " DNSINTERFACE
if [[ -z "$DNSINTERFACE" ]]; then
  DNSINTERFACE="tailscale0"
fi

read -rp "How many local DNS records do you want to add: " DNS_LOCAL_REC_NUM
[[ "$DNS_LOCAL_REC_NUM" =~ ^[0-9]+$ ]] || fail "Invalid number: $DNS_LOCAL_REC_NUM"

HOSTSARR=""
for i in $(seq "$DNS_LOCAL_REC_NUM")
do
  read -rp "Record $i hostname (e.g. pihole.homelab): " RECORDNAME
  [[ "$RECORDNAME" =~ ^[a-z0-9.-]+$ ]] || fail "Invalid hostname: '$RECORDNAME'"

  # if first item/only one item, then no commas
  if [[ -z "$HOSTSARR" ]]; then
    HOSTSARR="\"$MACHINEIP $RECORDNAME\""
  else
    HOSTSARR="$HOSTSARR,\"$MACHINEIP $RECORDNAME\""
  fi
done
HOSTSARR="[$HOSTSARR]"

echo "-------------------------------------"
echo "[=] Installing Pi-hole on $MACHINENAME"
echo "-------------------------------------"

sshpass -p "$USERPASSWORD" ssh -o StrictHostKeyChecking=no -tt "$USERNAME@$MACHINENAME" "
  set -e
  echo '$USERPASSWORD' | sudo -S -p '' -v
  curl -sSL https://install.pi-hole.net | sudo bash
  sudo pihole-FTL --config webserver.port '${WEBPORT}o,[::]:${WEBPORT}o,443os,[::]:443os'
  sudo pihole-FTL --config dns.interface '${DNSINTERFACE}'
  sudo pihole-FTL --config dns.listeningMode SINGLE
  sudo pihole setpassword
  sudo systemctl restart pihole-FTL.service
" || fail "Pi-hole installation failed"

echo "[=] Pi-hole installed: http://$MACHINENAME:$WEBPORT/admin"

if [[ "$DNS_LOCAL_REC_NUM" -eq 0 ]]; then
  echo "[=] No DNS records to add, skipping."
else
  echo "-------------------------------------"
  echo "[=] Adding local DNS records: $HOSTSARR"
  echo "-------------------------------------"

  sshpass -p "$USERPASSWORD" ssh -o StrictHostKeyChecking=no -tt "$USERNAME@$MACHINENAME" "
    set -e
    echo '$USERPASSWORD' | sudo -S -p '' -v
    sudo pihole-FTL --config dns.hosts '${HOSTSARR}'
    sudo systemctl restart pihole-FTL.service
  " || fail "Could not add DNS records"

  echo "[=] $DNS_LOCAL_REC_NUM DNS record(s) added."
fi

echo "-------------------------------------"
echo "[=] Last manual step:"
echo "    Open the Tailscale admin console > DNS, add $MACHINEIP as a nameserver,"
echo "    and turn on 'Override DNS servers'."
echo "-------------------------------------"
