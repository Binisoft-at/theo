#!/usr/bin/env python3
"""App Store Connect helper used by the TestFlight workflow.

Commands
  prepare-signing  Ensure an Apple Distribution + Mac Installer certificate exist for the CI
                   signing key, create fresh App Store provisioning profiles for iOS and macOS,
                   and install everything into a keychain on the build machine.
  beta-setup       Ensure an internal TestFlight group exists that receives every build and
                   contains all team members.
  status           Print the app record, bundle ID capabilities and latest builds.

Environment
  ASC_KEY_ID, ASC_ISSUER_ID, ASC_PRIVATE_KEY   App Store Connect API key (Admin role)
  SIGNING_KEY_PEM (optional)                   RSA key for the signing certificates. If absent,
                                               the key is kept AES-encrypted in ci/signing-key.enc,
                                               keyed by ASC_PRIVATE_KEY.
"""
import argparse
import base64
import hashlib
import json
import os
import plistlib
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import jwt  # PyJWT
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.serialization import pkcs12
from cryptography.x509.oid import NameOID

API = "https://api.appstoreconnect.apple.com"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
KEY_FILE = os.path.join(ROOT, "ci", "signing-key.enc")
WWDR_URLS = [
    "https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer",
    "https://www.apple.com/certificateauthority/AppleWWDRCAG4.cer",
]


def log(*args):
    print(*args, file=sys.stderr, flush=True)


# ---------------------------------------------------------------------------
# API client
# ---------------------------------------------------------------------------

class ASC:
    def __init__(self):
        self.key_id = os.environ["ASC_KEY_ID"].strip()
        self.issuer = os.environ["ASC_ISSUER_ID"].strip()
        self.private_key = normalize_p8(os.environ["ASC_PRIVATE_KEY"])
        self._token = None
        self._token_time = 0

    def token(self):
        if not self._token or time.time() - self._token_time > 600:
            now = int(time.time())
            self._token = jwt.encode(
                {"iss": self.issuer, "iat": now, "exp": now + 1100, "aud": "appstoreconnect-v1"},
                self.private_key,
                algorithm="ES256",
                headers={"kid": self.key_id, "typ": "JWT"},
            )
            self._token_time = now
        return self._token

    def request(self, method, path, body=None, params=None, ok_missing=False):
        url = API + path
        if params:
            url += "?" + urllib.parse.urlencode(params)
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(url, data=data, method=method)
        req.add_header("Authorization", "Bearer " + self.token())
        req.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                raw = resp.read()
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as err:
            text = err.read().decode(errors="replace")
            if ok_missing and err.code == 404:
                return None
            raise RuntimeError(f"{method} {path} -> HTTP {err.code}: {text}") from None

    def get_all(self, path, params=None):
        params = dict(params or {})
        params.setdefault("limit", "200")
        result = self.request("GET", path, params=params)
        items = list(result.get("data", []))
        included = list(result.get("included", []))
        nxt = result.get("links", {}).get("next")
        while nxt:
            req_path = nxt.replace(API, "")
            result = self.request("GET", req_path)
            items += result.get("data", [])
            included += result.get("included", [])
            nxt = result.get("links", {}).get("next")
        return items, included


def normalize_p8(text):
    text = text.strip().replace("\\n", "\n")
    if "BEGIN PRIVATE KEY" not in text:
        body = "".join(text.split())
        lines = [body[i:i + 64] for i in range(0, len(body), 64)]
        text = "-----BEGIN PRIVATE KEY-----\n" + "\n".join(lines) + "\n-----END PRIVATE KEY-----"
    return text + "\n"


# ---------------------------------------------------------------------------
# Signing key storage
# ---------------------------------------------------------------------------

def _aes_key():
    material = normalize_p8(os.environ["ASC_PRIVATE_KEY"]).encode() + b"|theo-signing-v1"
    return hashlib.sha256(material).digest()


