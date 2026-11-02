---
title: Privacy Guard example
sidebar_label: Privacy Guard
description: A Flutter app in which an on-device Qwen3.5 vision model boxes ID cards, card numbers, addresses and other private details in photos through a tool call, and the app blacks them out and strips metadata before sharing.
---

Path: `example/privacy_guard` · Platforms: macOS 14.0+, iOS 16.4+, Android
10+ (API 29) · First-run download: Qwen3.5 4B (3.4 GB with its projector), or
2B (2.0 GB) on phones

A Flutter app that checks photos before you share them. An on-device vision
model finds ID cards, card numbers, names, phone numbers, addresses, barcodes
and other private details and boxes each one; the app blacks them out, drops
the file's metadata, GPS location included, and hands the copies to the
system share sheet. You can leave any box visible.

[Demo video][demo] (45 s): Qwen3.5 4B, built with `--dart-define=MODEL=4b`, on
the iOS Simulator's CPU; the checking is sped up 8×.

[demo]: https://github.com/leehack/llamadart/blob/main/example/privacy_guard/doc/demo.mp4

## Run

```bash
cd example/privacy_guard
flutter pub get
flutter run -d macos   # or an iOS or Android device
```

Photos come from the system photo picker, so the app needs no photo library
permission. Pass `--dart-define=MODEL=2b` or `MODEL=4b` to choose the model.

## What it demonstrates

- Visual grounding through a [tool call](../guides/tool-calling): one
  `report_private_details` call carries every finding with a
  `[x1, y1, x2, y2]` box in a 0 to 1,000 grid, the format Qwen vision models
  are trained on.
- A schema that tolerates a small model: `kind` is a plain string, because
  a value outside an enum failed the whole call's validation on Qwen3.5 2B.
- [Image input](../guides/multimodal) prepared off the UI isolate: the photo
  turned upright and shrunk to 1,024 pixels for the model.
- Redaction that holds up: solid fill rather than blur, a margin around each
  box, and re-encoding without metadata.

## Headless runs

```bash
dart run bin/scan.dart --size 2b --out redacted photo1.jpg photo2.jpg
```

[`example/privacy_guard/README.md`](https://github.com/leehack/llamadart/blob/main/example/privacy_guard/README.md)
has the measured results for both model sizes.

## Test

```bash
cd example/privacy_guard
flutter test
```

The tests cover the tool's handling of findings and boxes, the black fill and
metadata removal on real JPEGs, the check queue (order, failures, photos
added mid-run), the shown and hidden findings, and the pages against fake
reports.
