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

## SECURITY/PRIVACY RULE — FROZEN. THE #1 PRIORITY, ABOVE ALL ELSE.

Protecting the user's security and privacy comes BEFORE features, speed,
convenience, or anything else. Be constantly vigilant. Treat every change
as a possible threat to security until proven otherwise, and PROACTIVELY
raise anything that could expose private data — without waiting to be asked.

The user's text is private and sensitive. ToneLayer and Clarity rewrite
people's real messages — often emotional, personal, or high-stakes — and
sending that text (or voice) to an AI service is the single biggest
security/privacy risk in this product. Users unknowingly putting all their
private business out where anyone could access it is UNACCEPTABLE and must
be prevented and flagged the moment it could happen.

ALWAYS, without being asked:
- Actively watch for and call out ANY path where the user's text or voice
  leaves the device or could be seen by a third party (server logs,
  analytics, Hume voice analysis, a full-access keyboard, etc.).
- Prefer designs that only touch the text the user EXPLICITLY selects or
  highlights, over anything with broad access to everything they type.
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

### SECURE vs FULL mode — the user always chooses.

Offer two modes and let the USER pick which one they want:
- **Secure mode:** everything happens on-device. Nothing leaves the phone —
  no server, no Claude, no Hume voice analysis. Authenticity comes from
  on-device learning of the user's own writing style.
- **Full mode:** off-device (server + Claude, plus voice-tone analysis) for
  maximum capability and voice-based authenticity. More capable, less private.

Rules for these modes:
- Default to the SECURE (private) option.
- ALWAYS show the user, on every rewrite, which mode actually ran — whether
  it stayed on the phone or was sent off the phone.
- NEVER silently move a user from secure to off-device. Going off-device is
  always a clear, deliberate, consented choice.
- Voice-tone (Hume) is inherently cloud-based, so it belongs only to Full
  mode and must never run in Secure mode.

### NO DIAGNOSTIC LABELS TO THE AI — FROZEN. NEVER SEND A DIAGNOSIS TO A MODEL.

AI disability bias becomes possible the moment a diagnostic term enters the
text an AI model reads. Models have absorbed the world's stereotypes about
"ADHD," "autistic," "PTSD," "CPTSD," etc. — the label invokes those priors and
can pathologize or distort the output. Describing the BEHAVIOR cannot do this;
the LABEL can. So the label must NEVER reach the model.

ALWAYS:
- Describe the behavior/pattern, never the diagnosis, in ANYTHING sent to an
  AI (prompts, system instructions, voice prompts, the server "profile"
  field, tool inputs). E.g. "reduce working-memory load; surface the buried
  ask" — never "ADHD: ...". "Lower threat signals; add reassurance" — never
  "PTSD: ...".
- Keep diagnostic terms, if used at all, ONLY in the user-facing UI as the
  user's own optional self-identification. The user selects who they are;
  that selection maps INTERNALLY to behavior instructions; the diagnostic
  word is stripped before anything is sent to a model.
- Before sending anything to an AI, scan it for diagnostic terms (ADHD,
  AUDHD, Autism/autistic, PTSD, CPTSD, etc.) and remove them, keeping the
  behavior.

NEVER put a diagnosis in a prompt, a system message, a profile string sent to
the server, or any other AI-facing text. This is a core anti-bias guarantee of
the product: "we never tell the AI your diagnosis."
