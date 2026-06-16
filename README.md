# Wealth

A personal finance iPhone app: checking/savings/credit cards, Roth IRA, 401(k) and
HSA work benefits, student/car loans and bills, and a rule-based virtual financial
advisor — all backed by data stored locally on your phone.

## How it's put together

```
ios/      Native SwiftUI app (the actual iPhone app)
server/   Thin Node proxy that talks to Plaid on the app's behalf
```

**Why a server exists even though the app stores data locally:** Plaid requires a
secret API key on every call (creating a link session, syncing transactions,
reading balances/liabilities/investments). That secret can never live in the iOS
app, so `server/` exists purely to hold it and proxy those calls. It stores nothing
about your finances — only an encrypted Plaid `access_token` per linked
institution. Every balance, transaction, bill, and loan you see in the app is
persisted on-device via SwiftData; the server is just a relay.

If you don't want to link real accounts yet, skip the server entirely and use
"Add Account → Or Enter Manually" in the app.

## Running the server

```bash
cd server
cp .env.example .env
# fill in PLAID_CLIENT_ID / PLAID_SECRET from https://dashboard.plaid.com (start in "sandbox")
# generate TOKEN_ENCRYPTION_KEY with: openssl rand -hex 32
npm install
npm run dev
```

This starts the proxy on `http://localhost:8787`. Point the iOS app at it by
editing `PlaidAPIClient.baseURL` in `ios/Wealth/Networking/PlaidAPIClient.swift`
(localhost only works when running the Simulator on the same Mac; for a physical
phone, deploy the server somewhere reachable, e.g. a small Fly.io/Render instance,
over HTTPS).

## Running the iOS app

