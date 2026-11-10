#!/usr/bin/env python3
"""Lists the fields in the repo's CloudKit schema that an exported schema doesn't have yet.

usage: schema-missing.py <cloudkit/schema.ckdb> <exported.ckdb>
Prints one "RecordType.field" per line (nothing when the exported schema has them all).
TestFlight builds use the Production environment, so a field missing there means the
schema still has to be deployed in the CloudKit Console.
"""
import re
import sys

RECORD = re.compile(r"RECORD\s+TYPE\s+([A-Za-z_][\w]*)\s*\((.*?)\);", re.S)
FIELD = re.compile(r'^\s*"?([A-Za-z_][\w]*)"?\s+(?:STRING|INT64|DOUBLE|TIMESTAMP|REFERENCE|BYTES|ASSET|LOCATION|LIST)', re.M)


def fields(path):
    with open(path, encoding="utf-8") as handle:
        text = handle.read()
    result = set()
    for record, body in RECORD.findall(text):
        for name in FIELD.findall(body):
            if not name.startswith("___"):
                result.add(f"{record}.{name}")
    return result


def main():
    wanted = fields(sys.argv[1])
    present = fields(sys.argv[2])
    for name in sorted(wanted - present):
        print(name)


if __name__ == "__main__":
    main()
