#!/usr/bin/env bash
set -e

if [ -t 1 ]; then
    BOLD="\033[1m"
    RED="\033[31m"
    GREEN="\033[32m"
    YELLOW="\033[33m"
    RESET="\033[0m"
else
    BOLD=""
    RED=""
    GREEN=""
    YELLOW=""
    RESET=""
fi

echo "======================================================================"
DATE=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
COMMIT=$(git rev-parse --short HEAD)
DIRTY=$(git diff --quiet src/ || echo "- DIRTY")
echo -e "${BOLD}Date:${RESET} $DATE | ${BOLD}Commit:${RESET} $COMMIT $DIRTY"
echo "----------------------------------------------------------------------"

echo -e "${BOLD}[1/5] Compiling Release Binary...${RESET}"
make clean > /dev/null
make release > /dev/null 2>&1
if [ ! -f "zig-out/bin/ngc" ]; then
    echo -e "${RED}Compilation failed!${RESET}"
    exit 1
fi
echo "      OK"

echo -e "${BOLD}[2/5] File Metrics:${RESET}"
BIN_SIZE=$(ls -lh zig-out/bin/ngc | awk '{print $5}')
V4_SIZE=$(ls -lh test/geo-whois-asn-country-ipv4-num.csv | awk '{print $5}')
V6_SIZE=$(ls -lh test/geo-whois-asn-country-ipv6-num.csv | awk '{print $5}')
OUT_SIZE=$(ls -lh test/output.txt | awk '{print $5}')
echo "      Binary: $BIN_SIZE | IPv4 CSV: $V4_SIZE | IPv6 CSV: $V6_SIZE | Output: $OUT_SIZE"

echo -e "${BOLD}[3/5] Application Stats (Cold Run):${RESET}"
/usr/bin/time -al zig-out/bin/ngc --ipv4 test/geo-whois-asn-country-ipv4-num.csv --ipv6 test/geo-whois-asn-country-ipv6-num.csv --output test/output.txt --static test/private.txt > /dev/null 2> /tmp/ngc_time_cold.txt

grep "Inputs (ranges parsed)" /tmp/ngc_time_cold.txt | sed 's/^  /      /' || true
grep -E "^  Phase 1" /tmp/ngc_time_cold.txt | sed 's/^  /      /' || true
grep -E "^  Phase 2" /tmp/ngc_time_cold.txt | sed 's/^  /      /' || true
grep "Outputs (CIDR" /tmp/ngc_time_cold.txt | sed 's/^  /      /' || true
grep "Pipeline Profiling" /tmp/ngc_time_cold.txt | sed 's/^  /      /' || true

echo -e "${BOLD}[4/5] Performance Metrics:${RESET}"

# Hot runs
/usr/bin/time -al zig-out/bin/ngc --ipv4 test/geo-whois-asn-country-ipv4-num.csv --ipv6 test/geo-whois-asn-country-ipv6-num.csv --output test/output.txt --static test/private.txt > /dev/null 2> /tmp/ngc_time_hot1.txt
/usr/bin/time -al zig-out/bin/ngc --ipv4 test/geo-whois-asn-country-ipv4-num.csv --ipv6 test/geo-whois-asn-country-ipv6-num.csv --output test/output.txt --static test/private.txt > /dev/null 2> /tmp/ngc_time_hot2.txt
/usr/bin/time -al zig-out/bin/ngc --ipv4 test/geo-whois-asn-country-ipv4-num.csv --ipv6 test/geo-whois-asn-country-ipv6-num.csv --output test/output.txt --static test/private.txt > /dev/null 2> /tmp/ngc_time_hot3.txt

# Parse function
parse_time() {
    local file=$1
    local name=$2
    
    awk -v name="$name" '
    function commas(n) {
        str = sprintf("%d", n);
        res = "";
        len = length(str);
        for(i=1; i<=len; i++) {
            res = res substr(str, i, 1);
            if ((len - i) > 0 && (len - i) % 3 == 0) res = res ",";
        }
        return res;
    }
    /real/ && /user/ && /sys/ {
        real = $1
        user = $3
        sys = $5
    }
    /maximum resident set size/ { rss = $1 }
    /instructions retired/ { inst = $1 }
    /cycles elapsed/ { cyc = $1 }
    /voluntary context switches/ && !/involuntary/ { vctx = $1 }
    /involuntary context switches/ { ictx = $1 }
    END {
        rss_mb = rss / 1024 / 1024;
        printf "| %-4s | %5ss | %5ss | %5ss | %4.1f MB | %14s | %14s | %8s |\n", name, real, user, sys, rss_mb, commas(inst), commas(cyc), vctx "/" ictx;
    }
    ' "$file"
}

echo "| Type | Real   | User   | Sys    | Max RSS |   Instructions |         Cycles | Ctx Sw   |"
echo "|------|--------|--------|--------|---------|----------------|----------------|----------|"
parse_time /tmp/ngc_time_cold.txt "Cold"
parse_time /tmp/ngc_time_hot1.txt "Hot1"
parse_time /tmp/ngc_time_hot2.txt "Hot2"
parse_time /tmp/ngc_time_hot3.txt "Hot3"
echo ""

echo -e "${BOLD}[5/5] Output Verification:${RESET}"
if git diff --quiet test/output.txt; then
    echo -e "      ${GREEN}[OK] No changes in test/output.txt. Output exactly matches baseline.${RESET}"
else
    echo -e "      ${YELLOW}[NOTICE] test/output.txt has changed!${RESET}"
    echo -e "      If this is an intentional formatting or feature change, review the diff:"
    git diff --stat test/output.txt | sed 's/^/      /'
fi
echo "======================================================================"
