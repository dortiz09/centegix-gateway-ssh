#!/bin/sh

echo ""
echo "===== Centegix Ethernet Blocking Diagnostic ====="
echo "Running on $(hostname 2>/dev/null || echo unknown) at $(date)"
echo ""

# ---------- Helpers ----------

pass() { echo "   PASS: $1"; }
fail() { echo "   FAIL: $1"; }
info() { echo "   INFO: $1"; }

# BusyBox nc on this gateway supports only: nc IP PORT
# Run it in the background so a blocked connection cannot hang forever.
tcp_test() {
    TEST_IP="$1"
    TEST_PORT="$2"
    TEST_NAME="$3"

    nc "$TEST_IP" "$TEST_PORT" </dev/null >/dev/null 2>&1 &
    NC_PID=$!

    sleep 3

    if kill -0 "$NC_PID" 2>/dev/null; then
        kill "$NC_PID" 2>/dev/null
        wait "$NC_PID" 2>/dev/null
        fail "$TEST_NAME ($TEST_IP:$TEST_PORT) - connection did not complete within 3 seconds"
        return 1
    fi

    wait "$NC_PID" 2>/dev/null
    NC_RESULT=$?

    if [ "$NC_RESULT" -eq 0 ]; then
        pass "$TEST_NAME ($TEST_IP:$TEST_PORT) - TCP connection succeeded"
        return 0
    else
        fail "$TEST_NAME ($TEST_IP:$TEST_PORT) - TCP connection failed"
        return 1
    fi
}

# ---------- 1. Ethernet interface ----------

echo "1. Ethernet Interface"
ip link show eth0.2 2>/dev/null | grep "state UP" >/dev/null

if [ $? -eq 0 ]; then
    pass "eth0.2 is UP"
else
    fail "eth0.2 is DOWN or not found"
fi

# ---------- 2. Ethernet IP ----------

echo ""
echo "2. Ethernet IP Address"

ETH_IP=""
for IP in $(ip -4 addr show eth0.2 2>/dev/null | awk '/inet / {print $2}'); do
    CLEAN_IP=$(echo "$IP" | cut -d/ -f1)
    echo "$CLEAN_IP" | grep "^169\." >/dev/null
    if [ $? -ne 0 ]; then
        ETH_IP="$CLEAN_IP"
        break
    fi
done

if [ -n "$ETH_IP" ]; then
    info "Ethernet IP: $ETH_IP"
else
    fail "No valid IPv4 address found on eth0.2"
fi

# ---------- 3. Routing ----------

echo ""
echo "3. Routing"

DEFAULT_ROUTE=$(ip route 2>/dev/null | grep "^default" | head -n 1)
echo "   Default route: $DEFAULT_ROUTE"

ETH_ROUTE=$(ip route show dev eth0.2 2>/dev/null | grep "^default")
CELL_ROUTE=$(ip route show dev wwan0 2>/dev/null | grep "^default")

[ -n "$ETH_ROUTE" ] && info "Ethernet has a default route" || fail "Ethernet has no default route"
[ -n "$CELL_ROUTE" ] && info "Cellular has a default route (backup may be available)" || info "No cellular default route detected"

# ---------- 4. Default gateway ----------

echo ""
echo "4. Ethernet Default Gateway"

ETH_GW=$(ip route show dev eth0.2 2>/dev/null | grep "^default" | awk '{print $3}' | head -n 1)

if [ -n "$ETH_GW" ]; then
    info "Ethernet gateway: $ETH_GW"

    ping -c 2 -I eth0.2 -W 2 "$ETH_GW" >/dev/null 2>&1

    if [ $? -eq 0 ]; then
        pass "Ethernet default gateway is reachable"
    else
        fail "Ethernet default gateway is NOT reachable"
    fi
else
    fail "Could not determine Ethernet default gateway"
fi

# ---------- 5. DNS ----------

