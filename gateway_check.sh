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
[ $? -eq 0 ] && echo "   eth0.2 is using DHCP (udhcpc is active)" || echo "   eth0.2 is using a static IP or DHCP client is not detected"

# Step 4: Default Gateway
DEFAULT_GW=$(ip route show dev eth0.2 | grep "default" | awk '{print $3}')
echo ""
echo "4. Default Gateway: $DEFAULT_GW"
ping -c 2 -I eth0.2 -W 2 $DEFAULT_GW >/dev/null 2>&1
[ $? -eq 0 ] && echo "   Ping Test to $DEFAULT_GW is Reachable" || echo "   Ping Test to $DEFAULT_GW is Unreachable"

# Step 5: Active connections (filtered by eth0.2 IP)
echo ""
echo "5. Active Connections (Bound to $PRIMARY_IP):"
if [ -n "$PRIMARY_IP" ]; then
  netstat -anp 2>/dev/null | grep "$PRIMARY_IP" | sed 's/^/   /'
else
  echo "   Skipped — No valid IP found on eth0.2"
fi

echo ""
echo "===== Diagnostics Complete ====="
