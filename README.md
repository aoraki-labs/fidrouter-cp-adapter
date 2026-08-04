# fidrouter-cp-adapter (open, Apache-2.0)

A tiny bridge between **your control plane** (a New API instance, or anything that issues
`sk-` keys) and a **fidrouter enclave**. It lets your users keep using the key they
already have, while every request is served in a verifiable, no-log TEE — **without your
control plane ever sitting in the data path** (if it relayed traffic it would see
plaintext and break the no-log guarantee).

```
user's sk-  ──POST /exchange──▶  cp-adapter  (this, bundled beside your New API)
     validate sk- against your New API's billing, derive a content-free tenant id,
     mint an Ed25519 CAPABILITY TOKEN signed by YOUR control-plane key
◀── { capability_token, enclave_url, expected_measurement, verify_url }

user app  ──E2EE prompt + capability token──▶  ENCLAVE (verifiable)  ──▶ provider
```

The end user never sees this service — the drop-in SDK calls it transparently. You run it;
you hold the signing key.

## Why it's open
So **any** relay operator can integrate a fidrouter enclave with their existing stack, and
audit exactly what the exchange does. It holds **no prompt data** and stores **no secret in
code** — the control-plane signing seed is injected via `CP_SEED_HEX` (its *public* half is
what your enclave image bakes in, so a wrong key just fails token verification).

## Deploy (bundle beside your New API)
1. Generate your control-plane Ed25519 keypair (keep the seed; its public half goes into
   your enclave's `config/public.json` → reproducible build → your `measurement`).
2. Copy `.env.example` → `.env`, fill in `CP_SEED_HEX`, `NEWAPI_BASE`, `ENCLAVE_URL`,
   `EXPECTED_MEASUREMENT`, `VERIFY_URL`, `MODELS`.
3. Run: `python3 adapter.py`  (stdlib + `cryptography`).
4. Point the drop-in SDK / your users at it; register your enclave endpoint on the
   fidrouter platform.

## Endpoint
`POST /exchange {"key":"sk-..."}` → `{capability_token, tenant, enclave_url,
expected_measurement, verify_url, models}` (401 if your New API rejects the key).
`GET /healthz`.

## Notes
- `tenant = "u_" + sha256(sk-)[:16]` — content-free, stable per key; lets metering attribute
  usage without the enclave or platform ever seeing the key.
- New API billing check is out-of-band (`GET /v1/dashboard/billing/subscription`); **no
  request is relayed through New API**.
- TLS to New API is currently unverified (`CERT_NONE` / `InsecureSkipVerify`) for the
  internal hop — no user content crosses it. Pin the cert where you can.

Part of **fidrouter** — a verifiable, no-log LLM relay. Core + verify SDK:
https://github.com/aoraki-labs/fidrouter
