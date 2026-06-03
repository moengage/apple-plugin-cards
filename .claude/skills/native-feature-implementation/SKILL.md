---
name: native-feature-implementation
description: Create a minor version PR for apple-plugin-cards based on a new native SDK API and SDK contract. Reads contracts remotely, implements the bridge method, updates CHANGELOG and version — then creates a PR.
parameters:
  - name: "ticket_id"
    description: "JIRA ticket ID, e.g. 'MOEN-44072'. Extracted from command text if not supplied."
    optional: true
  - name: "feature_description"
    description: "Natural language description of the feature. E.g. 'get clicked cards count', 'delete cards by category'."
  - name: "contract_pr_url"
    description: "GitHub PR URL in mobile-sdk-contracts that adds the feature contract. E.g. 'https://github.com/moengage/mobile-sdk-contracts/pull/12'."
  - name: "ios_native_version"
    description: "Minimum native iOS SDK version required for this feature. Updates sdkVerMin in package.json and adds a '[bump] Updated MoEngage-iOS-SDK to X' CHANGELOG entry. E.g. '10.13.0'. Optional — if not provided, sdkVerMin is not updated."
    optional: true
  - name: "pluginbase_version"
    description: "MoEngagePluginBase version required for this feature. Updates pluginbaseVerMin. Optional."
    optional: true
  - name: "native_sdk_pr_url"
    description: "GitHub PR URL in MoEngage-iPhone-SDK that adds the native API. Optional — if not provided, master branch is used."
    optional: true
---

# Minor Version PR — apple-plugin-cards

You are implementing a minor version change in `apple-plugin-cards` that bridges a new native
iOS SDK API to hybrid frameworks via the cards plugin bridge.

---

## Architecture overview (read before implementing)

**Cards is architecturally different from iOS-PluginBase and apple-plugin-geofence:**

| Concern | How cards does it |
| --- | --- |
| Bridge entry point | `MoEngagePluginCardsBridge.swift` — single `@objc final public class` |
| Native calls | Via `handler: MoEngagePluginCardsBridgeHandler` protocol — never `MoEngageSDKCards.sharedInstance` directly |
| identifier | `Optional<String>` — always `guard let identifier = MoEngagePluginUtils.fetchIdentifierFromPayload(attribute: payload)` |
| Guard failure | Call `logAppIdentifierFetchFailed(for: payload)` and `return` |
| Logging | `MoEngagePluginCardsLogger.debug(...)` and `.error(...)` |
| Response building | `MoEngagePluginCardsUtil.buildHybridPayload(forIdentifier:containingData:)` — always wraps data |
| Response models | `HybridEncodable` conformances in `DataTransfer/NativeToHybrid/` — call `.encodeForHybrid()` |
| Input decoding | Decoders in `DataTransfer/HybridToNative/` — use `MoEngagePluginCardsUtil.getData` / `getNestedData` + `decodeFromHybrid` |
| Constants | `MoEngagePluginCardsContants` — `enum` with `static let` strings |
| Bridge handler protocol | `MoEngagePluginCardsBridgeHandler` at bottom of bridge file — add new method signature here AND as extension on `MoEngageSDKCards` |

---

## Phase 0 — Clarify Inputs

### 0.1 Extract ticket ID
Scan the user's full command for `MOEN-\d+` → **`ticketId`**.
If not found, ask before proceeding.

### 0.2 Confirm all required inputs
If either `feature_description` or `contract_pr_url` is missing, ask for them before proceeding.
`ios_native_version` is optional — do not ask for it if absent.

Derive:
- **`featureName`** — lowercase slug from `feature_description` (e.g. `getclickedcardscount`)
- **`prNumber`** — numeric part of `contract_pr_url`
- **`branchName`** — `feature/<ticketId>-<featureName>`

---

## Phase 1 — Read Contracts from PR (Hybrid ↔ CardsPlugin boundary)

### 1.1 Fetch PR file list

```bash
gh pr view <prNumber> --repo moengage/mobile-sdk-contracts --json title,body,files,headRefName
```

Extract:
- **`contractBranch`** — `headRefName`
- **`hybridToNativeFiles`** — changed files under `json/hybridToNative/`
- **`nativeToHybridFiles`** — changed files under `json/nativeToHybrid/`

### 1.2 Read contract files

For each file in `hybridToNativeFiles`:
```
https://raw.githubusercontent.com/moengage/mobile-sdk-contracts/<contractBranch>/<path>
```
- Filename (without `.json`) = **method name**
- Content = **input payload schema**

For each file in `nativeToHybridFiles`:
```
https://raw.githubusercontent.com/moengage/mobile-sdk-contracts/<contractBranch>/<path>
```
- Content = **response payload schema** — keys here must appear in the `buildHybridPayload` response

### 1.3 Classify

| File status | Meaning |
| --- | --- |
| **New file** added | New method — full bridge implementation needed (Phase 2 required) |
| **Existing file** modified | Payload change only — update existing method, skip Phase 2 |

