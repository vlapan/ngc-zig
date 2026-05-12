#!/usr/bin/env bash
set -e

fetch_file() {
    local url="$1"
    local target="$2"
    local tmp_file="${target}.tmp"
    local etag_file="${target}.etag"
    local tmp_etag="${target}.etag.tmp"
    local name="$(basename "${target}")"

    # Ensure target directory exists
    mkdir -p "$(dirname "${target}")"

    # We add etag flags. If the file doesn't exist locally, we ensure we don't send a stale etag
    local etag_args=""
    if [ -f "${target}" ] && [ -f "${etag_file}" ]; then
        etag_args="--etag-compare ${etag_file}"
    fi

    local curl_status=0
    local http_code_file="${target}.code"
    
    # curl -w writes to stdout, progress writes to stderr
    eval curl \
        --fail \
        --location \
        --retry 3 \
        --connect-timeout 10 \
        --speed-limit 1000 \
        --speed-time 15 \
        --max-time 300 \
        --remote-time \
        --write-out "%{http_code}" \
        --etag-save "${tmp_etag}" \
        ${etag_args} \
        -o "${tmp_file}" \
        "${url}" > "${http_code_file}" 2> >(tr '\r' '\n' | sed "s/^/MAKE:INFO: ${name}: /" >&2) || curl_status=$?

    local http_code
    http_code=$(cat "${http_code_file}")
    rm -f "${http_code_file}"

    if [ ${curl_status} -eq 0 ]; then
        if [ "${http_code}" = "304" ]; then
            echo "MAKE:INFO: 🟢 [SUCCESS] ${name} is up to date (ETag matched)."
            rm -f "${tmp_file}" "${tmp_etag}"
        else
            if [ -s "${tmp_file}" ]; then
                mv -f "${tmp_file}" "${target}"
                if [ -f "${tmp_etag}" ]; then
                    mv -f "${tmp_etag}" "${etag_file}"
                fi
                echo "MAKE:INFO: 🟢 [SUCCESS] ${name} fetched and installed."
            else
                echo "MAKE:INFO: 🛑 [ERROR] ${name} returned ${http_code} but file is empty!"
                rm -f "${tmp_file}" "${tmp_etag}"
                exit 1
            fi
        fi
    else
        echo "MAKE:INFO: 🛑 [ERROR] Download failed for ${name} with exit code ${curl_status}!"
        rm -f "${tmp_file}" "${tmp_etag}"
        exit ${curl_status}
    fi
}

echo "MAKE:INFO: Fetching upstream DBs securely..."
fetch_file "https://raw.githubusercontent.com/sapics/ip-location-db/refs/heads/main/geo-whois-asn-country/geo-whois-asn-country-ipv4-num.csv" "test/geo-whois-asn-country-ipv4-num.csv"
fetch_file "https://raw.githubusercontent.com/sapics/ip-location-db/refs/heads/main/geo-whois-asn-country/geo-whois-asn-country-ipv6-num.csv" "test/geo-whois-asn-country-ipv6-num.csv"
echo "MAKE:INFO: Test data fetched successfully!"
