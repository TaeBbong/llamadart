# Screenshot Inbox

A Flutter app for macOS, iOS and Android that reads your newest screenshots
with an on-device vision model and turns each into one-tap follow-ups: a
calendar event for a dated poster or a coupon's expiry, a maps search for a
place, a copied coupon code or tracking number. You mark the ones you are done
with and delete them together. No image leaves the device.

The model plans and the user acts: it proposes follow-ups through a tool
call, and each runs only through the platform's own UI when you tap it (the
system event sheet, the maps app, the clipboard). Deleting goes through the
system's confirmation.

## How it works

- `PhotoLibrary` (`lib/src/library.dart`) reads the newest 400 images through
  `photo_manager` and keeps the screenshots: on iOS and macOS by the
  `photoScreenshot` media subtype, on Android by a `Screenshots` folder. Each
  is read as a JPEG at most 1,024 pixels on its long edge.
- `ScreenshotTriager` (`lib/src/triage.dart`) sends the screenshot and a
  system prompt with today's date and the user's language to
  `LlamaEngine.complete` with one tool, `sort_screenshot`, and
  `ToolChoice.required`. The call carries the kind, a summary and at most one
  event, place and text to copy, as flat optional strings that every tool
  format can parse.
- The handler turns those strings into `InboxAction`s and drops what it
  cannot use, such as a date that is not `YYYY-MM-DD`. An event with a
  location and no place also gets a maps search.
- `runAction` (`lib/src/actions.dart`) runs a tapped action: `add_2_calendar`
  on iOS and Android, an `.ics` file that Calendar imports on macOS, a `geo:`
  link on Android and Apple Maps elsewhere, and the clipboard.

### Why one call per screenshot

Qwen3.5 has recurrent layers, so llama.cpp cannot reuse part of a cached
prompt: a second round after a tool result evaluates the whole prompt, image
included, again. With one tool per follow-up, a screenshot took three rounds
and 18 s on the 4B model; with one call it takes 4 to 7 s. The small Qwen3.5
models also made one call per reply here, even with `parallelToolCalls`.

## Run

```bash
cd example/screenshot_inbox
flutter pub get
flutter run -d macos   # or an iOS or Android device
```

The app downloads the model on first launch and keeps it in the llamadart
model cache. Phones get Qwen3.5 2B and other platforms 4B; pass
`--dart-define=MODEL=2b` or `MODEL=4b` to choose.

| Model | Files | Source |
| --- | --- | --- |
| Qwen3.5 2B | `Qwen3.5-2B-Q4_K_M.gguf` (1.3 GB) and `mmproj-F16.gguf` (668 MB), under Apache 2.0 | [`unsloth/Qwen3.5-2B-GGUF`](https://huggingface.co/unsloth/Qwen3.5-2B-GGUF) at `f6d5376be1edb4d416d56da11e5397a961aca8ae` |
| Qwen3.5 4B | `Qwen3.5-4B-Q4_K_M.gguf` (2.7 GB) and `mmproj-F16.gguf` (672 MB), under Apache 2.0 | [`unsloth/Qwen3.5-4B-GGUF`](https://huggingface.co/unsloth/Qwen3.5-4B-GGUF) at `e87f176479d0855a907a41277aca2f8ee7a09523` |

The model runs on the GPU, or on Android on the CPU.

Platform setup in this example:

- iOS: `NSPhotoLibraryUsageDescription`, plus `NSCalendarsUsageDescription`,
  `NSCalendarsWriteOnlyAccessUsageDescription` and
  `NSContactsUsageDescription` for the system event sheet.
- macOS: the `com.apple.security.personal-information.photos-library`
  entitlement and `NSPhotoLibraryUsageDescription`.
- Android: `READ_MEDIA_IMAGES` (`READ_EXTERNAL_STORAGE` up to API 32), and
  `<queries>` for the calendar insert intent and `geo:` links.

## Headless runs

`bin/triage.dart` sorts image files the way the app does and prints the
proposals:

```bash
dart run bin/triage.dart --size 2b --language ko-KR shot1.png shot2.png
dart run bin/triage.dart --model Qwen3.5-4B-Q4_K_M.gguf \
  --projector mmproj-F16.gguf shot1.png
```

On an Apple M4 Pro with Metal, four test screenshots (an English meetup
poster, a Korean coupon, a Korean parcel notice and a meme):

| Model | Time per screenshot | Kinds right | Follow-ups |
| --- | --- | --- | --- |
| Qwen3.5 4B | 3.9 to 7.1 s | 4 of 4 | event, map, coupon code with its expiry, tracking number with its arrival day; none for the meme |
| Qwen3.5 2B | 2.2 to 5.4 s | 4 of 4 | the same, without the coupon's expiry and the parcel's arrival day |

At 768 pixels instead of 1,024, the 4B model misread `WINTER5K-82QX` as
`WINTER5K-820X`, and was no faster.

## Test

```bash
flutter test
```