For **payload changes on existing files**:
- `hybridToNative` modified → extract additional input fields in the existing bridge method
- `nativeToHybrid` modified → add new keys to the `buildHybridPayload` response in the existing method

For new files:

| New contract files | Classification |
| --- | --- |
| `hybridToNative` only | **Fire-and-forget** (Type 1) — no response |
| both `hybridToNative` and `nativeToHybrid` | **Completion handler** (Type 2) — bridge method takes `completionHandler` param |

Print a `### Contract Summary` with method name(s), file status, payload schema, and classification.

---

## Phase 2 — Find the Native API (CardsPlugin ↔ Native boundary)

### 2a — Resolve source

**If `native_sdk_pr_url` was provided:**
```bash
gh pr view <prNumber> --repo moengage/MoEngage-iPhone-SDK --json title,body,files,headRefName
```
Read each changed `.swift` file:
```
https://raw.githubusercontent.com/moengage/MoEngage-iPhone-SDK/<nativeBranch>/<path>
```

**If `native_sdk_pr_url` was NOT provided:**
Fetch `MoEngageSDKCards` from master:
```
https://raw.githubusercontent.com/moengage/MoEngage-iPhone-SDK/master/Sources/MoEngageCards/Public/MoEngageSDKCards.swift
```
If not found there, search:
```
https://api.github.com/search/code?q=<featureName>+repo:moengage/MoEngage-iPhone-SDK+language:Swift+path:Sources/MoEngageCards
```

### 2b — Extract native signature

Extract:
- **Full method signature** (name, parameters, return type, completion closure shape)
- **Response model type** — what the completion closure receives (e.g. `MoEngageCardData?`, `Int`, `Bool`)
- **Availability guards** — `@available`, `#if os(tvOS)`

The type is always **Type 1** (fire-and-forget) or **Type 2** (completion handler) for cards — 
the `MoEngagePluginCardsBridgeHandler` protocol never uses delegate/event patterns.

Also determine:
- Does the input payload need decoding beyond just `identifier`? (e.g. a card object, category string)
  If yes → a `DataTransfer/HybridToNative/` decoder file may be needed
- Does the response model already conform to `HybridEncodable`?
  If no → a new `DataTransfer/NativeToHybrid/` conformance file may be needed

Print a `### Native API Summary` with the finalized type, native signature, and notes on any new decoder/encoder files needed.

---

## Phase 3 — Read Current CardsPlugin State

Read these files:

1. `Sources/MoEngagePluginCards/MoEngagePluginCardsBridge.swift`
2. `Sources/MoEngagePluginCards/Helpers/MoEngagePluginCardsContants.swift`
3. `Sources/MoEngagePluginCards/Helpers/MoEngagePluginCardsUtil.swift`
4. `Sources/MoEngagePluginCards/DataTransfer/NativeToHybrid/HybridEncodable.swift`
5. `package.json` — current version, `sdkVerMin`, `pluginbaseVerMin`
6. `CHANGELOG.md` — format reference

Identify:
- Current version (e.g. `3.10.0`) → new minor version (e.g. `3.11.0`)
- Whether any existing `HybridEncodable` conformance covers the new response model
- Whether any existing decoder in `DataTransfer/HybridToNative/` covers the new input
- Closest existing bridge method to use as template

---

## Phase 4 — Propose Implementation Plan

Output a numbered checklist under `### Implementation Plan`:

1. Branch: `<branchName>`
2. Files to change and exactly what to add/modify in each:
   - `MoEngagePluginCardsBridge.swift` — new bridge method + new entry in `MoEngagePluginCardsBridgeHandler` protocol + new `extension MoEngageSDKCards` stub (if new method)
   - `MoEngagePluginCardsContants.swift` — new constant keys for response payload (if any)
   - `DataTransfer/HybridToNative/<NewDecoder>.swift` — new decoder struct (if input requires it)
   - `DataTransfer/NativeToHybrid/<Model>+Encode.swift` — new `HybridEncodable` conformance (if needed)
   - `package.json` — minor version bump + `sdkVerMin` + optionally `pluginbaseVerMin`
   - `CHANGELOG.md` — new entry
3. tvOS guard if native API is iOS-only

Ask: *"Does this plan look right before I implement?"* Wait for approval.

---

## Phase 5 — Implement

Once approved, implement **in this order**:

### 5a — Constants

Open `Sources/MoEngagePluginCards/Helpers/MoEngagePluginCardsContants.swift`.
Add any new response key constants as `static let camelCaseName = "camelCaseName"` inside the
existing `enum MoEngagePluginCardsContants`. Do not create a new enum.

### 5b — DataTransfer files (if needed)

**Input decoder** (`DataTransfer/HybridToNative/<NewType>.swift`):
Follow the pattern of `MoEngageCardClickData.swift` — a struct with `HybridKeys` enum and
`static func decodeFromHybrid(_ data: [String: Any]) throws -> Self`.