def load_or_create_signing_key():
    """Returns (key, created). Prefers SIGNING_KEY_PEM, then the encrypted key file."""
    pem = os.environ.get("SIGNING_KEY_PEM", "").strip()
    if pem:
        return serialization.load_pem_private_key(pem.replace("\\n", "\n").encode(), password=None), False
    if os.path.exists(KEY_FILE):
        blob = base64.b64decode(open(KEY_FILE).read().strip())
        try:
            raw = AESGCM(_aes_key()).decrypt(blob[:12], blob[12:], b"theo")
            return serialization.load_pem_private_key(raw, password=None), False
        except Exception:
            log("warning: could not decrypt ci/signing-key.enc (API key changed?) - creating a new signing key")
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    raw = key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption())
    nonce = os.urandom(12)
    blob = nonce + AESGCM(_aes_key()).encrypt(nonce, raw, b"theo")
    os.makedirs(os.path.dirname(KEY_FILE), exist_ok=True)
    with open(KEY_FILE, "w") as f:
        f.write(base64.b64encode(blob).decode() + "\n")
    return key, True


def make_csr(key):
    subject = x509.Name([
        x509.NameAttribute(NameOID.COMMON_NAME, "Theo CI"),
        x509.NameAttribute(NameOID.EMAIL_ADDRESS, "ci@theo.invalid"),
        x509.NameAttribute(NameOID.COUNTRY_NAME, "US"),
    ])
    csr = x509.CertificateSigningRequestBuilder().subject_name(subject).sign(key, hashes.SHA256())
    return csr.public_bytes(serialization.Encoding.PEM).decode()


def same_key(cert, key):
    return cert.public_key().public_numbers() == key.public_key().public_numbers()


def ensure_certificate(api, key, cert_type):
    certs, _ = api.get_all("/v1/certificates", {"filter[certificateType]": cert_type})
    now = time.strftime("%Y-%m-%dT%H:%M:%S")
    for item in certs:
        content = item["attributes"].get("certificateContent")
        expires = item["attributes"].get("expirationDate", "")
        if not content or (expires and expires[:19] < now):
            continue
        cert = x509.load_der_x509_certificate(base64.b64decode(content))
        if same_key(cert, key):
            log(f"using existing {cert_type} certificate {item['id']}")
            return item["id"], cert
    log(f"creating {cert_type} certificate")
    try:
        created = api.request("POST", "/v1/certificates", {
            "data": {"type": "certificates", "attributes": {"certificateType": cert_type, "csrContent": make_csr(key)}}
        })
    except RuntimeError as err:
        if "limit" in str(err).lower() or "maximum" in str(err).lower():
            raise RuntimeError(
                f"Apple refused to create another {cert_type} certificate because the account is at its limit. "
                "Revoke an unused one at developer.apple.com > Certificates, then re-run.\n" + str(err))
        raise
    data = created["data"]
    cert = x509.load_der_x509_certificate(base64.b64decode(data["attributes"]["certificateContent"]))
    return data["id"], cert


def team_id_from_cert(cert):
    for attr in cert.subject:
        if attr.oid == NameOID.ORGANIZATIONAL_UNIT_NAME:
            return attr.value
    return None


def find_bundle_id(api, identifier):
    items, included = api.get_all("/v1/bundleIds", {"filter[identifier]": identifier, "include": "bundleIdCapabilities"})
    for item in items:
        if item["attributes"]["identifier"] == identifier:
            caps = [inc["attributes"].get("capabilityType") for inc in included if inc["type"] == "bundleIdCapabilities"
                    and inc["id"].startswith(item["id"])]
            return item, caps
    raise RuntimeError(f"Bundle ID {identifier} is not registered. Register it at developer.apple.com > Identifiers.")


def ensure_capabilities(api, bundle, caps):
    wanted = {
        "ICLOUD": [{"key": "ICLOUD_VERSION", "options": [{"key": "XCODE_6"}]}],
        "PUSH_NOTIFICATIONS": None,
    }
    for cap, settings in wanted.items():
        if cap in caps:
            continue
        log(f"enabling capability {cap}")
        attrs = {"capabilityType": cap}
        if settings:
            attrs["settings"] = settings
        try:
            api.request("POST", "/v1/bundleIdCapabilities", {
                "data": {"type": "bundleIdCapabilities", "attributes": attrs,
                         "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": bundle["id"]}}}}
            })
        except RuntimeError as err:
            log(f"warning: could not enable {cap}: {err}")


