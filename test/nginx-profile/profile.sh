#!/bin/bash
set -e

PROFILE_DIR="$(cd "$(dirname "$0")" && pwd)"
NGINX_BIN=$(which nginx)
PORT=8888

# Storage variables
baseline_rss=0
full_rss=0

profile_nginx() {
    local label="$1"
    local conf="$2"

    echo "=== Profiling: $label ==="
    echo "Config: $conf"
    echo ""

    # Start nginx in foreground (daemon off) but backgrounded
    # Use -p to set prefix so relative paths resolve correctly
    nginx -p "$PROFILE_DIR" -c "$conf" &
    local nginx_pid=$!
    sleep 2

    # Get RSS from ps (in KB)
    local rss
    rss=$(ps -o rss= -p "$nginx_pid" 2>/dev/null | tr -d ' ')
    if [ -z "$rss" ]; then
        echo "ERROR: Failed to measure nginx"
        kill "$nginx_pid" 2>/dev/null || true
        return 1
    fi

    # Store in variables
    if [ "$label" = "baseline" ]; then
        baseline_rss=$rss
    elif [ "$label" = "full" ]; then
        full_rss=$rss
    fi

    echo "Master PID: $nginx_pid (RSS: ${rss} KB)"
    echo ""

    # Make test requests
    if [ "$label" = "full" ]; then
        echo "--- Geo Lookup Timing (unique IPs) ---"
        local total_server=0
        local requests=50

        # Generate unique IPs from different ranges
        local ips=()
        for i in $(seq 1 $requests); do
            oct3=$((RANDOM % 256))
            oct4=$((RANDOM % 256))
            ips+=("1.${oct3}.${oct4}.1")
        done

        # Also add some known IPs
        ips+=("8.8.8.8" "1.1.1.1" "203.0.113.1" "198.51.100.1" "100.0.0.1")

        for ip in "${ips[@]}"; do
            local result
            result=$(curl -s -o /tmp/nginx_resp.txt -w "DNS:%{time_namelookup} Connect:%{time_connect} TTFB:%{time_starttransfer} Total:%{time_total}" \
                "http://127.0.0.1:$PORT/?ip=$ip" 2>/dev/null || echo "FAILED")
            local country
            country=$(cat /tmp/nginx_resp.txt 2>/dev/null || echo "N/A")

            # Extract times
            local connect ttfb server_time
            connect=$(echo "$result" | sed -n 's/.*Connect:\([0-9.]*\).*/\1/p')
            ttfb=$(echo "$result" | sed -n 's/.*TTFB:\([0-9.]*\).*/\1/p')
            server_time=$(echo "scale=6; $ttfb - $connect" | bc 2>/dev/null || echo "N/A")

            echo "  $ip -> $country | server: ${server_time}s (TTFB:$ttfb - Connect:$connect)"

            if [ "$server_time" != "N/A" ]; then
                total_server=$(echo "$total_server + $server_time" | bc 2>/dev/null || echo "$total_server")
            fi
        done

        local count=${#ips[@]}
        local avg_server
        if [ "$count" -gt 0 ]; then
            avg_server=$(echo "scale=6; $total_server / $count" | bc 2>/dev/null || echo "N/A")
        fi
        echo "  Avg server time: ${avg_server}s"
    else
        echo "--- Baseline Timing ---"
        local total_server=0
        local requests=50

        for i in $(seq 1 $requests); do
            local result
            result=$(curl -s -o /dev/null -w "DNS:%{time_namelookup} Connect:%{time_connect} TTFB:%{time_starttransfer} Total:%{time_total}" \
                http://127.0.0.1:$PORT/ 2>/dev/null || echo "FAILED")

            # Extract times
            local connect ttfb server_time
            connect=$(echo "$result" | sed -n 's/.*Connect:\([0-9.]*\).*/\1/p')
            ttfb=$(echo "$result" | sed -n 's/.*TTFB:\([0-9.]*\).*/\1/p')
            server_time=$(echo "scale=6; $ttfb - $connect" | bc 2>/dev/null || echo "N/A")

            echo "  Request $i: server: ${server_time}s (TTFB:$ttfb - Connect:$connect)"

            if [ "$server_time" != "N/A" ]; then
                total_server=$(echo "$total_server + $server_time" | bc 2>/dev/null || echo "$total_server")
            fi
        done

        local avg_server
        if [ "$requests" -gt 0 ]; then
            avg_server=$(echo "scale=6; $total_server / $requests" | bc 2>/dev/null || echo "N/A")
        fi
        echo "  Avg server time: ${avg_server}s"
    fi
    echo ""

    # Stop nginx
    kill "$nginx_pid" 2>/dev/null || true
    wait "$nginx_pid" 2>/dev/null || true
    sleep 0.5
}

echo "========================================="
echo "  Nginx Geo Module Memory Profiler"
echo "========================================="
echo ""

# Kill anything on port first
lsof -ti:$PORT 2>/dev/null | xargs kill -9 2>/dev/null || true
sleep 0.5

# Profile baseline
baseline_conf="$PROFILE_DIR/nginx-baseline.conf"
if [ -f "$baseline_conf" ]; then
    profile_nginx "baseline" "$baseline_conf"
else
    echo "SKIP: $baseline_conf not found"
    echo ""
fi

# Profile full
full_conf="$PROFILE_DIR/nginx-full-foreground.conf"
if [ -f "$full_conf" ]; then
    profile_nginx "full" "$full_conf"
else
    echo "SKIP: $full_conf not found"
    echo ""
fi

# Print comparison
echo "========================================="
echo "  Results Summary"
echo "========================================="
echo ""

delta_rss=$((full_rss - baseline_rss))

# Count CIDRs
v4_count=$(grep -c '\.' "$PROFILE_DIR/../output.txt" 2>/dev/null || echo 0)
v6_count=$(grep -c ':' "$PROFILE_DIR/../output.txt" 2>/dev/null || echo 0)
total_cidrs=$((v4_count + v6_count))

echo "Baseline (no geo rules):"
echo "  RSS: ${baseline_rss} KB"
echo ""
echo "Full ($total_cidrs CIDRs: $v4_count v4, $v6_count v6):"
echo "  RSS: ${full_rss} KB"
echo ""
echo "Delta (rules only):"
echo "  RSS: +${delta_rss} KB"
echo ""

# Per-CIDR calculation
if [ "$total_cidrs" -gt 0 ] && [ "$delta_rss" -gt 0 ]; then
    delta_bytes=$((delta_rss * 1024))
    bytes_per_cidr=$(echo "scale=2; $delta_bytes / $total_cidrs" | bc)
    echo "Per-CIDR memory: ${bytes_per_cidr} bytes"
    echo ""
    echo "Current heuristic: 97B/CIDR"
    echo "Actual measured:   ~${bytes_per_cidr}B avg"
fi

echo ""
echo "========================================="
echo "  Done"
echo "========================================="
