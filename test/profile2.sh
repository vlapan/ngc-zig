#!/usr/bin/env bash

if [ -z "$1" ]; then
	echo "ERROR: no binary provided!" >&2
	exit 1
fi

BINARY="$1"
CMD="$*"
RATE="1000000"

parse() {
	# 1. JQ: Your original logic (with -rs for stream safety)
	DATA="$(cat - | jq -r --argjson r "${RATE}" '.threads[0] as $t | 
	($t.samples.weight | add) as $tp |
	reduce range(0; ($t.samples.stack | length)) as $i ({};
		($t.frameTable.address[$t.stackTable.frame[$t.samples.stack[$i]]]) as $addr |
		.[($addr + 4294967296) | tostring] += $t.samples.weight[$i]
	) | 
	to_entries[] | "\(.value) \($tp) \(.key)"' | sort -rn | head -n 50)"

	# Print Header
	printf "%-12s %-12s %-8s %-12s %s\n" "TIME (ms)" "PROBES" "REL %" "OFFSET" "SYMBOL / SOURCE LINE (INLINED)"
	printf "%-12s %-12s %-8s %-12s %s\n" "---------" "------" "-----" "------" "------------------------------"

	# 2. Final Output Loop
	echo "$DATA" | while read -r val tp addr; do
		ms=$(awk -v v="$val" -v r="${RATE}" 'BEGIN {printf "%.2f", (v/r)*1000}')
		pct=$(awk -v v="$val" -v t="$tp" 'BEGIN {printf "%.1f%%", (v/t)*100}')
		hex_display=$(printf "0x%x" "$addr")

		# Get inlined symbols. We use 'sed' to indent the inlined parts for readability.
		resolved=$(xcrun atos -i -o "${BINARY}" "$hex_display" 2>/dev/null | sed '2,$s/^/                                                /')
		
		# Print the first line of the symbol next to the stats
		# Subsequent inlined lines will follow via the 'resolved' variable
		printf "%-12s %-12s %-8s %-12s %s\n" "${ms}ms" "$val" "$pct" "$hex_display" "$resolved"
		echo "--------------------------------------------------------------------------------"
	done
}

samply record \
	--save-only \
	--unstable-presymbolicate \
	--jit-markers \
	--fold-recursive-prefix \
	--rate "${RATE}" \
	--output /dev/stdout \
	${CMD} 2>/dev/null | parse | tee test/profile2.txt
