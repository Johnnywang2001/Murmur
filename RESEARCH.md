# RESEARCH.md — Technical Decisions

## Why a Standalone App (Not a Keyboard Extension)

**The #1 constraint**: iOS keyboard extensions (`UIInputViewController`) **cannot access the microphone**. Apple's App Extension sandbox explicitly blocks `AVAudioEngine` and `AVAudioSession.requestRecordPermission()` from keyboard extensions.

Options considered:
1. **Keyboard extension with full-access** — Even with "Allow Full Access" enabled, microphone access is still blocked. Full access only grants network and clipboard access, not hardware.
2. **App Group shared recording** — The host app could record and share audio via App Groups, but this requires the user to switch apps mid-dictation. Terrible UX.
3. **Standalone dictation app** ✅ — Simple, works, no UX friction. User records in-app, copies the result, pastes wherever needed.

**V2 path**: A keyboard extension could work if it displays transcribed text from the main app via App Groups or a shared container. The main app would handle recording in the background, and the keyboard would display/insert the result. This requires careful coordination and background audio session management.

## WhisperKit vs Alternatives

| Option | Pros | Cons |
|--------|------|------|
| **WhisperKit** ✅ | Native Swift, CoreML optimized, Argmax maintains it, great iOS support | Newer framework, smaller community |
| **whisper.cpp** | C++, very portable, battle-tested | Requires bridging header, manual CoreML integration, more boilerplate |
| **Apple Speech** | Built-in, no dependencies | Requires network in some configurations, less accurate, not truly private |
| **MLX Swift** | Apple's ML framework | Not optimized for Whisper specifically, more work to set up |

**Decision**: WhisperKit is purpose-built for running Whisper models on Apple devices via CoreML. It handles model downloading, tokenization, and inference in a clean Swift API. No bridging headers, no manual model conversion.

## Model Selection: Tiny vs Base

WhisperKit supports all Whisper model sizes. For a mobile dictation app:

- **Tiny** (~39M params, ~40MB): Best for casual dictation. Transcription of 30s audio takes ~2-4s on iPhone 14+. Good enough for most English dictation.
- **Base** (~74M params, ~75MB): Noticeably better accuracy, especially with accents or technical vocabulary. Takes ~4-8s for 30s audio.
- **Small/Medium/Large**: Too large for a lightweight dictation app. Large-v3 is ~1.5GB and takes 15-30s per 30s clip.

**Default**: Tiny. Users can switch to Base in settings if they want better accuracy.

## Audio Recording: AVAudioEngine

**Why AVAudioEngine over AVAudioRecorder?**

- `AVAudioEngine` gives us access to the raw audio buffer for real-time level metering (the pulsing mic animation)
- We can convert to 16kHz mono on-the-fly, which is what WhisperKit expects
- More control over format, buffer sizes, and interruption handling
- `AVAudioRecorder` would save to a file in the device's native format (often 48kHz stereo), requiring post-hoc conversion

**Recording format**: 16kHz mono PCM WAV. This is WhisperKit's native input format. Recording directly at this sample rate avoids a separate conversion step and keeps file sizes small (~32KB/second).

## Filler Word Removal Strategy

**Approach**: Regex-based word boundary matching, applied post-transcription.

Why not during transcription?
- WhisperKit doesn't expose token-level hooks for suppression (unlike some whisper.cpp builds)
- Post-processing is simpler, testable, and configurable
- Users might want to see the raw transcription in a future version

**Filler word list**: Curated from linguistic research on English conversational fillers. Sorted by frequency:
1. "um", "uh", "erm" — hesitation markers
2. "like" — discourse marker (risky — can be valid, but in dictation context it's almost always filler)
3. "you know", "I mean" — interpersonal fillers
4. "basically", "actually", "literally" — hedge words
5. "kind of", "sort of" — approximators
6. "right", "so" — discourse connectors used as fillers

**Edge case**: "like" as filler vs "like" as comparison ("I like pizza"). Current approach removes all instances. A future improvement could use NLP to detect syntactic role, but for dictation, the aggressive approach works well.

## Concurrency Model

- **AudioRecorder**: `@MainActor` — UI-bound state (isRecording, audioLevel), audio engine tap runs on audio thread via closure
- **TranscriptionService**: `@MainActor` — holds published state, but actual WhisperKit work runs on background threads internally
- **TextProcessor**: Pure value type (`struct` with static methods) — no concurrency concerns

WhisperKit internally manages its own dispatch queues for model inference. We don't need to manually manage background threads for transcription.

## Future Considerations

1. **Streaming transcription**: WhisperKit supports `AudioStreamTranscriber` for real-time transcription. Could show text as the user speaks instead of waiting until they stop.
2. **Keyboard extension (v2)**: Use App Groups to share transcription results. Main app records in background, keyboard extension reads from shared container.
3. **Language detection**: WhisperKit supports `detectLanguage()`. Could auto-detect language instead of hardcoding English.
4. **History**: Save past transcriptions with timestamps for easy reference.
5. **Custom vocabulary**: Use WhisperKit's `promptTokens` to bias transcription toward domain-specific terms.