You'll need a Mac with Xcode 16+. Generate the Xcode project with
[XcodeGen](https://github.com/yonaskolb/XcodeGen) instead of hand-editing a
`.xcodeproj`:

```bash
brew install xcodegen
cd ios
xcodegen generate
open Wealth.xcodeproj
```

Then build and run on a Simulator or your device (⌘R). `project.yml` already
declares the Plaid `LinkKit` Swift Package dependency, so Xcode will fetch it on
first open.

> No Mac yet? You can still read/review all the Swift source under `ios/Wealth`;
> it just can't be compiled or run outside Xcode, since iOS apps require Apple's
> toolchain.

## What's implemented

- **Accounts** (`ios/Wealth/Models/Account.swift`): checking, savings, credit
  cards, Roth/Traditional IRA, 401(k), HSA, student/auto/mortgage/other loans.
  Add manually or link via Plaid (checking/savings/credit cards/investment
  accounts, including employer 401(k)/HSA where your provider supports Plaid).
- **Bills** (`ios/Wealth/Models/Bill.swift`): one-off or recurring (weekly,
  biweekly, semimonthly, monthly, quarterly, annual) — covers rent/utilities,
  loan and credit card payments, and payroll-deducted work-benefit premiums
  (health/dental/vision), tagged separately from 401(k)/HSA contributions.
- **Debt payoff planner** (`ios/Wealth/Views/Bills/DebtPayoffView.swift`):
  avalanche (highest APR first) or snowball (smallest balance first) ordering
  across every loan/credit card, with an extra-payment slider.
- **Work benefits**: 401(k) and HSA accounts track employer name, employer
  match %, and year-to-date contribution against the IRS annual limit
  (`ContributionLimits.swift` — defaults are editable per-account since these
  change yearly).
- **Advisor** (`ios/Wealth/Insights/InsightsEngine.swift`): a deterministic
  rules engine — no external AI call, nothing leaves the device. It checks
  credit utilization, emergency-fund coverage, which debt to prioritize,
  contribution pace toward annual limits, employer-match reminders, upcoming
  cash-flow gaps, savings rate, and top spending category, all computed live
  from your accounts/bills/transactions.
- **On-device AI chat** (`ios/Wealth/Insights/AIAdvisorManager.swift`,
  `ios/Wealth/Views/Advisor/AIChatView.swift`): a free-form Q&A advisor on top
  of the same rules engine, powered by Apple's **Foundation Models** framework
  — see "Apple's on-device AI" below. Free, no API key, no network call.
- **Bill reminder notifications** (`ios/Wealth/Notifications/NotificationManager.swift`):
  local notifications the day before and on the due date for every bill —
  see "Notifications" below.

## Apple's on-device AI (Foundation Models framework)

iOS 26 shipped direct developer access to the ~3B-parameter on-device model
that powers Apple Intelligence, via `import FoundationModels`. It's the
free/private alternative to a paid LLM API mentioned earlier: no per-token
billing, no API key, and prompts never leave the phone.

- `SystemLanguageModel.default.availability` tells you whether it can run on
  this device right now — `.available`, or `.unavailable(reason)` where
  `reason` is `.deviceNotEligible` (pre-iPhone 15 Pro hardware), `.appleIntelligenceNotEnabled`
  (user hasn't turned it on in Settings), or `.modelNotReady` (still downloading).
- `LanguageModelSession(instructions:)` starts a conversation; `session.respond(to:)`
  sends a turn and returns the reply in `response.content`. Sessions also support
  streaming (`streamResponse`) and structured output via `@Generable`/`@Guide`
  macros if you want typed responses instead of free text later.
- It only works on Apple Intelligence-eligible hardware (iPhone 15 Pro or
  newer) with Apple Intelligence turned on in Settings, on iOS 26+.
  `AIChatView` checks `availability` and shows a clear message instead of a
  chat box on unsupported devices/older iOS — the rest of the app (including
  the rule-based Advisor tab) works everywhere regardless.
- `AIAdvisorManager.buildInstructions` is the seam that turns your local
  accounts/bills into the context the model reasons over — read it to see
  exactly what it's told.
- To go deeper: Apple's [WWDC25 session "Deep dive into the Foundation Models
  framework"](https://developer.apple.com/videos/play/wwdc2025/301/) and the
  [FoundationModels framework reference](https://developer.apple.com/documentation/foundationmodels)
  are the primary sources.

Since this framework was introduced after my training data, the `AIAdvisorManager`/`AIChatView`
code is written carefully against the documented API shape but **hasn't been
compiled** (this environment has no Xcode/macOS). If Xcode flags a renamed
case or method when you first build, it should be a one-line fix — the
overall structure (session lifecycle, availability handling, instructions)
is correct.

## Notifications

`NotificationManager` schedules two local notifications per bill — one the
day before at 9am, one on the due date at 9am — using `UNUserNotificationCenter`.
No push server or APNs setup is needed since these are purely local,
scheduled from data already on the device:

- The app asks for notification permission once, on first launch (`RootTabView.task`).
- Adding a bill (`AddBillView.save`) schedules its reminders immediately.
- Deleting a bill (`BillsListView`) cancels its pending reminders.
- `rescheduleAll` re-syncs every upcoming bill's notifications on every app
  launch, so nothing goes stale if you skip a few days.

If you deny the permission prompt, bills still work — you just won't get
reminders. There's no in-app way yet to re-prompt after denying (iOS requires
that to happen via Settings); that's a reasonable thing to add later (a
banner linking to `UIApplication.openSettingsURLString`).

## Sample data

`ios/Wealth/SampleData.swift` builds an in-memory SwiftData store with a
realistic mix of accounts/bills/transactions, wired up via `#Preview` on
`RootTabView`. Open that file in Xcode and use the canvas to see the whole app
populated without entering anything by hand.

## Suggested next steps

- Add Face ID / passcode gating before showing balances (`LocalAuthentication`).
- If you want multi-device sync down the road, the SwiftData store can move to
  a `CloudKit`-backed configuration with minimal model changes.
- If you ever want a cloud LLM (e.g. for devices without Apple Intelligence,
  or more capable reasoning) alongside the on-device chat, `AIAdvisorManager.buildInstructions`
  is reusable as the context you'd send to that API too.
