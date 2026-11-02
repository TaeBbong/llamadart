import 'package:llamadart/llamadart.dart';

/// Reports load progress: a message and, while downloading, a fraction.
typedef LoadStatus = void Function(String message, double? fraction);

/// A Qwen3.5 GGUF and its vision projector, pinned to a revision.
class AgentModel {
  /// Creates a model from [modelFile] and [projectorFile] in [repoId].
  const AgentModel({
    required this.label,
    required this.repoId,
    required this.revision,
    required this.modelFile,
    required this.projectorFile,
  });

  /// Short name for the status line.
  final String label;

  /// Hugging Face repository.
  final String repoId;

  /// Commit the files are pinned to.
  final String revision;

  /// Quantized weights.
  final String modelFile;

  /// Vision projector.
  final String projectorFile;

  /// The weights as a model source.
  ModelSource get model => ModelSource.huggingFace(
    repoId: repoId,
    revision: revision,
    filePath: modelFile,
  );

  /// The projector as a model source, named after the model so the two
  /// sizes do not share a cache file name.
  ModelSource get projector => ModelSource.huggingFace(
    repoId: repoId,
    revision: revision,
    filePath: projectorFile,
    fileName: '${modelFile.split('-Q').first}-$projectorFile',
  );

  /// The weights with the projector when [vision], ready to load.
  LlamaModel load({bool vision = true}) =>
      LlamaModel(model, projector: vision ? projector : null);
}

/// Qwen3.5 2B, Q4_K_M (1.3 GB) and its F16 projector (668 MB), under
/// Apache 2.0.
const AgentModel qwen35Small = AgentModel(
  label: 'Qwen3.5 2B',
  repoId: 'unsloth/Qwen3.5-2B-GGUF',
  revision: 'f6d5376be1edb4d416d56da11e5397a961aca8ae',
  modelFile: 'Qwen3.5-2B-Q4_K_M.gguf',
  projectorFile: 'mmproj-F16.gguf',
);

/// Qwen3.5 4B, Q4_K_M (2.7 GB) and its F16 projector (672 MB), under
/// Apache 2.0.
const AgentModel qwen35Large = AgentModel(
  label: 'Qwen3.5 4B',
  repoId: 'unsloth/Qwen3.5-4B-GGUF',
  revision: 'e87f176479d0855a907a41277aca2f8ee7a09523',
  modelFile: 'Qwen3.5-4B-Q4_K_M.gguf',
  projectorFile: 'mmproj-F16.gguf',
);

/// The model `--dart-define=MODEL=2b` or `4b` names, or by default 2B on a
/// phone and 4B elsewhere.
AgentModel pickModel({required bool phone}) =>
    switch (const String.fromEnvironment('MODEL')) {
      '2b' => qwen35Small,
      '4b' => qwen35Large,
      _ => phone ? qwen35Small : qwen35Large,
    };

/// Loads [model] and checks that it can call tools and, when it has a
/// projector, read images. [label] names it in status messages and errors.
///
/// [cpu] keeps every layer on the CPU.
Future<LlamaEngine> loadAgentModel(
  LlamaModel model, {
  required String label,
  bool cpu = false,
  LoadStatus? onStatus,
}) async {
  onStatus?.call('Loading $label', null);
  final engine = await LlamaEngine.load(
    model,
    params: ModelParams(
      contextSize: 8192,
      preferredBackend: cpu ? GpuBackend.cpu : GpuBackend.auto,
      gpuLayers: cpu ? 0 : ModelParams.maxGpuLayers,
    ),
    onProgress: (p) => onStatus?.call(
      'Downloading $label: ${(p.receivedBytes / 1e6).round()}'
      '${p.totalBytes == null ? '' : ' of ${(p.totalBytes! / 1e6).round()}'}'
      ' MB',
      p.fraction,
    ),
  );
  try {
    final capabilities = await engine.capabilities;
    if (!capabilities.supportsToolCalling) {
      throw LlamaUnsupportedException(
        '$label cannot call tools on this backend.',
      );
    }
    if (model.projector != null && !capabilities.supportsVision) {
      throw LlamaUnsupportedException(
        'The $label projector does not provide image input on this '
        'backend.',
      );
    }
    return engine;
  } catch (_) {
    await engine.dispose();
    rethrow;
  }
}