def create_profile(api, name, profile_type, bundle_id, cert_id):
    existing, _ = api.get_all("/v1/profiles", {"filter[name]": name})
    for item in existing:
        if item["attributes"]["name"] == name:
            log(f"deleting old profile {name}")
            api.request("DELETE", f"/v1/profiles/{item['id']}")
    created = api.request("POST", "/v1/profiles", {
        "data": {
            "type": "profiles",
            "attributes": {"name": name, "profileType": profile_type},
            "relationships": {
                "bundleId": {"data": {"type": "bundleIds", "id": bundle_id}},
                "certificates": {"data": [{"type": "certificates", "id": cert_id}]},
            },
        }
    })
    attrs = created["data"]["attributes"]
    return attrs["uuid"], base64.b64decode(attrs["profileContent"])


def profile_entitlements(content):
    """Decodes the plist embedded in a CMS-signed provisioning profile."""
    start = content.find(b"<?xml")
    end = content.find(b"</plist>") + len(b"</plist>")
    return plistlib.loads(content[start:end])


def run(cmd, check=True):
    log("$ " + " ".join(cmd))
    return subprocess.run(cmd, check=check)


def install_keychain(keychain, password, key, dist_cert, installer_cert, workdir):
    p12_path = os.path.join(workdir, "dist.p12")
    enc = (serialization.PrivateFormat.PKCS12.encryption_builder()
           .kdf_rounds(50000)
           .key_cert_algorithm(pkcs12.PBES.PBESv1SHA1And3KeyTripleDESCBC)
           .hmac_hash(hashes.SHA1())
           .build(password.encode()))
    with open(p12_path, "wb") as f:
        f.write(pkcs12.serialize_key_and_certificates(b"Theo CI", key, dist_cert, None, enc))
    installer_path = os.path.join(workdir, "installer.cer")
    with open(installer_path, "wb") as f:
        f.write(installer_cert.public_bytes(serialization.Encoding.DER))

    run(["security", "delete-keychain", keychain], check=False)
    run(["security", "create-keychain", "-p", password, keychain])
    run(["security", "set-keychain-settings", "-lut", "21600", keychain])
    run(["security", "unlock-keychain", "-p", password, keychain])
    run(["security", "import", p12_path, "-k", keychain, "-P", password, "-T", "/usr/bin/codesign",
         "-T", "/usr/bin/productbuild", "-T", "/usr/bin/security", "-A"])
    run(["security", "import", installer_path, "-k", keychain, "-T", "/usr/bin/productbuild", "-A"], check=False)
    for url in WWDR_URLS:
        path = os.path.join(workdir, os.path.basename(url))
        try:
            urllib.request.urlretrieve(url, path)
            run(["security", "import", path, "-k", keychain], check=False)
        except Exception as err:  # noqa: BLE001
            log(f"warning: could not fetch {url}: {err}")
    run(["security", "set-key-partition-list", "-S", "apple-tool:,apple:,codesign:,productbuild:", "-s", "-k", password, keychain])
    existing = subprocess.run(["security", "list-keychains", "-d", "user"], capture_output=True, text=True).stdout
    paths = [p.strip().strip('"') for p in existing.split() if p.strip()]
    run(["security", "list-keychains", "-d", "user", "-s", keychain] + [p for p in paths if p != keychain])
    run(["security", "find-identity", "-v", "-p", "codesigning", keychain], check=False)
    os.remove(p12_path)


def install_profile(uuid, content):
    for folder in ["~/Library/MobileDevice/Provisioning Profiles", "~/Library/Developer/Xcode/UserData/Provisioning Profiles"]:
        path = os.path.expanduser(folder)
        os.makedirs(path, exist_ok=True)
        ext = "mobileprovision"
        with open(os.path.join(path, f"{uuid}.{ext}"), "wb") as f:
            f.write(content)
        with open(os.path.join(path, f"{uuid}.provisionprofile"), "wb") as f:
            f.write(content)


# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

