#!/usr/bin/env bash
set -e

fetch_file() {
    local url="$1"
    local target="$2"
    local tmp_file="${target}.tmp"
    local name="$(basename "${target}")"

    local cond=""
    if [ -f "${target}" ]; then
        cond="-z ${target}"
    fi

    # Ensure target directory exists
    mkdir -p "$(dirname "${target}")"

    local curl_status=0
    # Execute curl with robust parameters
    eval curl \
        --fail \
        --location \
        --retry 3 \
        --connect-timeout 10 \
        --speed-limit 1000 \
        --speed-time 15 \
        --max-time 300 \
        --remote-time \
        ${cond} \
        -o "${tmp_file}" \
        "${url}" 2>&1 | tr '\r' '\n' | sed "s/^/MAKE:INFO: ${name}: /" || curl_status=$?

    if [ ${curl_status} -eq 0 ] && [ -s "${tmp_file}" ]; then
        mv -f "${tmp_file}" "${target}"
        echo "MAKE:INFO: 🟢 [SUCCESS] ${name} fetched and installed."
    elif [ ${curl_status} -eq 0 ]; then
        echo "MAKE:INFO: 🟢 [SUCCESS] ${name} is up to date."
        rm -f "${tmp_file}"
    else
        echo "MAKE:INFO: 🛑 [ERROR] Download failed for ${name} with exit code ${curl_status}!"
        rm -f "${tmp_file}"
        exit ${curl_status}
    fi
}

echo "MAKE:INFO: Fetching upstream DBs securely..."
fetch_file "https://raw.githubusercontent.com/sapics/ip-location-db/refs/heads/main/geo-whois-asn-country/geo-whois-asn-country-ipv4-num.csv" "test/geo-whois-asn-country-ipv4-num.csv"
fetch_file "https://raw.githubusercontent.com/sapics/ip-location-db/refs/heads/main/geo-whois-asn-country/geo-whois-asn-country-ipv6-num.csv" "test/geo-whois-asn-country-ipv6-num.csv"
echo "MAKE:INFO: Test data fetched successfully!"
