import 'dart:async';

import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:dart_style/dart_style.dart';
import 'package:mirror_builder/src/generator.dart';

/// Factory method following the Reflectable pattern, allowing configuration via `build.yaml`.
Builder mirrorBuilder(BuilderOptions options) {
  return MirrorBuilder(options);
}

/// A builder that generates mirror code for annotated classes.
class MirrorBuilder implements Builder {
  final BuilderOptions options;

  /// Creates a [MirrorBuilder].
  MirrorBuilder(this.options);

  @override
  Map<String, List<String>> get buildExtensions => const {
    '.dart': ['.mirror.dart'],
  };

  @override
  Future<void> build(BuildStep buildStep) async {
    var targetId = buildStep.inputId.toString();

    if (targetId.contains('.vm_test.') ||
        targetId.contains('.node_test.') ||
        targetId.contains('.browser_test.')) {
      return;
    }

    LibraryElement inputLibrary = await buildStep.inputLibrary;

    if (inputLibrary.entryPoint == null) {
      return;
    }

    log.info('Generating mirrors for: ${buildStep.inputId.path}');

    final inputId = buildStep.inputId;
    final outputId = inputId.changeExtension('.mirror.dart');

    try {
      String generatedSource = await MirrorGenerator().buildMirrorLibrary(
        buildStep,
        inputId,
        outputId,
        inputLibrary,
      );

      if (generatedSource.isEmpty) {
        log.warning('The generator ran on $inputId but produced no content.');
      } else {
        await buildStep.writeAsString(
          outputId,
          DartFormatter(
            languageVersion: DartFormatter.latestLanguageVersion,
            pageWidth: 1000,
          ).format(generatedSource),
        );
      }
    } catch (e, stack) {
      log.severe('Error generating mirrors for $inputId', e, stack);
    }
  }
}