echo ""
echo "5. DNS"

if [ -f /etc/resolv.conf ]; then
    cat /etc/resolv.conf | sed 's/^/   /'
else
    fail "/etc/resolv.conf not found"
fi

if command -v nslookup >/dev/null 2>&1; then
    nslookup google.com >/dev/null 2>&1

    if [ $? -eq 0 ]; then
        pass "DNS resolution succeeded"
    else
        fail "DNS resolution failed"
    fi
else
    info "nslookup is not installed; DNS test skipped"
fi

# ---------- 6. Route to external IPs ----------

echo ""
echo "6. External Routing"

for TEST_IP in 8.8.8.8 8.8.4.4 35.243.210.132; do
    ROUTE=$(ip route get "$TEST_IP" 2>/dev/null)

    if [ -n "$ROUTE" ]; then
        echo "   $TEST_IP -> $ROUTE"

        echo "$ROUTE" | grep "dev eth0.2" >/dev/null

        if [ $? -eq 0 ]; then
            pass "Traffic to $TEST_IP is routed through Ethernet"
        else
            fail "Traffic to $TEST_IP is NOT routed through eth0.2"
        fi
    else
        fail "No route found to $TEST_IP"
    fi
done

# ---------- 7. Ethernet TCP connectivity ----------

echo ""
echo "7. TCP Connectivity Over Preferred Route"
echo "   These tests use the gateway's normal routing table."

TCP_FAILURES=0

tcp_test "8.8.8.8" "443" "Google HTTPS" || TCP_FAILURES=$((TCP_FAILURES + 1))
tcp_test "8.8.4.4" "443" "Google HTTPS" || TCP_FAILURES=$((TCP_FAILURES + 1))

# Known Centegix endpoints from the V2 Technical Guide
tcp_test "52.52.247.202" "443" "WISDM Remote Management" || TCP_FAILURES=$((TCP_FAILURES + 1))
tcp_test "3.222.152.56" "443" "Centegix LoRaWAN Network Server" || TCP_FAILURES=$((TCP_FAILURES + 1))

# ---------- 8. Existing Ethernet connections ----------

echo ""
echo "8. Existing Connections From Ethernet IP"

if [ -n "$ETH_IP" ]; then
    CONNECTIONS=$(netstat -anp 2>/dev/null | grep "$ETH_IP")

    if [ -n "$CONNECTIONS" ]; then
        echo "$CONNECTIONS" | sed 's/^/   /'
        pass "Existing network connections were found for $ETH_IP"
    else
        info "No active connections found for $ETH_IP"
    fi
else
    info "Skipped because no Ethernet IP was found"
fi

# ---------- Assessment ----------

echo ""
echo "===== Assessment ====="

if [ -z "$ETH_IP" ]; then
    echo "ETHERNET PROBLEM: No valid Ethernet IP was found."
elif [ -z "$ETH_GW" ]; then
    echo "ETHERNET PROBLEM: No Ethernet default gateway was found."
else
    ping -c 1 -I eth0.2 -W 2 "$ETH_GW" >/dev/null 2>&1
    GW_OK=$?

    if [ "$GW_OK" -ne 0 ]; then
        echo "ETHERNET PROBLEM: The Ethernet default gateway is unreachable."
    elif [ "$TCP_FAILURES" -eq 0 ]; then
        echo "NO OBVIOUS ETHERNET BLOCK DETECTED."
        echo "Ethernet has a valid IP, reachable gateway, and all tested TCP endpoints responded."
        echo "If the gateway is still reporting cellular, investigate the gateway's failover/detection logic."
    else
        echo "ETHERNET CONNECTIVITY APPEARS HEALTHY."
        echo "$TCP_FAILURES TCP test(s) failed; other Centegix services are reachable over Ethernet."
        echo "Investigate the failed endpoint(s) separately."
    fi
fi

echo ""
echo "===== Diagnostic Complete ====="
