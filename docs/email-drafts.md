# Email Drafts — Migration Guide Pack Outreach

Two versions for testing the Android Migration Guide Pack and sample app.

---

## Email 1 — Non-Technical Leaders (AI focus)

**To:** Business / product leaders, engineering managers
**Subject:** Using AI to accelerate Android app modernisation on Zebra devices

---

Hi [Name],

As enterprise Android moves to newer OS versions, apps built for older versions need to be updated to stay compatible. For many organisations this has been a slow, manual process.

We've put together a resource that lets development teams use the AI coding tools they already have — GitHub Copilot, Claude, Cursor, or ChatGPT — to automate the bulk of the migration work.

**What it is:**
A pack of guidance files that developers drop into their project. Once in place, the AI assistant understands the Zebra device context and can apply fixes phase by phase — updating deprecated APIs, fixing permission handling, modernising storage access, and more — with the developer reviewing and approving each change.

**Why it matters:**
- Apps targeting older Android versions will stop passing Google Play requirements and may lose access to Zebra's latest OS features
- Manual migration of a medium-sized app typically takes days to weeks; AI-assisted migration compresses this significantly
- The guidance is reusable — any app in your portfolio can benefit from the same pack

**What we'd like from you:**
We're testing this with a small group before broader release. If you have a development team working on Android app updates, we'd welcome the chance to walk through it with them and get your feedback on where it's most useful.

Happy to set up a 30-minute call if that's easier.

[Your name]
[Title], Zebra Technologies
[Contact]

---

## Email 2 — Developers

**To:** Android developers, mobile engineering teams
**Subject:** AI-assisted Android migration pack for Zebra devices — looking for testers

---

Hi [Name],

We've built an open-source pack to help developers migrate Zebra Android apps from API 30 to API 35 using AI coding assistants. We're looking for developers to try it on a real project (or the sample app we've included) and give us feedback before we publish it more widely.

**What's in the pack** ([github.com/cbolen/Android-Migration-Guide-Pack](https://github.com/cbolen/Android-Migration-Guide-Pack)):

- `CLAUDE.md` / `.cursorrules` — drop in your project root; Claude Code or Cursor loads it automatically and gains full Zebra + Android migration context
- `docs/migration-guide.md` — full A11→A15 reference covering every API change that affects Zebra apps, phase by phase
- `docs/datawedge-intents-ref.md` — DataWedge Intent API quick reference
- `examples/` — vetted Kotlin boilerplate for DataWedge, EMDK, permissions, storage, and edge-to-edge
- `docs/how-to-use.md` — 12 ready-to-paste prompts (one per migration phase) plus a `migrate.sh` script that runs Claude Code non-interactively through the full migration

**For GitHub Copilot users:** copy `CLAUDE.md` into `.github/copilot-instructions.md` — same context, picked up automatically.
**For AI chat users (ChatGPT, Gemini, Claude.ai):** paste `docs/system-prompt.md` as your first message.

**Practice app** ([github.com/cbolen/android-migration-sample](https://github.com/cbolen/android-migration-sample)):

If you'd rather not use a production codebase to test this, we built a realistic legacy inventory app targeting API 30 with 31 intentional migration issues spread across 13 files — AsyncTask, startActivityForResult, hardcoded /sdcard/ paths, missing android:exported, PendingIntent without FLAG_IMMUTABLE, and more. Clone it, run the migration guide against it, and check your results against the included MIGRATION-ISSUES.md checklist.

**What we're looking for:**
- Does the guide cover the issues you actually encounter?
- Are the AI prompts specific enough to produce clean, reviewable changes?
- What's missing for your specific app or device target?

Any feedback — GitHub issues, replies here, or a quick call — is appreciated. We want this to be genuinely useful before pushing it through TechDocs.

Thanks
[Your name]
[Title], Zebra Technologies
[Contact]