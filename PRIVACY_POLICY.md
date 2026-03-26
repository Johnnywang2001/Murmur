# Murmur - Privacy Policy

**Last updated:** March 25, 2026

## Overview

Murmur is a voice-to-text keyboard app that transcribes speech entirely on-device using Apple's CoreML and the WhisperKit framework. Your privacy is fundamental to how Murmur works.

## Data Collection

**Murmur does not collect, store, transmit, or share any personal data.** Specifically:

- **No audio is recorded permanently.** Audio is captured temporarily in memory for transcription and immediately discarded after processing.
- **No transcription data is sent to any server.** All speech-to-text processing happens on your device using the WhisperKit machine learning model.
- **No analytics or tracking.** Murmur does not use any analytics frameworks, crash reporting services, or tracking pixels.
- **No network requests for transcription.** The only network activity is the one-time download of the WhisperKit model on first launch. After that, Murmur works fully offline.
- **No user accounts.** Murmur does not require sign-up, login, or any form of account creation.

## Keyboard Extension

Murmur includes a custom keyboard extension. The keyboard extension:

- Does **not** log keystrokes
- Does **not** transmit any typed or dictated text
- Uses the App Group shared container solely to pass transcribed text from the main app back to the keyboard — this data is stored temporarily on-device and automatically expires after 60 seconds
- Requires "Full Access" permission only for the App Group communication between the keyboard and the main app — no network access is used

## Data Storage

Transcribed text exists only in the app's active memory while you are using it. When you close the app, the text is gone. Murmur does not maintain any database, log files, or persistent storage of your content.

## Third-Party Services

Murmur uses no third-party services, SDKs, or APIs. The WhisperKit model runs locally on your device.

## Children's Privacy

Murmur does not collect any data from anyone, including children under 13.

## Changes to This Policy

If this policy changes, the updated version will be posted here with a new "Last updated" date.

## Contact

If you have questions about this privacy policy, please open an issue on the [Murmur GitHub repository](https://github.com/Johnnywang2001/Murmur).
