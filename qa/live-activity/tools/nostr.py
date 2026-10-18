import base64
import hashlib
import json
import os
import secrets
import ssl
import sys
import time
import urllib.error
import urllib.request
import uuid

P = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F
N = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141
G = (
    0x79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798,
    0x483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8,
)


def add(a, b):
    if a is None:
        return b
    if b is None:
        return a
    if a[0] == b[0] and a[1] != b[1]:
        return None
    if a == b:
        lam = 3 * a[0] * a[0] * pow(2 * a[1], -1, P) % P
    else:
        lam = (b[1] - a[1]) * pow(b[0] - a[0], -1, P) % P
    x = (lam * lam - a[0] - b[0]) % P
    return x, (lam * (a[0] - x) - a[1]) % P


def mul(point, k):
    result = None
    while k:
        if k & 1:
            result = add(result, point)
        point = add(point, point)
        k >>= 1
    return result


def tagged(tag, data):
    digest = hashlib.sha256(tag.encode()).digest()
    return hashlib.sha256(digest + digest + data).digest()


def num(data):
    return int.from_bytes(data, "big")


def raw(value):
    return value.to_bytes(32, "big")


def pubkey(secret):
    return raw(mul(G, num(secret))[0]).hex()


def schnorr(message, secret):
    d0 = num(secret)
    point = mul(G, d0)
    d = d0 if point[1] % 2 == 0 else N - d0
    t = bytes(a ^ b for a, b in zip(raw(d), tagged("BIP0340/aux", secrets.token_bytes(32))))
    k0 = num(tagged("BIP0340/nonce", t + raw(point[0]) + message)) % N
    r = mul(G, k0)
    k = k0 if r[1] % 2 == 0 else N - k0
    e = num(tagged("BIP0340/challenge", raw(r[0]) + raw(point[0]) + message)) % N
    return (raw(r[0]) + raw((k + e * d) % N)).hex()


def sign(secret, kind, tags, content):
    created = int(time.time())
    author = pubkey(secret)
    serial = json.dumps([0, author, created, kind, tags, content], separators=(",", ":"), ensure_ascii=False)
    event_id = hashlib.sha256(serial.encode()).digest()
    return {
        "id": event_id.hex(),
        "pubkey": author,
        "created_at": created,
        "kind": kind,
        "tags": tags,
        "content": content,
        "sig": schnorr(event_id, secret),
    }


def request(secret, path, body):
    url = os.environ["QA_RELAY_HTTPS"] + path
    data = json.dumps(body, separators=(",", ":"), ensure_ascii=False).encode()
    auth = sign(
        secret,
        27235,
        [["u", url], ["method", "POST"], ["nonce", str(uuid.uuid4())], ["payload", hashlib.sha256(data).hexdigest()]],
        "",
    )
    req = urllib.request.Request(
        url,
        data=data,
        method="POST",
        headers={
            "content-type": "application/json",
            "authorization": "Nostr " + base64.b64encode(json.dumps(auth).encode()).decode(),
        },
    )
    context = ssl.create_default_context(cafile=os.environ["QA_CA"])
    try:
        with urllib.request.urlopen(req, context=context, timeout=15) as response:
            return json.loads(response.read() or b"null")
    except urllib.error.HTTPError as error:
        sys.exit(f"{path} {error.code}: {error.read()[:300].decode(errors='replace')}")


def main():
    command, key_file = sys.argv[1], sys.argv[2]
    with open(key_file) as handle:
        secret = bytes.fromhex(handle.read().strip())
    if command == "event":
        event = sign(secret, int(sys.argv[3]), json.loads(sys.argv[4]), sys.argv[5] if len(sys.argv) > 5 else "")
        result = request(secret, "/events", event)
        if not result or not result.get("accepted"):
            sys.exit(f"rejected: {result}")
        print(json.dumps({"id": event["id"], "message": result.get("message", "")}))
    elif command == "query":
        print(json.dumps(request(secret, "/query", json.loads(sys.argv[3]))))
    else:
        sys.exit(f"unknown command {command}")


if __name__ == "__main__":
    main()
