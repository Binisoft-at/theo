#!/usr/bin/env python3
"""Keeps automatic signing from piling up development certificates.

Each CI run starts on a fresh Mac, so `xcodebuild -allowProvisioningUpdates` creates a new
"Apple Development" certificate whose private key is gone when the runner is. This script
records the signing identities before archiving and, afterwards, revokes only the ones that run
created, through the App Store Connect API. Nothing else on the account is touched.

usage: ci-certificates.py snapshot <file>       record the identities in the keychain
       ci-certificates.py revoke-new <file>     revoke identities added since the snapshot
       ci-certificates.py create-identity <dir> creates this run's development certificate
                                                through the API and puts it, with its key, in a
                                                keychain of its own (revoke-new removes it later)
       ci-certificates.py check -               what Apple answers about the account's
                                                certificates and profiles (counts and Apple's
                                                error messages only, never names: the log is public)
env:   ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_PATH    (all but snapshot)

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


def create_identity(workdir):
    """Creates an Apple Development certificate through the API and makes it a signing identity.

    `xcodebuild -allowProvisioningUpdates` normally creates this certificate itself. Since
    19 November 2026 that step fails on GitHub's Macs ("The data couldn't be read because it
    isn't in the correct format") while the API itself creates certificates fine, so the run
    creates it here and Xcode finds it ready.
    """
    import secrets
    import urllib.error
    os.makedirs(workdir, exist_ok=True)
    key, csr = os.path.join(workdir, "ci-key.pem"), os.path.join(workdir, "ci.csr")
    der, pem, p12 = (os.path.join(workdir, name) for name in ("ci-cert.der", "ci-cert.pem", "ci.p12"))
    keychain = os.path.join(workdir, "theo-ci.keychain-db")
    password = secrets.token_hex(16)
    ssl = "/usr/bin/openssl"  # macOS's own: its PKCS#12 files are ones the keychain can read
    subprocess.run([ssl, "req", "-new", "-newkey", "rsa:2048", "-nodes", "-keyout", key, "-out", csr,
                    "-subj", "/CN=Theo CI/O=Theo CI"], check=True, capture_output=True)
    body = json.dumps({"data": {"type": "certificates", "attributes": {
        "certificateType": "DEVELOPMENT", "csrContent": open(csr).read()}}}).encode()
    request = urllib.request.Request(API + "/certificates", data=body, method="POST", headers={
        "Authorization": "Bearer " + token(), "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            created = json.loads(response.read())["data"]
    except urllib.error.HTTPError as error:
        print("Apple refused the certificate: HTTP %d" % error.code)
        try:
            for item in json.loads(error.read()).get("errors", []):
                print("  %s: %s: %s" % (item.get("code"), item.get("title"), item.get("detail")))
        except Exception:
            print("  (no readable error body)")
        sys.exit(1)
    with open(der, "wb") as handle:
        handle.write(base64.b64decode(created["attributes"]["certificateContent"]))
    subprocess.run([ssl, "x509", "-inform", "DER", "-in", der, "-out", pem], check=True, capture_output=True)
    subprocess.run([ssl, "pkcs12", "-export", "-inkey", key, "-in", pem, "-out", p12, "-passout", "pass:" + password],
                   check=True, capture_output=True)

    def security(*args):
        subprocess.run(["security", *args], check=True, capture_output=True)

    security("create-keychain", "-p", password, keychain)
    security("set-keychain-settings", "-lut", "21600", keychain)
    security("unlock-keychain", "-p", password, keychain)
    security("import", p12, "-k", keychain, "-P", password, "-T", "/usr/bin/codesign", "-T", "/usr/bin/security")
    security("set-key-partition-list", "-S", "apple-tool:,apple:,codesign:", "-s", "-k", password, keychain)
    # Apple's intermediate certificate, so the identity's chain is complete (skipped if offline).
    intermediate = os.path.join(workdir, "AppleWWDRCAG3.cer")
    try:
        with urllib.request.urlopen("https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer", timeout=30) as response:
            with open(intermediate, "wb") as handle:
                handle.write(response.read())
        subprocess.run(["security", "import", intermediate, "-k", keychain], capture_output=True)
    except Exception as error:
        print("Apple's intermediate certificate wasn't downloaded (%s)" % type(error).__name__)
    searched = subprocess.run(["security", "list-keychains", "-d", "user"], capture_output=True, text=True).stdout
    current = [line.strip().strip('"') for line in searched.splitlines() if line.strip()]
    security("list-keychains", "-d", "user", "-s", keychain, *[path for path in current if path != keychain])
    for path in (key, p12):
        os.remove(path)
    serial = created["attributes"].get("serialNumber", "?")
    print("Created this run's development certificate (%s); signing identities now:" % serial)
    print(subprocess.run(["security", "find-identity", "-v", "-p", "codesigning"], capture_output=True, text=True).stdout
          .replace(created["attributes"].get("name") or "\0", "<this run's certificate>"))


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
    # May the key create anything? A deliberately invalid request creates nothing: Apple answers
    # that the request is invalid when creating is allowed, and why not when it isn't (such as an
    # agreement waiting to be accepted).
    body = json.dumps({"data": {"type": "certificates", "attributes": {
        "certificateType": "DEVELOPMENT", "csrContent": "not-a-certificate-request"}}}).encode()
    request = urllib.request.Request(API + "/certificates", data=body, method="POST", headers={
        "Authorization": "Bearer " + auth, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            print("creating a certificate: HTTP %d (unexpected)" % response.status)
    except urllib.error.HTTPError as error:
        print("creating a certificate (invalid on purpose): HTTP %d" % error.code)
        try:
            for item in json.loads(error.read()).get("errors", []):
                print("  %s: %s: %s" % (item.get("code"), item.get("title"), item.get("detail")))
        except Exception:
            print("  (no readable error body)")
    except Exception as error:
        print("creating a certificate: %s" % type(error).__name__)


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
    if len(sys.argv) != 3 or sys.argv[1] not in ("snapshot", "revoke-new", "check", "create-identity"):
        sys.exit(__doc__)
    if sys.argv[1] == "check":
        check()
    elif sys.argv[1] == "create-identity":
        create_identity(sys.argv[2])
    elif sys.argv[1] == "snapshot":
        with open(sys.argv[2], "w") as handle:
            handle.write("\n".join(sorted(keychain_serials())) + "\n")
    else:
        revoke_new(sys.argv[2])


if __name__ == "__main__":
    main()
