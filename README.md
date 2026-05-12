# NGC (Nginx GeoIP Converter)

A highly optimized, pure Zig CLI tool for converting integer-range GeoIP CSV databases into Nginx `geo` module format. It uses a Radix Trie to safely punch holes for static network overrides and automatically merges contiguous identically-mapped sibling subnets.

## Usage

```bash
ngc --ipv4 ipv4.csv --ipv6 ipv6.csv --static private.txt --output geo.conf
```
*(At least one input file is required. All flags are optional).*

## File Formats

### Input: GeoIP CSV (`--ipv4`, `--ipv6`)
Expects a headerless CSV formatted as `start_ip_integer,end_ip_integer,country_code`.
```csv
16777216,16777471,AU
16777472,16778239,CN
16778240,16779263,AU
```

### Input: Static Overrides (`--static`)
Allows manually defining specific IP blocks to override the CSV databases (e.g. for private IPs). Expects `IP/CIDR COMMENT;`.
```text
127.0.0.0/8 RFC1918;
10.0.0.0/8 RFC1918;
192.168.0.0/16 RFC1918;
```

### Output (`--output`)
Space-separated, semicolon-terminated CIDR-to-string mappings directly loadable by the Nginx `geo` module. Output strictness is guaranteed via post-order traversal optimization.
```text
1.0.0.0/24 AU;
1.0.1.0/24 CN;
1.0.2.0/23 AU;
10.0.0.0/8 RFC1918;
127.0.0.0/8 RFC1918;
```
