---
title: Screenshot Inbox example
sidebar_label: Screenshot Inbox
description: A Flutter app in which an on-device Qwen3.5 vision model sorts your screenshots through a tool call and proposes calendar events, maps searches and codes to copy, which run with one tap.
---

Path: `example/screenshot_inbox` · Platforms: macOS 14.0+, iOS 16.4+,
Android 10+ (API 29) · First-run download: Qwen3.5 4B (3.4 GB with its
projector), or 2B (2.0 GB) on phones

A Flutter app that reads your newest screenshots with an on-device vision
model and turns each into one-tap follow-ups: a calendar event for a dated
poster or a coupon's expiry, a maps search for a place, a copied coupon code
or tracking number. You mark the ones you are done with and delete them
together. No image leaves the device.

[Demo video][demo] (35 s): Qwen3.5 4B, built with `--dart-define=MODEL=4b`, on
the iOS Simulator's CPU; the sorting is sped up 8×. On the same simulator, 2B
gave the parcel notice a calendar event and a maps search for the product
name.

[demo]: https://github.com/leehack/llamadart/blob/main/example/screenshot_inbox/doc/demo.mp4

## Run

```bash
cd example/screenshot_inbox
flutter pub get
flutter run -d macos   # or an iOS or Android device
```

Pass `--dart-define=MODEL=2b` or `MODEL=4b` to choose the model. The app
needs photo library access; its README lists the platform setup.

## What it demonstrates

- [Image input](../guides/multimodal) and a
  [tool call](../guides/tool-calling) in one request: `LlamaEngine.complete`
  with a GGUF projector, one `sort_screenshot` tool and
  `ToolChoice.required`.
- A tool whose handler turns the model's strings into typed proposals and
  drops what it cannot use, such as a malformed date.
- Planning by the model, acting by the user: each proposal runs only when
  tapped, through the system event sheet, the maps app or the clipboard, and
  deletion goes through the system's confirmation.
- One call per screenshot instead of one tool per follow-up. Qwen3.5 has
  recurrent layers, so a second round after a tool result evaluates the
  whole prompt, image included, again: three rounds took 18 s per screenshot
  on the 4B model, one call 4 to 7 s on an Apple M4 Pro.

## Headless runs

```bash
dart run bin/triage.dart --size 2b --language ko-KR shot1.png shot2.png
```

[`example/screenshot_inbox/README.md`](https://github.com/leehack/llamadart/blob/main/example/screenshot_inbox/README.md)
has the measured results for both model sizes.

## Test

```bash
cd example/screenshot_inbox
flutter test
```

The tests cover the tool's argument handling, event dates and times, the
`.ics` file and maps links, the inbox's sorting run (order, failures, stop,
retry) and deletion, and the page against fake triages.
