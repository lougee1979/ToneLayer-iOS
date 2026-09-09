# Build Integrity & Transparency

*Companion to `privacy-safety-section.md`. That doc covers data-at-rest and in-transit protection (local PII scrubbing, on-device storage, zero-retention vendor terms). This doc covers a different threat: a legally compelled, targeted, secretly modified build pushed to one user — the Apple v. FBI / Lavabit scenario — and what ToneLayer can and cannot do about it.*

---

## The threat this addresses

Encryption and on-device storage protect against a passive request for *existing* data ("hand over what you have"). They do not protect against a targeted order compelling ToneLayer to ship a modified build to one specific user that captures their key or plaintext going forward — potentially under a gag order preventing disclosure to that user or the public. This is a different attack surface: the build pipeline, not the storage layer.

## What we can build

**1. Public build-hash transparency log.**
On every release, publish the SHA-256 hash of the shipped build artifact to a public, append-only log (a simple signed changelog page is sufficient to start — no blockchain needed). Anyone — a user, a journalist, a security researcher — can check whether a given installed build's hash matches what was publicly logged for that version number.

**2. In-app build verification screen.**
Settings → About shows the exact version, build number, and SHA-256 hash of the running binary, with a link explaining how to cross-check it against the public log.

**3. Warrant canary.**
A regularly-updated public statement (e.g. monthly) affirming ToneLayer has not received a National Security Letter, FISA order, or gag order compelling a modified build. Under a gag order the company cannot lie by continuing to affirm this — so the canary simply goes stale, which is itself the signal. Standard, established practice (EFF and others track these).

**4. App Attest / DeviceCheck integration.**
Apple's attestation API lets the ToneLayer server cryptographically verify that a request originated from a genuine, unmodified, Apple-signed build. This protects server-side logic and detects tampering at the network layer — it does not protect the user directly, but it closes a related gap.

## The hard ceiling — state this honestly in any privacy claim

iOS apps run only if Apple signs them. In the Apple v. FBI case, it was Apple itself being compelled to build and sign a special version — not the developer. If that ever happened to ToneLayer, Apple's own signature makes the modified build indistinguishable from a legitimate one to the OS, and nothing client-side (including the transparency log and verification screen above) can be trusted to detect it for that specific targeted device, since those very components could be part of what's silently swapped out.

**No engineering effort closes this gap for an iOS app.** It is a platform-level limitation, not a build-quality problem. Any public-facing privacy claim should say these protections cover passive data requests and network/server-level compulsion — not a fully Apple-cooperated targeted build.

## Implementation status

**Done, in `tonelayer-server`:**
- `transparency/canary.json` — the warrant canary statement, committed to git (not gitignored), served publicly at `GET /transparency/canary.json`
- `transparency/release-hashes.json` — the build-hash log, same pattern, served at `GET /transparency/release-hashes.json`
- `scripts/record-release-hash.mjs` — run manually after exporting an .ipa in Xcode: `node scripts/record-release-hash.mjs tonelayer <version> <build> <path-to-ipa>`, then commit + push the updated JSON. The git commit history is the actual audit trail; the server just serves the current state.
- The canary's `last_updated` field is updated by hand on a monthly cadence — there's no CI or scheduler for this yet, it's a manual recurring task.

**Not yet done:**
- In-app Settings → About screen showing build number + hash, with a link to the public log
- App Attest / DeviceCheck server-side verification

## Trade-offs, stated plainly

The transparency log and canary are low engineering cost (a static page, a CI step to publish hashes, a monthly manual affirmation) and add a genuine, verifiable trust signal. App Attest is a moderate integration cost on the server side. None of this should be marketed as "unbreakable" or "government-proof" — the honest claim is *detectable tampering* for most scenarios, with a stated, disclosed limit at the platform level.
