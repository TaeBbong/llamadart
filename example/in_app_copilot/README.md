# In-app Copilot

A Flutter budget app for macOS, iOS and Android with a copilot that answers
and acts through the app's own functions. Ask *How much did I spend on
delivery last month?*, *Cut my delivery budget by 20%* or *Was any taxi ride
charged twice? Delete the extra one*: the model calls the app's tools, the
budget bars and expense list change as it works, and a deletion waits for
your approval. It shows how to add an on-device agent to an existing app.

## How it works

- `Ledger` (`lib/src/ledger.dart`) is the app's data: expenses and a monthly
  budget per category, in plain Dart. `Ledger.sample` fills it with last
  month and this month, including a taxi ride charged twice.
- `ledgerTools` (`lib/src/copilot_tools.dart`) exposes six of its functions as
  `ToolDefinition`s: `find_expenses`, `spending_summary`, `budget_status`,
  `add_expense`, `set_budget` and `delete_expenses`. Bad arguments throw a
  message such as `Unknown category "coffee". Use one of food, ...`, which
  the tool loop hands back to the model to retry. Categories are strings
  checked by the handler rather than schema enums, because a value outside
  an enum fails the whole call before the model sees why. A merchant name
  that matches nothing returns the merchant names that do match the other
  filters: asked in Korean, 4B searched for `택시`, then retried with `Taxi`.
- `delete_expenses` awaits a `confirm` callback; the app shows a dialog
  listing what would be deleted.
- `Copilot` (`lib/src/copilot.dart`) keeps one `ChatSession` and answers each
  request with `sendWithTools`, at most six rounds. `onMessageAdded` reports
  each call and its result, which the panel shows as they happen.
- The app's widgets listen to the ledger, not to the copilot, so a change
  made through a tool appears the same way as one made by hand.

## Run

```bash
cd example/in_app_copilot
flutter pub get
flutter run -d macos   # or an iOS or Android device
```

The app downloads Qwen3.5 4B (`Qwen3.5-4B-Q4_K_M.gguf`, 2.7 GB, under
Apache 2.0, from
[`unsloth/Qwen3.5-4B-GGUF`](https://huggingface.co/unsloth/Qwen3.5-4B-GGUF)
at `e87f176479d0855a907a41277aca2f8ee7a09523`) on first launch and keeps it in
the llamadart model cache. It runs on the GPU, or on Android on the CPU.
`--dart-define=MODEL=2b` loads Qwen3.5 2B instead (1.3 GB), which is not
reliable here: asked to cut a budget, it tried to delete four unrelated
expenses and answered in Chinese.

## Headless runs

`bin/copilot.dart` sends requests, one per argument, in one conversation over
the sample ledger, and prints each tool call:

```bash
dart run bin/copilot.dart "How much did I spend on delivery last month?" \
  "Cut my delivery budget by 20%"
dart run bin/copilot.dart --yes "택시 중복 결제된 거 있으면 하나 지워줘"
```

On an Apple M4 Pro with Metal, Qwen3.5 4B answered each of these in 6 to
12 s:

| Request | Tool calls |
| --- | --- |
| 이번 달 배달비 얼마 썼어? | `find_expenses(category: delivery, from, to)` |
| 지난달에 어디에 제일 많이 썼어? | `spending_summary(from, to)` |
| How much did I spend on coffee last month? | `spending_summary(from, to)` |
| 배달 예산 넘었으면 다음 달부터 예산을 20% 줄여줘 | `budget_status()`, then `set_budget(category: delivery, amount: 96000)` |
| 택시 중복 결제된 거 있으면 하나 지워줘 | `find_expenses(category: transport, ...)`, then `delete_expenses(ids: [113])` on one of the two rides |
| 오늘 점심 김밥집에서 9000원 썼어 | `add_expense(amount: 9000, category: food, merchant: 김밥집, date: today)` |

It cut the delivery budget although this month's delivery spending was
still under it; last month's was well over.

## Test

```bash
flutter test
```
