import { generateKeyPairSync } from "node:crypto";
import { existsSync, writeFileSync } from "node:fs";
import path from "node:path";

const CHARSET = "qpzry9x8gf2tvdw0s3jn54khce6mua7l";
const polymod = (values) => {
  const gen = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3];
  let chk = 1;
  for (const v of values) {
    const top = chk >>> 25;
    chk = ((chk & 0x1ffffff) << 5) ^ v;
    for (let i = 0; i < 5; i++) if ((top >>> i) & 1) chk ^= gen[i];
  }
  return chk;
};
const bech32 = (hrp, bytes) => {
  const data = [];
  let acc = 0, bits = 0;
  for (const b of bytes) {
    acc = (acc << 8) | b; bits += 8;
    while (bits >= 5) { bits -= 5; data.push((acc >>> bits) & 31); }
  }
  if (bits) data.push((acc << (5 - bits)) & 31);
  const expand = [...hrp].map((c) => c.charCodeAt(0) >> 5).concat(0, [...hrp].map((c) => c.charCodeAt(0) & 31));
  const mod = polymod(expand.concat(data, [0, 0, 0, 0, 0, 0])) ^ 1;
  const checksum = [0, 1, 2, 3, 4, 5].map((i) => (mod >>> (5 * (5 - i))) & 31);
  return hrp + "1" + data.concat(checksum).map((d) => CHARSET[d]).join("");
};

const dir = process.argv[2];
for (const name of process.argv.slice(3)) {
  if (existsSync(path.join(dir, `${name}.key`))) continue;
  const { privateKey } = generateKeyPairSync("ec", { namedCurve: "secp256k1" });
  const jwk = privateKey.export({ format: "jwk" });
  const sk = Buffer.from(jwk.d, "base64url");
  const pk = Buffer.from(jwk.x, "base64url");
  writeFileSync(path.join(dir, `${name}.key`), sk.toString("hex"), { mode: 0o600 });
  writeFileSync(path.join(dir, `${name}.nsec`), bech32("nsec", sk), { mode: 0o600 });
  writeFileSync(path.join(dir, `${name}.pub`), pk.toString("hex"), { mode: 0o600 });
}
