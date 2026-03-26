# Murmur QA Report

**Date:** 2026-03-25  
**Reviewer:** QA Engineer (automated)  
**Overall Assessment:** FAIL — Critical Xcode project configuration issues prevent building

---

## 1. Issues Found and FIXED (in code)

### 1.1 ContentView never responded to URL scheme dictation requests
**Severity:** Critical  
**File:** `Murmur/ContentView.swift`  
**Problem:** `MurmurApp.swift` sets `appState.shouldStartDictation = true` when `murmur://dictate` is received, but `ContentView` never observed this property and never auto-started recording.  
**Fix:** Added `@EnvironmentObject private var appState: AppState`, an `.onChange(of: appState.shouldStartDictation)` handler, and a `handleDictationRequest()` method that waits for the model to load, then auto-starts recording.

### 1.2 No keyboard return flow after dictation
**Severity:** Critical  
**File:** `Murmur/ContentView.swift`  
**Problem:** After the main app transcribes audio initiated by the keyboard, it never saved the result to `SharedDefaults` for the keyboard to pick up.  
**Fix:** Added `isDictationFromKeyboard` state flag. After transcription, if the session was keyboard-initiated, the cleaned text is written to `SharedDefaults.setPendingText()`.

### 1.3 iOS 16 compilation failure — `AVAudioApplication` requires iOS 17
**Severity:** Critical  
**File:** `Murmur/AudioRecorder.swift`  
**Problem:** `AVAudioApplication.shared.recordPermission` and `AVAudioApplication.requestRecordPermission()` are iOS 17+ APIs. The deployment target is iOS 16.0, so this would fail to compile or crash at runtime.  
**Fix:** Added `if #available(iOS 17.0, *)` guards with fallbacks to the deprecated `AVAudioSession.sharedInstance().recordPermission` for iOS 16.

### 1.4 `onChange` modifier used iOS 17+ syntax
**Severity:** Medium  
**File:** `Murmur/ContentView.swift`  
**Problem:** `onChange(of:) { _, newValue in }` (two-parameter closure) is iOS 17+. Deployment target is iOS 16.  
**Fix:** Changed to the single-parameter form `onChange(of:) { newValue in }` which is available since iOS 14.

### 1.5 WhisperKit model names incorrect
**Severity:** Medium  
**File:** `Murmur/TranscriptionService.swift`  
**Problem:** Model names were `"tiny"` and `"base"`. WhisperKit's model repository uses architecture-prefixed names.  
**Fix:** Changed to `"openai_whisper-tiny"` and `"openai_whisper-base"`.

### 1.6 `unloadModels()` may not exist in WhisperKit API
**Severity:** Medium  
**File:** `Murmur/TranscriptionService.swift`  
**Problem:** Called `whisperKit?.unloadModels()` which may not be a public API method.  
**Fix:** Changed to simply nil-out the `whisperKit` instance, which releases all model memory via ARC.

### 1.7 Overly aggressive filler word removal
**Severity:** Medium  
**File:** `Murmur/TextProcessor.swift`  
**Problem:** The filler list included common legitimate words: "like", "so", "right", "well", "actually", "literally", "honestly", "basically". These would be stripped from sentences like "I like this" or "This is right."  
**Fix:** Trimmed the list to only unambiguous fillers (um, uh, erm, er, you know, I mean, kinda, sorta, okay so, yeah so).

### 1.8 TextProcessor empty input edge case
**Severity:** Low  
**File:** `Murmur/TextProcessor.swift`  
**Problem:** No early return for empty or whitespace-only input. Processing would run regex on empty strings.  
**Fix:** Added guard at top of `process()` that returns `""` for empty/whitespace input.

