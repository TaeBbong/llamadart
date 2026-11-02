---
title: In-app Copilot example
sidebar_label: In-app Copilot
description: A Flutter budget app with an on-device copilot that reads and changes the app's data through its own functions as tools, with approval before deleting.
---

Path: `example/in_app_copilot` · Platforms: macOS 14.0+, iOS 16.4+, Android
10+ (API 29) · First-run download: Qwen3.5 4B (2.7 GB)

A Flutter budget app with a copilot that answers and acts through the app's
own functions. Ask *How much did I spend on delivery last month?*, *Cut my
delivery budget by 20%* or *Was any taxi ride charged twice? Delete the extra
one*: the model calls the app's tools, the budget bars and expense list
change as it works, and a deletion waits for your approval.

## Run

```bash
cd example/in_app_copilot
flutter pub get
flutter run -d macos   # or an iOS or Android device
```

## What it demonstrates

- An app's functions as [tools](../guides/tool-calling): six
  `ToolDefinition`s over the app's data, run by
  `ChatSession.sendWithTools` for up to six rounds.
- Recovery from bad arguments: a handler throws a message naming the valid
  values, and the tool loop hands it back to the model to retry.
- Human approval inside a handler: `delete_expenses` awaits a dialog before
  it changes anything.
- Live tool activity from `onMessageAdded`, and app widgets that listen to
  the app's data rather than to the copilot.
- Model size matters for an agent: Qwen3.5 4B chained calls such as
  `budget_status` then `set_budget` correctly, while 2B tried to delete
  unrelated expenses when asked to cut a budget.

## Headless runs

```bash
dart run bin/copilot.dart "How much did I spend on delivery last month?" \
  "Cut my delivery budget by 20%"
```

[`example/in_app_copilot/README.md`](https://github.com/leehack/llamadart/blob/main/example/in_app_copilot/README.md)
lists the measured requests and tool calls.

## Test

```bash
cd example/in_app_copilot
flutter test
```

The tests cover the ledger, each tool's results and error messages,
approval and refusal of a deletion, the system prompt's dates, and the page
against a fake copilot.
