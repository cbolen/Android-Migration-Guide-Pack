# Zebra Android Migration — AI Developer Pack

Guidance and context files to help developers port Android apps to Android 11–15 using AI coding assistants (Claude, Cursor, GitHub Copilot, ChatGPT, Gemini, etc.).

## What's Included

| File | Purpose |
|---|---|
| `CLAUDE.md` | Drop in project root — Claude Code loads it automatically |
| `.cursorrules` | Drop in project root — Cursor loads it automatically |
| `docs/migration-guide.md` | Full A11–A15 migration reference |
| `docs/system-prompt.md` | Paste into any AI chat tool as first message |
| `docs/datawedge-intents-ref.md` | DataWedge Intent API quick reference |
| `examples/` | Vetted Kotlin boilerplate for common Zebra patterns |

## Quick Start by Tool

### Claude Code (CLI or IDE extension)
1. Copy `CLAUDE.md` to your project root
2. Open Claude Code in your project — Zebra context loads automatically

### Cursor
1. Copy `.cursorrules` to your project root
2. Cursor AI now has Zebra context for all suggestions

### GitHub Copilot
1. Copy contents of `CLAUDE.md` into `.github/copilot-instructions.md` in your repo

### ChatGPT / Gemini / Any AI Chat
1. Open `docs/system-prompt.md`
2. Paste the full contents as your first message
3. Then paste your code or describe your problem

### Claude.ai (browser)
- Use the shared Zebra Migration Project link (see your Zebra DevRel contact)
- Or paste `docs/system-prompt.md` as first message in a new chat

## Scope

This guide covers migration from **Android 11 (API 30) to Android 15 (API 35)**.

Primary SDKs covered:
- **DataWedge** — recommended for all barcode scanning (intent-based, no scanner code in app)
- **Zebra AI Suite** — A14+ only, advanced data capture (AI barcode, OCR, shelf recognition)
- **EMDK** — direct hardware APIs for specialized scanner control
- **Android Jetpack** — compatibility libraries

## Notes

- DataWedge is the recommended scanning integration for all new development
- Use Zebra AI Suite (A14+) for advanced data capture scenarios — AI barcode recognition, OCR, shelf analysis
- EMDK is appropriate only when direct scanner control is required (custom decode params, serial/USB, payment hardware)
- Zebra AI Suite was released with Android 14 — only relevant for A14+ scenarios
- SSM (Secure Storage Manager) is not required for standard A11+ storage patterns; see `docs/migration-guide.md` for when it applies

## Practice App

**[android-migration-sample](https://github.com/cbolen/android-migration-sample)** — A legacy inventory app intentionally written with API 30 patterns (AsyncTask, startActivityForResult, hardcoded storage paths, missing exported flags, etc.). Use it as a safe sandbox to practice applying this guide with your AI tool of choice before touching production code.

## Automating the Migration

See **[docs/how-to-use.md](docs/how-to-use.md)** for step-by-step instructions on adding these files to your own project and running AI-assisted migration phase by phase, including a `migrate.sh` script for Claude Code users.

## Support

- Zebra Developer Portal: https://developer.zebra.com
- DataWedge Docs: https://techdocs.zebra.com/datawedge/latest/guide/api/
- EMDK Docs: https://techdocs.zebra.com/emdk-for-android/latest/guide/about/
- AI Suite Docs: https://techdocs.zebra.com/ai-datacapture/latest/about/
- DevRel: developer@zebra.com