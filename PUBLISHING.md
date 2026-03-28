# Publishing the Zebra Android Migration Guide Pack

Instructions for the Zebra team on how to publish and maintain this AI developer pack.

---

## Recommended Distribution Channels

| Channel | Audience | Effort | Reach |
|---|---|---|---|
| GitHub repository | All developers | Low | High |
| Zebra TechDocs page | Zebra ecosystem developers | Medium | High |
| Claude.ai Project | Developers using Claude | Low | Medium |
| Developer newsletter / blog post | Awareness | Low | Medium |

Use GitHub as the source of truth. All other channels link to it.

---

## 1. GitHub Repository

### Recommended Setup

- **Organization**: `zebra-oss` (or your existing public org)
- **Repo name**: `android-migration-guide`
- **Visibility**: Public
- **License**: Apache 2.0 (recommended for developer tooling)

### Initial publish steps

```bash
git init
git add .
git commit -m "Initial release: Android 11–15 migration guide pack for Zebra devices"
git remote add origin https://github.com/zebra-oss/android-migration-guide.git
git push -u origin main
```

### Recommended repo structure (matches this pack)

```
android-migration-guide/
├── README.md                        # How to use the pack (existing file)
├── CLAUDE.md                        # Auto-loaded by Claude Code
├── .cursorrules                     # Auto-loaded by Cursor
├── PUBLISHING.md                    # This file (internal — consider moving to docs/internal/)
├── docs/
│   ├── migration-guide.md           # Master migration guide
│   ├── system-prompt.md             # Paste-in context for AI chat tools
│   └── datawedge-intents-ref.md     # DataWedge API quick reference
└── examples/
    ├── datawedge-receiver.kt
    ├── datawedge-api-commands.kt
    ├── emdk-scanner-basic.kt
    ├── permissions-compat.kt
    ├── storage-patterns.kt
    └── edge-to-edge-insets.kt
```

### GitHub Copilot instructions file

Add `.github/copilot-instructions.md` to the repo. Copy the content of `CLAUDE.md` into it verbatim — GitHub Copilot auto-loads this file from the `.github/` folder. This gives Copilot users the same context automatically when they clone the repo.

```bash
mkdir .github
cp CLAUDE.md .github/copilot-instructions.md
```

### Releases and versioning

Tag a release whenever a major Android version or Zebra device guidance is added:

```bash
git tag -a v1.0 -m "Initial release — Android 11 to 15 migration"
git push origin v1.0
```

Suggested version naming: `v<year>.<month>` (e.g. `v2025.06`) or `v<major>.<minor>` tracking Android target SDK (e.g. `v35.1`).

---

## 2. Zebra TechDocs Page

### Suggested URL path

`https://techdocs.zebra.com/ai/android-migration/`

### Suggested page outline

```
Title: Android 11–15 Migration Guide for Zebra Devices — AI Developer Pack

Summary paragraph (2–3 sentences):
  This pack helps developers migrate Zebra enterprise Android apps to modern
  Android API levels using AI coding assistants (Claude Code, Cursor, GitHub
  Copilot, ChatGPT, Gemini). It covers standard Android API changes as the
  primary migration path, with Zebra-specific guidance for DataWedge, EMDK,
  and device-specific behavior layered on top.

Quick Start (link to README.md or embed the quick-start table):
  - Claude Code users → copy CLAUDE.md to your project root
  - Cursor users → copy .cursorrules to your project root
  - GitHub Copilot users → add to .github/copilot-instructions.md
  - AI chat users (Claude.ai, ChatGPT, Gemini) → paste system-prompt.md

Download / Source:
  [GitHub: zebra-oss/android-migration-guide] (link)

Contents:
  - Migration guide (A11→A15 with Zebra-specific phases)
  - DataWedge Intent API reference
  - Code examples (DataWedge, EMDK, permissions, storage, edge-to-edge)

Supported devices:
  - All Zebra Android enterprise devices (TC, MC, EC, ET series)
  - WS50 / WS501 square display — additional appendix included

Feedback / Issues:
  File an issue on GitHub or contact developer-relations@zebra.com
```

