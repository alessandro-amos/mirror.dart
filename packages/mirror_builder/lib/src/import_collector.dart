import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';

/// Manages import prefixes to avoid conflicts in generated code.
class ImportCollector {
  final Map<String, String> _importUriToPrefix = {};
  final Set<String> _usedPrefixes = {};
  int _nextPrefixIndex = 0;
  final LibraryElement? entryPoint;
  final AssetId? outputId;

  /// Creates an [ImportCollector].
  ImportCollector(this.outputId, [this.entryPoint]);

  /// Returns a valid prefix for the given [library].
  ///
  /// If the library is already cached, returns the existing prefix.
  /// If it is the entrypoint, assigns 'p0'.
  /// Otherwise, assigns a new unique prefix 'pX'.
  String getPrefix(LibraryElement? library) {
    if (library == null || library.isDartCore) return '';

    final uri = library.firstFragment.source.uri.toString();

    if (_importUriToPrefix.containsKey(uri)) {
      final prefix = _importUriToPrefix[uri]!;
      _usedPrefixes.add(prefix);
      return '$prefix.';
    }

    if (entryPoint != null &&
        uri == entryPoint!.firstFragment.source.uri.toString()) {
      const prefix = 'p0';
      _usedPrefixes.add(prefix);
      _importUriToPrefix[entryPoint!.firstFragment.source.shortName] = prefix;
      return '$prefix.';
    }

    final prefix = 'p${_nextPrefixIndex++}';
    _importUriToPrefix[uri] = prefix;
    _usedPrefixes.add(prefix);
    return '$prefix.';
  }

  /// Returns the list of import statements to be written to the generated file.
  List<String> getImports() {
    return _importUriToPrefix.entries
        .where((entry) => _usedPrefixes.contains(entry.value))
        .map((entry) => "import '${entry.key}' as ${entry.value};")
        .toList()
      ..sort();
  }
}
