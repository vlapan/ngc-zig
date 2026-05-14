# Define phony targets so Make doesn't look for files named 'all' or 'clean'
.PHONY: all build release clean run test fetch-data

SHELL := /opt/homebrew/bin/zsh
.SHELLFLAGS := -e -o pipefail -c

# The first target is the default one run by 'make'
all: build run


BINARY := zig-out/bin/ngc
SOURCES := $(shell find . -name "*.zig")
TEST_V4 := test/geo-whois-asn-country-ipv4-num.csv
TEST_V6 := test/geo-whois-asn-country-ipv6-num.csv

$(BINARY): $(SOURCES)

build:
	@echo "MAKE:INFO: Compiling the project (optimised version)..."
	zig build --release=fast -Dcpu=native -Dtarget=native --summary all -Dstamp=false 2>&1
	@echo "MAKE:INFO: binary '${BINARY}' compilation done!"

$(TEST_V4) $(TEST_V6):
	@$(MAKE) fetch-data

run: $(BINARY) $(TEST_V4) $(TEST_V6)
	@echo "MAKE:INFO: Executing './zig-out/bin/ngc' binary..."
	/usr/bin/time -al ${BINARY} --ipv4 $(TEST_V4) --ipv6 $(TEST_V6) --output test/output.txt --static test/private.txt 2>&1
	@echo "MAKE:INFO: Done!"

profile: $(BINARY) $(TEST_V4) $(TEST_V6)
	@echo "MAKE:INFO: Profiling binary..."
	@bash test/profile.sh ${BINARY} --ipv4 $(TEST_V4) --ipv6 $(TEST_V6) --output test/output.txt --static test/private.txt
	@echo "MAKE:INFO: Done!"

profile2: $(BINARY) $(TEST_V4) $(TEST_V6)
	@echo "MAKE:INFO: Profiling binary..."
	@bash test/profile2.sh ${BINARY} --ipv4 $(TEST_V4) --ipv6 $(TEST_V6) --output test/output.txt --static test/private.txt
	@echo "MAKE:INFO: Done!"

release:
	@echo "MAKE:INFO: Compiling the project (optimised stamped/release version)..."
	zig build --release=fast -Dcpu=native -Dtarget=native --summary all -Dstamp=true 2>&1
	@echo "MAKE:INFO: binary '${BINARY}' compilation done!"

debug:
	@echo "MAKE:INFO: Compiling the project (debug version)..."
	zig build -Dcpu=native -Dtarget=native --summary all -Dstamp=false 2>&1
	@echo "MAKE:INFO: binary '${BINARY}' compilation done!"

clean:
	@echo "MAKE:INFO: Cleaning zig output directories..."
	rm -rf .zig-cache zig-out 2>&1
	@echo "MAKE:INFO: Cleaning done!"

fmt:
	@echo "MAKE:INFO: Formatting Zig source files..."
	zig fmt src/*.zig build.zig
	@echo "MAKE:INFO: Formatting done!"

test:
	@echo "MAKE:INFO: Building and running unit tests..."
	zig build test
	@./zig-out/bin/ngc-test
	@echo "MAKE:INFO: Tests passed!"

bench:
	@bash test/benchmark.sh | tee -a benchmarks.log

fetch-data:
	@bash test/fetch-data.sh
