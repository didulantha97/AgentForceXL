#!/usr/bin/env bash
# Local round trip for scripts/pms-licence.js: issue + extend with a throw-away key, verify both with openssl.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
node "$ROOT/scripts/pms-licence.js" keygen --out "$TMP/keys" >/dev/null
export PMS_LICENCE_PRIVATE_KEY="$TMP/keys/pms-licence-private.pem"
printf -- "-----BEGIN PUBLIC KEY-----\n%s\n-----END PUBLIC KEY-----\n" "$(cat "$TMP/keys/pms-licence-public.b64")" >"$TMP/pub.pem"
verify() {
  local t="$1"
  printf '%s' "${t%%.*}" >"$TMP/msg"
  printf '%s' "${t##*.}" | tr '_-' '/+' | awk '{while(length($0)%4)$0=$0"=";print}' | base64 -d >"$TMP/sig"
  openssl dgst -sha256 -verify "$TMP/pub.pem" -signature "$TMP/sig" "$TMP/msg"
}
ORG=00D5g000000TEST1AA
T1=$(node "$ROOT/scripts/pms-licence.js" issue --org $ORG --edition Standard --modules Hotel,Property --valid-until 2027-06-30 | grep -E '^ey')
T2=$(node "$ROOT/scripts/pms-licence.js" extend --org $ORG --until 2027-09-30 --reason "check" | grep -E '^ey')
verify "$T1"
verify "$T2"
# issuedAt is an ISO 8601 UTC datetime
for t in "$T1" "$T2"; do
  node -e 'const p=JSON.parse(Buffer.from(process.argv[1].split(".")[0],"base64url").toString());if(!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/.test(p.issuedAt))process.exit(1)' "$t" || { echo "issuedAt is not an ISO datetime" >&2; exit 1; }
done
# extend --until in the past is refused
if node "$ROOT/scripts/pms-licence.js" extend --org $ORG --until 2020-01-01 --reason x >/dev/null 2>&1; then echo "past --until was accepted" >&2; exit 1; fi
# rotation: a token signed by the old key needs --verify-key; the new token is signed by the new key
node "$ROOT/scripts/pms-licence.js" keygen --out "$TMP/keys2" >/dev/null
OLD_PRIV="$PMS_LICENCE_PRIVATE_KEY"
export PMS_LICENCE_PRIVATE_KEY="$TMP/keys2/pms-licence-private.pem"
if node "$ROOT/scripts/pms-licence.js" extend --org $ORG --until 2027-09-30 --reason rot --from-token "$T1" >/dev/null 2>&1; then echo "old token accepted without --verify-key" >&2; exit 1; fi
T3=$(node "$ROOT/scripts/pms-licence.js" extend --org $ORG --until 2027-09-30 --reason rot --from-token "$T1" --verify-key "$TMP/keys/pms-licence-public.b64" | grep -E '^ey')
printf -- "-----BEGIN PUBLIC KEY-----\n%s\n-----END PUBLIC KEY-----\n" "$(cat "$TMP/keys2/pms-licence-public.b64")" >"$TMP/pub2.pem"
cp "$TMP/pub2.pem" "$TMP/pub.pem"
verify "$T3"
# a group-readable private key only warns; the log stays 0600
chmod 644 "$TMP/keys2/pms-licence-private.pem"
node "$ROOT/scripts/pms-licence.js" issue --org $ORG --edition Standard --modules Hotel --valid-until 2027-06-30 2>&1 >/dev/null | grep -q "readable by group or others" || { echo "no key mode warning" >&2; exit 1; }
chmod 666 "$TMP/keys2/issuance-log.jsonl"
node "$ROOT/scripts/pms-licence.js" issue --org $ORG --edition Standard --modules Hotel --valid-until 2027-06-30 >/dev/null 2>&1
[[ "$(stat -f %Lp "$TMP/keys2/issuance-log.jsonl" 2>/dev/null || stat -c %a "$TMP/keys2/issuance-log.jsonl")" == "600" ]] || { echo "issuance log is not 0600" >&2; exit 1; }
export PMS_LICENCE_PRIVATE_KEY="$OLD_PRIV"
echo "licence round trip OK"
