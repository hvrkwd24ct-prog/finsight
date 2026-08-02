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

## Keeping your data

Browsers treat ordinary site storage as disposable. iOS Safari is the strictest:
it clears script-writable storage from any site you haven't opened in about a
week. Two things reduce the risk, and one removes it:

- **Add to Home Screen** (Share → Add to Home Screen). The page declares itself a
  web app, so it gets a storage container of its own rather than sharing
  Safari's — and note that means it starts empty, separate from whatever is in
  the Safari tab.
- **Settings → Backup & data → Storage** reports whether this browser has
  promised to keep the data, how much is stored, and which container you are in.
- **The native app** stores in its own app container, which nothing sweeps.

Export a backup either way. Restoring it is how data moves between the browser,
the Home Screen app and the native app — they are three separate stores.

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

## What it tracks

Current accounts, savings, pots, credit cards and non-investment ISAs (cash,
Lifetime, Help to Buy, IF, Junior) live under **Accounts**. Stocks & Shares
ISAs, general investing, bonds (gilts, index-linked, corporate, Premium Bonds,
fixed-rate, funds) and crypto live under **Investments** — a broker like
Trading 212 is a name you give an account, not a kind of account.

**Mortgage** takes what you still owe, the rate and the term, and works out the
monthly payment, the interest/capital split, when it clears and what an
overpayment would save. The payment shows up in **Recurring** automatically —
it is derived from the mortgage, so it cannot drift out of step. The debt counts
against net worth and any property value you enter counts toward it.

## Importing data

Bank and credit card statements (CSV or PDF), savings, ISA and broker exports,
crypto exchange CSVs, and FinSight's own JSON backups. Column mappings are
remembered per provider. Parsing happens locally in the page.