def cmd_prepare_signing(args):
    api = ASC()
    key, created = load_or_create_signing_key()
    dist_id, dist_cert = ensure_certificate(api, key, "DISTRIBUTION")
    inst_id, inst_cert = ensure_certificate(api, key, "MAC_INSTALLER_DISTRIBUTION")
    team = os.environ.get("APPLE_TEAM_ID", "").strip() or team_id_from_cert(dist_cert)
    bundle, caps = find_bundle_id(api, args.bundle_id)
    log(f"bundle id {bundle['id']} platform={bundle['attributes'].get('platform')} capabilities={caps}")
    ensure_capabilities(api, bundle, caps)

    ios_name = f"Theo CI iOS App Store"
    mac_name = f"Theo CI macOS App Store"
    ios_uuid, ios_content = create_profile(api, ios_name, "IOS_APP_STORE", bundle["id"], dist_id)
    mac_uuid, mac_content = create_profile(api, mac_name, "MAC_APP_STORE", bundle["id"], dist_id)
    cloudkit_ready = True
    for label, content in [("iOS", ios_content), ("macOS", mac_content)]:
        ents = profile_entitlements(content).get("Entitlements", {})
        log(f"{label} profile entitlements: " + json.dumps({k: v for k, v in ents.items()
                                                           if "icloud" in k or "aps" in k}, default=str))
        containers = ents.get("com.apple.developer.icloud-container-identifiers") or []
        if args.container not in containers:
            cloudkit_ready = False
    if not cloudkit_ready:
        log(f"warning: {args.container} is not attached to the App ID yet; building without iCloud sync. "
            "Attach it at developer.apple.com > Identifiers > App ID > iCloud > Edit.")

    os.makedirs(args.workdir, exist_ok=True)
    install_keychain(args.keychain, args.keychain_password, key, dist_cert, inst_cert, args.workdir)
    install_profile(ios_uuid, ios_content)
    install_profile(mac_uuid, mac_content)

    out = {
        "team_id": team,
        "ios_profile_name": ios_name,
        "ios_profile_uuid": ios_uuid,
        "mac_profile_name": mac_name,
        "mac_profile_uuid": mac_uuid,
        "signing_key_created": created,
        "cloudkit_ready": cloudkit_ready,
    }
    print(json.dumps(out))
    if args.github_env:
        with open(args.github_env, "a") as f:
            f.write(f"TEAM_ID={team}\nIOS_PROFILE={ios_name}\nMAC_PROFILE={mac_name}\n")
            f.write(f"SIGNING_KEY_CREATED={'true' if created else 'false'}\n")
            f.write(f"CLOUDKIT_READY={'true' if cloudkit_ready else 'false'}\n")


def find_app(api, bundle_id):
    apps, _ = api.get_all("/v1/apps", {"filter[bundleId]": bundle_id})
    for app in apps:
        if app["attributes"]["bundleId"] == bundle_id:
            return app
    raise RuntimeError(f"No App Store Connect app with bundle ID {bundle_id}. Create it under Apps > New App.")


def cmd_beta_setup(args):
    api = ASC()
    app = find_app(api, args.bundle_id)
    groups, _ = api.get_all(f"/v1/apps/{app['id']}/betaGroups")
    group = next((g for g in groups if g["attributes"].get("isInternalGroup")), None)
    if group is None:
        log("creating internal TestFlight group 'Theo Team'")
        group = api.request("POST", "/v1/betaGroups", {
            "data": {
                "type": "betaGroups",
                "attributes": {"name": "Theo Team", "isInternalGroup": True, "hasAccessToAllBuilds": True},
                "relationships": {"app": {"data": {"type": "apps", "id": app["id"]}}},
            }
        })["data"]
    else:
        log(f"internal group: {group['attributes'].get('name')}")
        if not group["attributes"].get("hasAccessToAllBuilds"):
            try:
                api.request("PATCH", f"/v1/betaGroups/{group['id']}", {
                    "data": {"type": "betaGroups", "id": group["id"], "attributes": {"hasAccessToAllBuilds": True}}
                })
            except RuntimeError as err:
                log(f"warning: {err}")
    testers, _ = api.get_all(f"/v1/betaGroups/{group['id']}/betaTesters")
    emails = {t["attributes"].get("email", "").lower() for t in testers}
    # Only the explicitly listed people are added - never the whole team.
    wanted = {e.strip().lower() for e in os.environ.get("TESTFLIGHT_TESTERS", "").split(",") if e.strip()}
    users, _ = api.get_all("/v1/users")
    for user in users:
        attrs = user["attributes"]
        email = (attrs.get("username") or "").lower()
        if not email or email in emails or email not in wanted:
            continue
        log(f"adding {email} to the internal group")
        try:
            api.request("POST", "/v1/betaTesters", {
                "data": {
                    "type": "betaTesters",
                    "attributes": {"email": email, "firstName": attrs.get("firstName", ""), "lastName": attrs.get("lastName", "")},
                    "relationships": {"betaGroups": {"data": [{"type": "betaGroups", "id": group["id"]}]}},
                }
            })
        except RuntimeError as err:
            log(f"warning: could not add {email}: {err}")
    print(json.dumps({"app_id": app["id"], "group_id": group["id"]}))


