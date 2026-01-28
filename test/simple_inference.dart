import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:llamadart/src/loader.dart';

void main() {
  print('Starting inference test...');

  // 1. Initialize Backend
  llama.llama_backend_init();
  llama.llama_log_set(nullptr, nullptr);
  print('Backend initialized and log set.');

  // 2. Load Model
  final modelPath = 'models/stories15M.gguf';
  final modelPathPtr = modelPath.toNativeUtf8();

  // Use default model params
  final modelParams = llama.llama_model_default_params();
  final model =
      llama.llama_model_load_from_file(modelPathPtr.cast(), modelParams);

  malloc.free(modelPathPtr);

  if (model == nullptr) {
    print('Error: Failed to load model from $modelPath');
    exit(1);
  }
  print('Model loaded successfully.');

  // 3. Create Context
  final ctxParams = llama.llama_context_default_params();
  // Set context size to something small for testing
  ctxParams.n_ctx = 512;

  final ctx = llama.llama_init_from_model(model, ctxParams);
  if (ctx == nullptr) {
    print('Error: Failed to create context');
    exit(1);
  }
  print('Context created.');

  // 4. Create Sampler
  final samplerChainParams = llama.llama_sampler_chain_default_params();
  final sampler = llama.llama_sampler_chain_init(samplerChainParams);
  llama.llama_sampler_chain_add(sampler, llama.llama_sampler_init_greedy());

  // 5. Tokenize Prompt
  final prompt = "Once upon a time";
  final promptPtr = prompt.toNativeUtf8();

  // Allocate memory for tokens
  final nPromptTokensAlloc = prompt.length + 1;
  final tokensPtr = malloc<Int32>(nPromptTokensAlloc);

  // Get vocab for tokenization
  final vocab = llama.llama_model_get_vocab(model);

  // Use helper if available, or llama_tokenize
  // llama_tokenize(vocab, text, text_len, tokens, n_max_tokens, add_special, parse_special)
  final nTokens = llama.llama_tokenize(
      vocab,
      promptPtr.cast(),
      prompt.length,
      tokensPtr,
      nPromptTokensAlloc,
      true, // add_bos
      false // special
      );

  malloc.free(promptPtr);

  if (nTokens < 0) {
    print('Error: Tokenization failed');
    exit(1);
  }
  print('Tokenized prompt: $nTokens tokens.');

  // 6. Create Batch
  // llama_batch_get_one(token, n_tokens, pos, seq_id)
  // We need to decode the whole prompt first
  final batch = llama.llama_batch_init(512, 0, 1); // n_tokens, embd, n_seq_max

  // Prepare batch with prompt tokens
  // We manually populate the C struct arrays
  batch.n_tokens = nTokens;
  for (var i = 0; i < nTokens; i++) {
    batch.token[i] = tokensPtr[i];
    batch.pos[i] = i;
    batch.n_seq_id[i] = 1;
    batch.seq_id[i][0] = 0; // seq 0
    batch.logits[i] = (i == nTokens - 1) ? 1 : 0; // Logits only for last
  }

  // 7. Decode Prompt
  if (llama.llama_decode(ctx, batch) != 0) {
    print('Error: llama_decode failed');
    exit(1);
  }
  print('Prompt decoded.');

  // 8. Generate Loop
  // int currentToken = tokensPtr[nTokens - 1]; // Start with last prompt token (unused)

  print('Generating: $prompt');

  for (int i = 0; i < 10; i++) {
    // Sample next token
    // id = llama_sampler_sample(sampler, ctx, idx)
    // idx is usually -1 or the batch index where logits are valid?
    // In new API: llama_sampler_sample(sampler, ctx, batch_idx)
    // Since we decoded batch where logits[nTokens-1] was true, the index is nTokens-1?
    // Wait, usually batch.logits index needs to be checked.

    final newTokenId =
        llama.llama_sampler_sample(sampler, ctx, batch.n_tokens - 1);

    // Check if EOG
    if (llama.llama_vocab_is_eog(
        llama.llama_model_get_vocab(model), newTokenId)) {
      print(' [END]');
      break;
    }

    // Convert to text
    // llama_token_to_piece(vocab, token, buf, size, lstrip, special)
    // We need a buffer.
    final buf = malloc<Int8>(256);
    final n = llama.llama_token_to_piece(
        llama.llama_model_get_vocab(model),
        newTokenId,
        buf.cast(),
        256,
        0, // lstrip (bool in C, int here?) usually works
        false // special
        );

    if (n < 0) {
      // Error or buffer too small
    } else {
      final str = buf.cast<Utf8>().toDartString(length: n);
      stdout.write(str);
    }
    malloc.free(buf);

    // Prepare next batch (single token)
    batch.n_tokens = 1;
    batch.token[0] = newTokenId;
    batch.pos[0] = nTokens + i; // increment pos
    batch.n_seq_id[0] = 1;
    batch.seq_id[0][0] = 0;
    batch.logits[0] = 1; // Always need logits for next sample

    if (llama.llama_decode(ctx, batch) != 0) {
      print('Decode failed during generation');
      break;
    }
  }

  print('\nDone.');

  // Cleanup
  malloc.free(tokensPtr);
  llama.llama_batch_free(batch);
  llama.llama_sampler_free(sampler);
  llama.llama_free(ctx);
  llama.llama_model_free(model);
  llama.llama_backend_free();
}