### 1.9 Keyboard URL opening — fragile responder chain approach
**Severity:** Medium  
**File:** `MurmurKeyboard/KeyboardViewController.swift`  
**Problem:** The code tried to cast responders to `UIApplication` (which doesn't exist in extension contexts) before falling to the selector approach.  
**Fix:** Simplified to only use the `openURL:` selector walk, which is the established pattern for keyboard extensions. Removed the `UIApplication` cast and the `extensionContext` fallback (which doesn't work for keyboard extensions — only Today/Share extensions).

### 1.10 Pending text timer too aggressive
**Severity:** Low  
**File:** `MurmurKeyboard/KeyboardViewController.swift`  
**Problem:** Timer checked shared defaults every 0.5 seconds, adding unnecessary I/O in a memory-constrained extension.  
**Fix:** Changed interval to 1.0 seconds and ensured the check runs on the main thread explicitly.

### 1.11 ContentView preview missing EnvironmentObject
**Severity:** Low  
**File:** `Murmur/ContentView.swift`  
**Problem:** The `#Preview` macro didn't provide `AppState()` as an environment object, causing preview crashes.  
**Fix:** Added `.environmentObject(AppState())` to the preview.

---

## 2. Issues Found but NOT FIXED (require manual Xcode work)

### 2.1 ❗ MurmurKeyboard target does not exist in the Xcode project
**Severity:** BLOCKER  
**File:** `Murmur.xcodeproj/project.pbxproj`  
**Problem:** The Xcode project only contains one target: `Murmur` (the main app). There is **no keyboard extension target** in the project at all. The files exist on disk (`MurmurKeyboard/KeyboardViewController.swift`, `MurmurKeyboard/KeyboardView.swift`, `MurmurKeyboard/Info.plist`, `MurmurKeyboard/MurmurKeyboard.entitlements`) but they are not referenced by any target and will not be compiled.  
**Fix required:** In Xcode:
1. File → New → Target → Custom Keyboard Extension → name it `MurmurKeyboard`
2. Set bundle identifier to `com.murmur.app.keyboard` (must be child of main app ID)
3. Add `KeyboardViewController.swift`, `KeyboardView.swift` to the new target
4. Add `SharedDefaults.swift` to **both** targets (main app AND keyboard extension)
5. Set the keyboard extension's entitlements file to `MurmurKeyboard/MurmurKeyboard.entitlements`
6. Embed the keyboard extension in the main app target (Xcode does this automatically when you add a keyboard extension target)

### 2.2 ❗ SharedDefaults.swift not in any target
**Severity:** BLOCKER  
**File:** `Shared/SharedDefaults.swift`  
**Problem:** `SharedDefaults.swift` is not referenced in the Xcode project at all. Neither the main app nor the (non-existent) keyboard extension can compile it. The main app source files reference `SharedDefaults` in `ContentView.swift` (after our fix), so the main app won't compile either.  
**Fix required:** In Xcode, add `Shared/SharedDefaults.swift` to **both** the Murmur and MurmurKeyboard targets.

### 2.3 ❗ Murmur.entitlements not referenced in build settings
**Severity:** BLOCKER  
**File:** `Murmur.xcodeproj/project.pbxproj`  
**Problem:** The build settings have no `CODE_SIGN_ENTITLEMENTS` entry. The entitlements file exists on disk but is never used during signing, meaning the App Group capability won't be enabled.  
**Fix required:** In each target's build settings, set:
- Murmur target: `CODE_SIGN_ENTITLEMENTS = Murmur/Murmur.entitlements`
- MurmurKeyboard target: `CODE_SIGN_ENTITLEMENTS = MurmurKeyboard/MurmurKeyboard.entitlements`

### 2.4 ❗ Bundle identifier mismatch
**Severity:** High  
**File:** `Murmur.xcodeproj/project.pbxproj`  
**Problem:** The bundle identifier is `com.whisperboard.app` but the App Group is `group.com.murmur.shared`. These should align. The keyboard extension's bundle ID must be a child of the main app's (e.g. `com.murmur.app.keyboard`).  
**Fix required:** Change `PRODUCT_BUNDLE_IDENTIFIER` to `com.murmur.app` (both Debug and Release configurations). Set the keyboard extension's bundle ID to `com.murmur.app.keyboard`.

### 2.5 ❗ Missing DEVELOPMENT_TEAM in build settings
**Severity:** High  
**Problem:** No `DEVELOPMENT_TEAM` is set in the project. App Groups and keyboard extensions require a valid Apple Developer team for provisioning.  
**Fix required:** Set `DEVELOPMENT_TEAM` in Xcode for both targets (Signing & Capabilities).

### 2.6 Deployment target should be iOS 16+ (WhisperKit minimum)
**Severity:** Medium  
**Problem:** The deployment target is iOS 16.0. WhisperKit 0.9+ may require iOS 16 minimum, but some features like `AVAudioApplication` needed iOS 17. The code fixes above handle this, but consider bumping to iOS 17.0 to simplify the codebase and use newer APIs without availability checks.  
**Fix required (optional):** In Xcode, update `IPHONEOS_DEPLOYMENT_TARGET` to `17.0` for both targets if iOS 16 support isn't needed.

---

## 3. Risk Areas to Watch During Testing

### 3.1 WhisperKit API Compatibility
The WhisperKit package reference uses `upToNextMajorVersion: 0.9.0`. WhisperKit is pre-1.0 and its API changes frequently. The `WhisperKitConfig` struct, `DecodingOptions` fields, and `TranscriptionResult` shape may differ from what's coded. **Verify after resolving packages** — if it doesn't compile, check the WhisperKit documentation for the installed version.

Specific risks:
- `WhisperKitConfig` parameter names/types
- `DecodingOptions` fields (`usePrefillPrompt`, `usePrefillCache`, `suppressBlank`, etc.)
- `TranscriptionResult.text` property name/type
- Model name format (`openai_whisper-tiny` vs `whisperkit_whisper-tiny` vs just `tiny`)

### 3.2 Keyboard Extension Memory Limit (60MB)
The keyboard extension doesn't load WhisperKit (correct), but SwiftUI hosting in an extension can be memory-heavy. Monitor memory usage with Instruments — if it exceeds ~50MB, iOS will terminate the extension silently.

### 3.3 Audio Converter in Recording Tap
The `AVAudioConverter` inside the `installTap` closure converts buffers from the mic's native format (typically 48kHz stereo) to 16kHz mono. This is happening synchronously on the audio thread. If conversion is slow, it could cause audio glitches or dropped frames. Test with real recordings of 30+ seconds.

### 3.4 Keyboard → App → Keyboard Round-Trip
The full flow is: keyboard taps mic → opens `murmur://dictate` → app auto-records → user taps stop → transcribes → saves to shared defaults → user switches back to previous app → keyboard timer picks up text → inserts. **The weakest link is "user switches back"** — there's no reliable programmatic way for the main app to return to the previous app. Users must manually switch.

### 3.5 Timer-Based Polling in Keyboard Extension
The 1-second timer polling `SharedDefaults.consumePendingText()` works but is inelegant. If the user takes more than 60 seconds to return from the main app, the text expires (the 60-second staleness guard in SharedDefaults). This may need to be increased.

### 3.6 `UserDefaults.synchronize()` Calls
The code calls `.synchronize()` explicitly. Apple deprecated this and says it's unnecessary since iOS 12. It shouldn't cause issues, but it's redundant — `UserDefaults` handles persistence automatically.

### 3.7 Filler Word Regex with Multi-Word Phrases
The regex uses `\b` word boundaries, but phrases like "I mean" or "you know" span multiple words. The `\b` at the start/end works correctly for these, but edge cases around punctuation (e.g. "I mean, ..." or "you know?") may leave the comma/question mark orphaned. The cleanup code handles most cases but watch for weird punctuation artifacts.

### 3.8 No App Transport Security / Network Permissions
WhisperKit downloads models on first launch. This requires network access. The Info.plist doesn't have any ATS exceptions, which is fine (WhisperKit uses HTTPS), but test on a device with airplane mode to verify graceful error handling.

---

## 4. Summary of Required Xcode Work (in order)

1. **Change main app bundle ID** from `com.whisperboard.app` to `com.murmur.app`
2. **Add `CODE_SIGN_ENTITLEMENTS = Murmur/Murmur.entitlements`** to main target build settings
3. **Create MurmurKeyboard extension target** in Xcode (File → New → Target → Custom Keyboard Extension)
4. **Set keyboard extension bundle ID** to `com.murmur.app.keyboard`
5. **Add `CODE_SIGN_ENTITLEMENTS = MurmurKeyboard/MurmurKeyboard.entitlements`** to keyboard target
6. **Add existing files to keyboard target:** `KeyboardViewController.swift`, `KeyboardView.swift`
7. **Add `SharedDefaults.swift` to BOTH targets** (check target membership for both Murmur and MurmurKeyboard)
8. **Set `DEVELOPMENT_TEAM`** for both targets
9. **Enable App Groups capability** for both targets in Signing & Capabilities (group.com.murmur.shared)
10. **Resolve Swift packages** (WhisperKit) — may need to add WhisperKit dependency to main target only
11. **Build and test** — fix any remaining WhisperKit API mismatches

---

## 5. Overall Assessment

### **FAIL**

The Swift source code is well-structured and mostly correct (after the fixes above), but the **Xcode project is fundamentally incomplete**. The keyboard extension target doesn't exist, shared files aren't referenced, entitlements aren't wired up, and the bundle identifier is wrong. These are not code issues — they're project configuration issues that must be resolved in Xcode before the app can build.

**Once the Xcode project is properly configured** (following the steps in Section 4), the code should compile and the end-to-end flow should work. The code-level fixes applied in this review address the logic bugs in the dictation round-trip, iOS version compatibility, and API correctness.

**Estimated effort to fix:** 30-45 minutes of Xcode project configuration work by a developer familiar with keyboard extensions and App Groups.
