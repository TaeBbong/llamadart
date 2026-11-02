# Privacy Guard

A Flutter app for macOS, iOS and Android that checks photos before you share
them. An on-device vision model finds ID cards, card numbers, names, phone
numbers, addresses, barcodes and other private details and boxes each one;
the app blacks them out, drops the file's metadata, GPS location included,
and hands the copies to the system share sheet. You can leave any box
visible. Checking a photo for private details is the one job you should not
send to a server, so the model runs on the device.

## How it works

- Photos come from the system photo picker (`image_picker`), which needs no
  photo library permission. It also turns HEIC into JPEG.
- `preparePhoto` (`lib/src/redaction.dart`) turns the photo upright, notes a
  GPS position in its metadata, and shrinks a 1,024-pixel copy for the model,
  on a background isolate.
- `PrivacyScanner` (`lib/src/scanner.dart`) sends that copy to
  `LlamaEngine.complete` with one tool, `report_private_details`, and
  `ToolChoice.required`. The call carries a list of findings, each with a
  kind, a label and a `[x1, y1, x2, y2]` box in a 0 to 1,000 grid, the
  grounding format Qwen vision models are trained on, and a one-sentence
  verdict.
- The handler keeps each finding with a usable box. `kind` is a plain
  string, not an enum: on Qwen3.5 2B a kind outside the list (`"date"`)
  failed the whole call's validation, and an unknown kind is still worth
  hiding.
- `redactPhoto` fills each box, grown by 1% of the image, with solid black,
  not blur, which can often be read back, and re-encodes the photo with no
  metadata.

Everything the model finds arrives in one call: the small Qwen3.5 models
make one call per reply, and their recurrent layers make a second round
evaluate the whole prompt, image included, again.

## Run

```bash
cd example/privacy_guard
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

Platform setup in this example: `NSPhotoLibraryUsageDescription` on iOS, which
`image_picker` requires, and the
`com.apple.security.files.user-selected.read-only` entitlement on macOS.

## Headless runs

`bin/scan.dart` checks image files the way the app does and, with `--out`,
writes the blacked-out copies:

```bash
dart run bin/scan.dart --size 2b --out redacted photo1.jpg photo2.jpg
```

On an Apple M4 Pro with Metal, four test photos (a mock Korean ID card on a
desk, a mock payment card, a parcel label with a name, phone number, address
and barcode, and a landscape), 5 to 10 s each:

| Model | ID card | Payment card | Parcel label | Landscape |
| --- | --- | --- | --- | --- |
| Qwen3.5 4B | whole card, within 1% of its edges, and its address | whole card, its name and expiry | name, phone number, address and barcode, each boxed tightly | safe |
| Qwen3.5 2B | whole card, as one box for every field | whole card, number, name and expiry | name, phone number, address and barcode, boxed loosely | safe |

Neither model boxed the parcel's printed tracking number on its own; the 4B
box around the barcode covered it.

2B boxes are not stable. On an iOS simulator (CPU, the same photos through
the system picker), 2B put all four ID card boxes over one part of the card
and left its registration number and address readable, and it left the
parcel's tracking number visible. 4B covered the whole card and the whole
label there too, in about 30 s a photo. Prefer `MODEL=4b` on phones that
have the memory for it.

## Test

```bash
flutter test
```
