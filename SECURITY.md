# Security Policy — Firewood Desktop

Firewood Desktop is an offline-first, zero-knowledge password and credential vault for desktop platforms.

---

## Supported Versions

Security fixes and patches are provided for the latest release:

| Version | Supported |
|---|---|
| `v1.x` (Latest) | ✅ Yes |
| `< v1.0` | ❌ No |

---

## Security Model & Guarantees

1. **Zero Knowledge**:
   - Master password derivation uses **Argon2id** (64 MiB RAM, 3 passes, 4 lanes).
   - Sensitive credential fields are sealed with **XChaCha20-Poly1305** using unique 24-byte CSPRNG nonces.
   - Master keys exist strictly in volatile RAM while the vault is unlocked and are never written to disk or swapped to disk files.
2. **Local Isolation**:
   - No cloud account systems, remote databases, or background tracking services exist in the binary.
3. **P2P AirShare Verification**:
   - Nearby peer sharing uses Bluetooth Low Energy with encrypted payloads, preventing network eavesdropping.

---

## Reporting a Vulnerability

If you discover a security vulnerability or cryptographic flaw in Firewood Desktop, please report it **responsibly and privately**.

### Contact Information
- **Email**: `security@firewood.local` (or via our [Web Contact Portal](https://firewoodsec.yahyaoncloud.com/contact/)).
- **Subject**: `[SECURITY VULNERABILITY] Firewood Desktop — <Brief Summary>`

Please provide:
- A clear description of the vulnerability.
- Steps to reproduce or proof-of-concept demonstration.
- Operating system, Flutter version, and affected release.
- Any suggested remediation or fix.

### Our Commitment
- We will acknowledge receipt within **48 hours**.
- We will provide an assessment and expected remediation timeline.
- We will notify you once a fix has been verified and released.
- We request that you maintain confidentiality until an official patch is published.