---

## 3. Claude.ai Project (Optional — Zero Friction Access)

Claude.ai Projects allow you to upload files that are automatically loaded into every conversation. This is the fastest path to get external developers working with the guide — no file management required.

### Setup steps

1. Log in to [claude.ai](https://claude.ai) with a team or business account
2. Create a new Project: **"Zebra Android Migration Guide"**
3. Upload the following files to the Project's knowledge base:
   - `docs/migration-guide.md`
   - `docs/system-prompt.md`
   - `docs/datawedge-intents-ref.md`
4. Set a Project instruction (paste into the project system prompt field):

```
You are helping Android developers migrate Zebra enterprise apps to Android 15.
Use the migration guide and DataWedge reference in this project as your primary
source of truth. Always prioritize standard Android API migrations; add
Zebra-specific guidance where relevant.
```

5. Share the Project link with external developers. Anyone with the link can use it without setting up Claude Code or any local files.

> **Note**: Claude.ai Projects require a paid plan. Check current plan limits for file size and number of uploads.

---

## 4. Developer Newsletter / Blog Post

A short announcement post increases awareness. Suggested outline:

**Title**: New AI Developer Pack: Migrate Your Zebra App to Android 15

**Body**:
- Why this pack exists (standard A11→A15 migration is the majority of work; Zebra-specific changes layer on top)
- What's in the pack (migration guide, DataWedge reference, code examples, AI assistant config files)
- How to use it with each AI tool (one-sentence per tool, link to README)
- Link to GitHub repo and TechDocs page
- Call to action: try it, file issues, send feedback

---

## 5. Maintenance Guide

### When to update

| Trigger | Files to update | Notes |
|---|---|---|
| New Android version announced (preview) | `migration-guide.md` | Add new phase/section for upcoming API level |
| New Android version released | `migration-guide.md`, `CLAUDE.md`, `.cursorrules`, `system-prompt.md` | Update targetSdk, minSdk guidance, new API requirements |
| New Zebra device with unique behavior | `migration-guide.md` (Appendix) | Add device-specific section like WS50/WS501 |
| DataWedge major version release | `datawedge-intents-ref.md`, examples | Update intent extras, new API commands |
| EMDK major version release | `examples/emdk-scanner-basic.kt` | Update initialization pattern if changed |
| Deprecated API actually removed | `migration-guide.md` | Verify against Android API reference; update urgency |
| Community bug report or correction | Relevant file | File GitHub issue, apply fix, tag new release |

### Ownership

Assign a DRI (Directly Responsible Individual) for this pack. Suggested home team: **DevRel** or **Developer Experience**, with input from:
- Android platform team (API accuracy)
- DataWedge/EMDK team (SDK accuracy)
- Field solutions / SE team (real-world migration pain points)

### Review cadence

- **Quarterly**: Check for new Android version announcements, Zebra SDK releases
- **At each Android release**: Full review of migration-guide.md against Google's migration docs and behavior changes list
- **At each major Zebra OS release**: Review WS50/WS501 appendix and any device-specific sections

---

## 6. Feedback Collection

Route developer feedback back to improve the guide:

- **GitHub Issues**: Primary channel for corrections, missing topics, broken examples
- **GitHub Discussions**: Open-ended Q&A and feature requests
- **TechDocs feedback widget**: If TechDocs supports it, enable "Was this helpful?" on the page
- **DevRel inbox / community Slack**: Monitor for recurring questions — each repeated question is a gap in the guide

---

## Quick Reference: Files to Copy Per AI Tool

| AI Tool | File to copy | Where to put it |
|---|---|---|
| Claude Code | `CLAUDE.md` | Project root |
| Cursor | `.cursorrules` | Project root |
| GitHub Copilot | `CLAUDE.md` content | `.github/copilot-instructions.md` |
| Any AI chat | `docs/system-prompt.md` | Paste as first message |
| Claude.ai Project | Upload `docs/` folder files | Project knowledge base |