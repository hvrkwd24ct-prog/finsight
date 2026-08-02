# FinSight

A self-contained personal finance dashboard — bank statements, savings, ISAs and
investments in one place, with targets, monthly reviews and adviser-style
recommendations.

**Everything stays on your device.** Data lives in the browser's `localStorage`
(or the app's own storage on macOS/iOS). There is no server, no account, and no
network call — the page carries React, Babel and pdf.js inline and works fully
offline.

## Running it

**In a browser** — open `index.html`. That's the whole app.

**As a Mac or iPhone app** — open `FinSight.xcodeproj`, pick a destination and
Run. Requires Xcode 16+ (macOS 14+ / iOS 17+). To install on your own device,
set a Team under the target's Signing & Capabilities tab.

## Layout

```
index.html                 the entire dashboard — vendor libs, styles and app source
FinSight/                  SwiftUI + WKWebView wrapper for macOS and iOS
FinSight.xcodeproj/        single target, both platforms
```

The Xcode project references `index.html` at the repo root rather than a copy,
so editing the dashboard updates both apps — no sync step.

The native wrapper exists to supply the things a bare web view doesn't:
`alert`/`confirm`/`prompt` bridged to `NSAlert`/`UIAlertController`, and file
exports bridged to a save panel (macOS) or share sheet (iOS).

## Importing data

Bank and credit card statements (CSV or PDF), savings, ISA and broker exports,
crypto exchange CSVs, and FinSight's own JSON backups. Column mappings are
remembered per provider. Parsing happens locally in the page.
