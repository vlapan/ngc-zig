# Define phony targets so Make doesn't look for files named 'all' or 'clean'
.PHONY: all build release clean run

SHELL := /opt/homebrew/bin/zsh
.SHELLFLAGS := -e -o pipefail -c

# The first target is the default one run by 'make'
all: build clean run compare


BINARY := zig-out/bin/geoip-converter
SOURCES := $(shell find . -name "*.zig")

$(BINARY): $(SOURCES)
	@echo "MAKE:INFO: Compiling the project (optimised version)..."
	@# rm -rf .zig-cache zig-out 2>&1
	zig build --release=fast -Dcpu=native -Dtarget=native --summary all -Dstamp=false 2>&1
	@echo "MAKE:INFO: binary '${BINARY}' compilation done!"

build: $(BINARY)

run: $(BINARY) clean
	@echo "MAKE:INFO: Executing './zig-out/bin/geoip-converter' binary..."
	/usr/bin/time -al ${BINARY} --ipv4 test/geo-whois-asn-country-ipv4-num.csv --ipv6 test/geo-whois-asn-country-ipv6-num.csv --output test/output.txt --static test/private.txt 2>&1
	@echo "MAKE:INFO: Done!"

profile: $(BINARY)
	@echo "MAKE:INFO: Profiling binary..."
	@bash test/profile.sh ${BINARY} --ipv4 test/geo-whois-asn-country-ipv4-num.csv --ipv6 test/geo-whois-asn-country-ipv6-num.csv --output test/output.txt --static test/private.txt
	@echo "MAKE:INFO: Done!"

release:
	@echo "MAKE:INFO: Compiling the project (optimised stamped/release version)..."
	@# rm -rf .zig-cache zig-out 2>&1
	zig build --release=fast -Dcpu=native -Dtarget=native --summary all -Dstamp=true 2>&1
	@echo "MAKE:INFO: binary '${BINARY}' compilation done!"

debug:
	@echo "MAKE:INFO: Compiling the project (debug version)..."
	@# rm -rf .zig-cache zig-out 2>&1
	zig build --summary all 2>&1
	@echo "MAKE:INFO: binary '${BINARY}' compilation done!"

clean:
	@echo "MAKE:INFO: Removing 'test/output.txt' output..."
	rm -rf test/output.txt 2>&1
	@echo "MAKE:INFO: Cleaning done!"
