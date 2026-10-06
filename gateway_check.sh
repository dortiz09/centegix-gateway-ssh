#!/bin/sh

echo ""
echo "===== Centegix Gateway Connectivity Check ====="

# Step 0: Hostname and time
HOST=$(hostname 2>/dev/null)
[ -z "$HOST" ] && HOST="unknown"
echo "Running on $HOST at $(date)"

# Step 1: Interface status
echo ""
echo "1. Interface eth0.2 status:"
ip link show eth0.2 2>/dev/null | grep "state UP" >/dev/null
[ $? -eq 0 ] && echo "   eth0.2 is UP" || echo "   eth0.2 is DOWN or not found"

# Step 2: IP address on eth0.2 (BusyBox-safe with persistent variable)
echo ""
echo "2. IP address on eth0.2:"
PRIMARY_IP=""
for IP in $(ip -4 addr show eth0.2 | awk '/inet / {print $2}'); do
  CLEAN_IP=$(echo "$IP" | cut -d/ -f1)
  echo "$CLEAN_IP" | grep "^169\." >/dev/null
  if [ $? -ne 0 ]; then
    PRIMARY_IP="$CLEAN_IP"
    break
  fi
done

if [ -n "$PRIMARY_IP" ]; then
  echo "   IP Address: $PRIMARY_IP"
else
  echo "   No valid IP assigned"
fi

# Step 3: IP assignment type
echo ""
echo "3. IP Assignment Type:"
ps | grep "udhcpc.*eth0.2" | grep -v grep >/dev/null
[ $? -eq 0 ] && echo "   eth0.2 is using DHCP (udhcpc is active)" || echo "   eth0.2 is likely using a static IP"

# Step 4: Default Gateway
DEFAULT_GW=$(ip route show dev eth0.2 | grep "default" | awk '{print $3}')
echo ""
echo "4. Default Gateway: $DEFAULT_GW"
ping -c 2 -I eth0.2 -W 2 $DEFAULT_GW >/dev/null 2>&1
[ $? -eq 0 ] && echo "   Ping Test to $DEFAULT_GW is Reachable" || echo "   Ping Test to $DEFAULT_GW is Unreachable"

# Step 5: Connectivity Test via eth0.2
echo ""
echo "5. Connectivity Test via eth0.2:"

# General Internet / Centegix connectivity
for HOSTNAME in google.com centegix.com; do
  for PORT in 80 443; do
    nc -zvw2 $HOSTNAME $PORT >/dev/null 2>&1
    if [ $? -eq 0 ]; then
      printf "   %-40s : Reachable\n" "$HOSTNAME:$PORT"
    else
      printf "   %-40s : Unreachable\n" "$HOSTNAME:$PORT"
    fi
  done
done

# WISDM / V2 Gateway Remote Management
for IP in 52.8.200.52 52.52.247.202 54.176.253.249 54.177.127.136 54.215.92.247 54.241.17.58; do
  for PORT in 22 443 8443 8883; do
    nc -zvw2 $IP $PORT >/dev/null 2>&1
    if [ $? -eq 0 ]; then
      printf "   %-40s : Reachable\n" "$IP:$PORT"
    else
      printf "   %-40s : Unreachable\n" "$IP:$PORT"
    fi
  done
done

# Step 6: Active connections (filtered by eth0.2 IP)
echo ""
echo "6. Active Connections (Bound to $PRIMARY_IP):"
if [ -n "$PRIMARY_IP" ]; then
  netstat -anp 2>/dev/null | grep "$PRIMARY_IP" | sed 's/^/   /'
else
  echo "   Skipped — No valid IP found on eth0.2"
fi

echo ""
echo "===== Diagnostics Complete ====="
