# NGC (Nginx GeoIP Converter)

A highly optimized, pure Zig CLI tool for converting integer-range GeoIP CSV databases into mathematically flat Nginx `geo` module format.

It handles "dirty" upstream data via a 1D sweep-line algorithm to resolve overlapping blocks (enforcing specificity priorities), then uses a Radix Trie to safely punch holes for static network overrides, automatically fracturing IP ranges into valid Nginx CIDRs, and merging contiguous sibling subnets.

## Usage

```bash
ngc --ipv4 ipv4.csv --ipv6 ipv6.csv --static private.txt --group EU:FR,DE --filter US,CA,EU --output geo.conf
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


### Grouping and Filtering
You can radically reduce the memory footprint of your Nginx configuration by aggregating countries and dropping unwanted networks:
- `--group TARGET:SRC1,SRC2` (e.g. `--group EU:FR,DE`) maps source countries into a target group.
- `--filter SRC1,SRC2` (e.g. `--filter US,CA,EU`) aggressively drops any network not in the list *before* generating CIDRs.
- You can also provide these via files using `--groups-file` and `--filters-file`.

### Output (`--output`)
Space-separated, semicolon-terminated CIDR-to-string mappings directly loadable by the Nginx `geo` module. Output strictness is guaranteed via post-order traversal optimization.
```text
1.0.0.0/24 AU;
1.0.1.0/24 CN;
1.0.2.0/23 AU;
```