def cmd_beta_prune(args):
    """Removes everyone except --keep from the app's internal TestFlight group(s)."""
    api = ASC()
    keep = {e.strip().lower() for e in args.keep.split(",") if e.strip()}
    app = find_app(api, args.bundle_id)
    groups, _ = api.get_all(f"/v1/apps/{app['id']}/betaGroups")
    for group in groups:
        if not group["attributes"].get("isInternalGroup"):
            continue
        testers, _ = api.get_all(f"/v1/betaGroups/{group['id']}/betaTesters")
        remove = [t for t in testers if t["attributes"].get("email", "").lower() not in keep]
        log(f"group {group['attributes'].get('name')}: {len(testers)} testers, removing {len(remove)}")
        for chunk in [remove[i:i + 50] for i in range(0, len(remove), 50)]:
            api.request("DELETE", f"/v1/betaGroups/{group['id']}/relationships/betaTesters",
                        {"data": [{"type": "betaTesters", "id": t["id"]} for t in chunk]})
        left, _ = api.get_all(f"/v1/betaGroups/{group['id']}/betaTesters")
        log("remaining: " + ", ".join(t["attributes"].get("email", "?") for t in left))


def cmd_status(args):
    api = ASC()
    try:
        app = find_app(api, args.bundle_id)
        print("app:", app["id"], app["attributes"].get("name"), app["attributes"].get("sku"))
        builds, _ = api.get_all("/v1/builds", {"filter[app]": app["id"], "sort": "-uploadedDate", "limit": "10"})
        for b in builds[:10]:
            a = b["attributes"]
            print("build:", a.get("version"), a.get("processingState"), a.get("uploadedDate"), a.get("expired"))
    except RuntimeError as err:
        print("app:", err)
    bundle, caps = find_bundle_id(api, args.bundle_id)
    print("bundle:", bundle["id"], bundle["attributes"].get("platform"), caps)


def main():
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("prepare-signing")
    p.add_argument("--bundle-id", required=True)
    p.add_argument("--keychain", required=True)
    p.add_argument("--container", default="iCloud.com.erblinkastrati.theo")
    p.add_argument("--keychain-password", required=True)
    p.add_argument("--workdir", default="/tmp/theo-signing")
    p.add_argument("--github-env", default=os.environ.get("GITHUB_ENV"))
    p.set_defaults(func=cmd_prepare_signing)
    b = sub.add_parser("beta-setup")
    b.add_argument("--bundle-id", required=True)
    b.set_defaults(func=cmd_beta_setup)
    pr = sub.add_parser("beta-prune")
    pr.add_argument("--bundle-id", required=True)
    pr.add_argument("--keep", required=True)
    pr.set_defaults(func=cmd_beta_prune)
    s = sub.add_parser("status")
    s.add_argument("--bundle-id", required=True)
    s.set_defaults(func=cmd_status)
    args = parser.parse_args()
    try:
        args.func(args)
    except RuntimeError as err:
        log(f"error: {err}")
        sys.exit(1)


if __name__ == "__main__":
    main()
