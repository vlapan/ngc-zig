#!/usr/bin/env bash

if [ -z "$1" ]; then
	echo "ERROR: no binary provided!" >&2
	exit 1
fi

BINARY="$1"
CMD="$*"
RATE="1000000"

parse() {
	# Set your samply --rate here

	# Print Header
	printf "%-12s %-12s %-8s %-12s %s\n" "TIME (ms)" "PROBES" "REL %" "OFFSET" "SYMBOL / SOURCE LINE"
	printf "%-12s %-12s %-8s %-12s %s\n" "---------" "------" "-----" "------" "--------------------"

	# 1. JQ: Extract raw probes and decimal addresses
	DATA="$(cat - | jq -r --argjson r "${RATE}" '.threads[0] as $t | 
	($t.samples.weight | add) as $tp |
	reduce range(0; ($t.samples.stack | length)) as $i ({};
		($t.frameTable.address[$t.stackTable.frame[$t.samples.stack[$i]]]) as $addr |
		.[($addr + 4294967296) | tostring] += $t.samples.weight[$i]
	) |
	to_entries[] | "\(.value) \($tp) \(.key)"' | sort -rn | head -n 100)"

	# 2. Run LLDB and create a map keyed by DECIMAL address to avoid hex padding issues
	SYMBOLS="$(lldb "${BINARY}" --batch -s <(
		echo "${DATA}" | while read -r val tp addr; do
			printf "image lookup -a %s\n" "$addr"
		done
	) 2>/dev/null | \
		awk '/Address:/{
				match($0, /0x[0-9a-fA-F]+/); 
				hex=substr($0, RSTART, RLENGTH);
				# Convert hex to decimal for stable mapping
				cmd = "printf %d " hex;
				cmd | getline dec;
				close(cmd);
			} 
			/Summary:/{
				sub(/.*Summary: /, "");
				print dec "|" $0
			}')"

	# 3. Final Output Loop
	echo "${DATA}" | while read -r val tp addr; do
		ms=$(awk -v v="$val" -v r="${RATE}" 'BEGIN {printf "%.2f", (v/r)*1000}')
		pct=$(awk -v v="$val" -v t="$tp" 'BEGIN {printf "%.1f%%", (v/t)*100}')
		
		# Extract symbol from our map using the decimal key
		resolved=$(echo "${SYMBOLS}" | grep "^${addr}|" | cut -d'|' -f2)
		
		# Convert decimal back to hex just for the display column
		hex_display=$(printf "0x%x" "$addr")
		
		printf "%-12s %-12s %-8s %-12s %s\n" "${ms}ms" "$val" "$pct" "$hex_display" "${resolved:-[Unknown]}"
	done
}

samply record \
	--save-only \
	--unstable-presymbolicate \
	--jit-markers \
	--fold-recursive-prefix \
	--rate "${RATE}" \
	--output /dev/stdout \
	${CMD} 2>/dev/null | parse | tee test/profile.txt
