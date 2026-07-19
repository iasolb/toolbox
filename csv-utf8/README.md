# csv-utf8

Rewrites non-UTF-8 CSV files as UTF-8 in place. Built because mixed-encoding
CSVs (cp1252 exports, UTF-16 spreadsheet dumps, BOM-prefixed files) keep
breaking pandas reads.

## Usage

```bash
python ensure_utf8.py path/to/file.csv
python ensure_utf8.py path/to/dir          # walks the tree for *.csv
python ensure_utf8.py path/to/dir --dry-run
```

Every file gets one report line: `ok` (already clean UTF-8, untouched),
`converted` (rewritten, with the detected source encoding), `empty`, or
`FAILED`. Exit code is 1 only if something failed.

## Detection order

1. BOM sniff (utf-8-sig, utf-16, utf-32). BOMs are stripped on rewrite.
2. Strict UTF-8 decode (the fast path, means no rewrite).
3. `charset-normalizer` if installed (better detection, worth `pip install`ing).
4. Builtin fallback chain: cp1252, then latin-1.

Output is always UTF-8 without BOM.

## machine-sync integration

The `--csv` flag on the machine-sync commands runs this tool over the
transfer destination after a successful transfer. It is streamed over ssh
for pushes, so the receiving machine needs a Python but not a copy of this
repo. Stdlib is enough; charset-normalizer just improves detection.