**Response encoder** (`DataTransfer/NativeToHybrid/<Model>+Encode.swift`):
Follow the pattern of `MoEngageCardsData.swift` — an `extension <Model>: HybridEncodable` with
`func encodeForHybrid() -> [String: Any?]`.

### 5c — Bridge method in MoEngagePluginCardsBridge.swift

Read the relevant example file before generating code:

| Type | Example file |
| --- | --- |
| Type 1 — fire-and-forget | `examples/Type1_FireAndForget.swift` |
| Type 2 — completion handler | `examples/Type2_CompletionHandler.swift` |

**Rules:**
- `@objc public` — required for ObjC runtime access
- First parameter is always `_ payload: [String: Any]`
- Always `guard let identifier = MoEngagePluginUtils.fetchIdentifierFromPayload(attribute: payload)` — never force-unwrap
- On guard failure: call `logAppIdentifierFetchFailed(for: payload)` and `return`
- Call native via `handler.<method>` — never `MoEngageSDKCards.sharedInstance` directly
- Log entry with `MoEngagePluginCardsLogger.debug("...", forData: payload)`
- For Type 2: build response with `MoEngagePluginCardsUtil.buildHybridPayload(forIdentifier:containingData:)` and log response
- For input decoding beyond identifier: use `MoEngagePluginCardsUtil.getData` / `getNestedData` inside a `do/catch`, log errors with `MoEngagePluginCardsLogger.error`
- Response keys must exactly match the `nativeToHybrid` contract
- `#if os(tvOS)` guard if the native API is iOS-only

**Also update `MoEngagePluginCardsBridgeHandler` protocol** (at the bottom of `MoEngagePluginCardsBridge.swift`):
Add the new method signature to the protocol AND a default implementation in
`extension MoEngageSDKCards: MoEngagePluginCardsBridgeHandler` (or add a new extension below it).

---

### 5d + 5e — Version bump and CHANGELOG

Invoke the `version-update` skill with:
- `new_version` = next minor version (e.g. `3.10.0` → `3.11.0`)
- `changelog_entries` = `["[minor] Added support for <feature_description>"]` — **do NOT include the ticket ID in the changelog entry**
- `native_sdk_version` = `<ios_native_version>` — **only if `ios_native_version` was provided**; omit otherwise
- `pluginbase_version` = `<pluginbase_version>` (if provided)

When `ios_native_version` is provided, the `version-update` skill will:
- Set `sdkVerMin` → `<ios_native_version>` in `package.json`
- Append `[<sdk_bump_type>] Updated MoEngage-iOS-SDK to <ios_native_version>` to the CHANGELOG entry

When `ios_native_version` is **not** provided:
- `sdkVerMin` in `package.json` is left unchanged
- No SDK version line is added to the CHANGELOG

---

## Phase 6 — Branch, Commit, Push and PR

### 6.1 — Create branch and commit

```bash
git status
git checkout -b <branchName>
git add -A
git commit -m "<ticketId>: Added support for <feature_description>"
```

If `git checkout -b` fails because the branch already exists, stop and ask the user.

### 6.2 — Push and create PR

```bash
git push -u origin <branchName>

gh pr create \
  --repo moengage/apple-plugin-cards \
  --base development \
  --title "<ticketId>: Added support for <feature_description>" \
  --body "$(cat <<'EOF'
### Jira Ticket
https://moengagetrial.atlassian.net/browse/<ticketId>

### Description
Added support for <feature_description>

### Contract PR
<contract_pr_url>

### Native SDK
<native_sdk_pr_url or "moengage/MoEngage-iPhone-SDK @ master">

### Changes
- `MoEngagePluginCardsBridge.swift` — <new method / updated method: methodName, type: 1/2>
- `MoEngagePluginCardsContants.swift` — <new constants or "no change">
- `DataTransfer/HybridToNative/` — <new decoder file or "no change">
- `DataTransfer/NativeToHybrid/` — <new encoder file or "no change">
- `package.json` — version <old> → <new>, sdkVerMin <old> → <ios_native_version>
- `CHANGELOG.md` — new entry
EOF
)"
```

---

## Phase 7 — Summary

Print:

```
PR:       <pr_url>
Branch:   <branchName>
Version:  <old> → <new>
sdkVerMin: <old> → <ios_native_version>            ← omit this line if ios_native_version not provided
pluginbaseVerMin: <old> → <pluginbase_version>   ← omit this line if pluginbase_version not provided
Ticket:   <ticketId>
Contract PR: <contract_pr_url>

Files changed:
  - MoEngagePluginCardsBridge.swift         (<new/updated> method: <methodName>, type: <1/2>)
  - MoEngagePluginCardsContants.swift       (new constants: <list> or "no change")
  - DataTransfer/HybridToNative/            (<new file> or "no change")
  - DataTransfer/NativeToHybrid/            (<new file> or "no change")
  - package.json                            (version bump + sdkVerMin)
  - CHANGELOG.md                            (new entry)

Native SDK source: <native_sdk_pr_url or "moengage/MoEngage-iPhone-SDK @ master">
```
