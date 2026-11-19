#!/usr/bin/env python3
"""Keeps automatic signing from piling up development certificates.

Each CI run starts on a fresh Mac, so `xcodebuild -allowProvisioningUpdates` creates a new
"Apple Development" certificate whose private key is gone when the runner is. This script
records the signing identities before archiving and, afterwards, revokes only the ones that run
created, through the App Store Connect API. Nothing else on the account is touched.

usage: ci-certificates.py snapshot <file>       record the identities in the keychain
       ci-certificates.py revoke-new <file>     revoke identities added since the snapshot
       ci-certificates.py check -               what Apple answers about the account's
                                                certificates and profiles (counts and Apple's
                                                error messages only, never names: the log is public)
env:   ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_PATH    (revoke-new and check)

Standard library plus the `security` and `openssl` tools that ship with macOS.
"""
import base64
import json
import os
import re
import subprocess
import sys
import time
import urllib.request

API = "https://api.appstoreconnect.apple.com/v1"


def normalize(serial):
    return serial.strip().upper().lstrip("0")


def keychain_serials():
    """Serial numbers of the Apple Development certificates in the keychain."""
    pems = subprocess.run(
        ["security", "find-certificate", "-a", "-c", "Apple Development", "-p"],
        capture_output=True, text=True,
    ).stdout
    serials = set()
    for pem in re.findall(r"-----BEGIN CERTIFICATE-----.+?-----END CERTIFICATE-----", pems, re.S):
        out = subprocess.run(["openssl", "x509", "-noout", "-serial"], input=pem, capture_output=True, text=True).stdout
        if out.startswith("serial="):
            serials.add(normalize(out[len("serial="):]))
    return serials


def b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def der_to_raw(signature):
    """ECDSA DER signature (from openssl) to the raw r||s form JWT expects."""
    assert signature[0] == 0x30
    index = 2 if signature[1] < 0x80 else 2 + (signature[1] & 0x7F)
    parts = []
    for _ in range(2):
        assert signature[index] == 0x02
        length = signature[index + 1]
        value = signature[index + 2:index + 2 + length].lstrip(b"\x00")
        parts.append(value.rjust(32, b"\x00"))
        index += 2 + length
    return b"".join(parts)


def token():
    header = {"alg": "ES256", "kid": os.environ["ASC_KEY_ID"], "typ": "JWT"}
    now = int(time.time())
    payload = {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"}
    signing_input = (b64url(json.dumps(header).encode()) + "." + b64url(json.dumps(payload).encode())).encode()
    der = subprocess.run(
        ["openssl", "dgst", "-sha256", "-sign", os.environ["ASC_KEY_PATH"]],
        input=signing_input, capture_output=True, check=True,
    ).stdout
    return signing_input.decode() + "." + b64url(der_to_raw(der))


def api(method, path, auth):
    request = urllib.request.Request(API + path, method=method, headers={"Authorization": "Bearer " + auth})
    with urllib.request.urlopen(request, timeout=30) as response:
        body = response.read()
        return json.loads(body) if body else None


def check():
    """Asks Apple for the account's certificates and profiles and prints how it answered."""
    import collections
    import urllib.error
    auth = token()
    for label, path in (
        ("certificates", "/certificates?limit=200&fields[certificates]=name,certificateType,expirationDate"),
        ("profiles", "/profiles?limit=200&fields[profiles]=profileType,profileState"),
        ("bundle IDs", "/bundleIds?limit=200&fields[bundleIds]=identifier"),
    ):
        try:
            data = api("GET", path, auth)["data"]
        except urllib.error.HTTPError as error:
            print("%s: HTTP %d" % (label, error.code))
            try:
                for item in json.loads(error.read()).get("errors", []):
                    print("  %s: %s: %s" % (item.get("code"), item.get("title"), item.get("detail")))
            except Exception:
                print("  (no readable error body)")
            continue
        except Exception as error:
            print("%s: %s" % (label, type(error).__name__))
            continue
        if label == "certificates":
            kinds = collections.Counter(item["attributes"].get("certificateType") for item in data)
            by_api = sum(1 for item in data if "Created via API" in (item["attributes"].get("name") or ""))
            print("certificates: %d (%s), %d of them created by CI runs" % (
                len(data), ", ".join("%s %d" % pair for pair in sorted(kinds.items())), by_api))
        elif label == "profiles":
            states = collections.Counter("%s/%s" % (item["attributes"].get("profileType"), item["attributes"].get("profileState")) for item in data)
            print("profiles: %d (%s)" % (len(data), ", ".join("%s %d" % pair for pair in sorted(states.items()))))
        else:
            theo = sorted(item["attributes"].get("identifier") for item in data if "theo" in (item["attributes"].get("identifier") or ""))
            print("bundle IDs: %d, Theo's: %s" % (len(data), ", ".join(theo)))


def revoke_new(snapshot_file):
    with open(snapshot_file) as handle:
        before = {line.strip() for line in handle if line.strip()}
    new = keychain_serials() - before
    if not new:
        print("No development certificate was created in this run.")
        return
    auth = token()
    certificates = api("GET", "/certificates?limit=200&fields[certificates]=serialNumber,name,certificateType", auth)["data"]
    for certificate in certificates:
        attributes = certificate["attributes"]
        if normalize(attributes.get("serialNumber", "")) in new:
            api("DELETE", "/certificates/" + certificate["id"], auth)
            print("Revoked this run's certificate: %s (%s)" % (attributes.get("name"), attributes.get("serialNumber")))
            new.discard(normalize(attributes["serialNumber"]))
    for serial in new:
        print("Not found on the account (nothing revoked): " + serial)


def main():
    if len(sys.argv) != 3 or sys.argv[1] not in ("snapshot", "revoke-new", "check"):
        sys.exit(__doc__)
    if sys.argv[1] == "check":
        check()
    elif sys.argv[1] == "snapshot":
        with open(sys.argv[2], "w") as handle:
            handle.write("\n".join(sorted(keychain_serials())) + "\n")
    else:
        revoke_new(sys.argv[2])


if __name__ == "__main__":
    main()
