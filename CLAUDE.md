# ToneLayer — Project Memory

## DEV FOLDER RULE — FROZEN. NEVER CHANGE THIS.

The user has ADHD and relies on a color-coded system to stay oriented.
Keep things EXACTLY the way the user already knows them. Do not introduce
new folders, paths, or names.

The dev folders live in `~/ToneLayer` (the user's Home folder — NOT
Desktop/Documents, which iCloud syncs and corrupts git repos):

- **ORANGE folder: `~/ToneLayer/ToneLayer iOS` = ToneLayer** (this project)
- **RED folder: `~/ToneLayer/ToneLayer Clarity iOS` = Clarity**

These two color-coded folders are the ONLY dev folders. Always.

### NEVER do any of these:
- Never create a new project folder.
- Never move, rename, clone, or delete the user's folders.
- Never tell the user to use `~/Developer`, the Desktop, or any folder
  other than the orange and red folders in `~/ToneLayer`.
- Never introduce a new name or location for these projects.

### ALWAYS:
- Refer to "the orange folder" for ToneLayer and "the red folder" for Clarity.
- Keep everything consistent with what the user already has set up.
- Prefer the simplest possible instructions. One small step at a time.

The user has stated this repeatedly and clearly. Honor it without exception.

## SECURITY/PRIVACY RULE — FROZEN. ALWAYS DO THIS.

The user's text is private and sensitive. ToneLayer and Clarity rewrite
people's real messages — often emotional, personal, or high-stakes — and
sending that text to an AI service is the single biggest security/privacy
risk in this product.

ALWAYS, without being asked:
- Treat every user message as sensitive data. Minimize what leaves the
  device, never log or store raw message content on the server, and never
  send more than is needed to do the rewrite/decode.
- Before designing or changing ANY feature, ask "does this expose the
  user's private text?" — and if it does, say so plainly to the user in
  simple terms BEFORE building it, not after.
- Prefer the most private option available (on-device processing, no
  retention, encryption in transit and at rest) even when a less private
  option is easier.
- Never quietly add anything that sends, copies, logs, or stores the
  user's text somewhere new. Flag it first.
- Keep secrets (API keys, app tokens) OUT of the source code and out of
  git. They belong in environment variables / build config only.

Security of the user's words is a top priority, every time, by default.
