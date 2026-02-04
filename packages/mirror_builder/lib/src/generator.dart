import 'dart:async';
import 'dart:collection';

import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:glob/glob.dart';

import 'annotation_extractor.dart';
import 'import_collector.dart';

class MirrorGenerator {
  MirrorGenerator();

  Future<String> buildMirrorLibrary(
      BuildStep buildStep,
      AssetId inputId,
      AssetId outputId,
      LibraryElement inputLibrary,
      ) async {
    final importCollector = ImportCollector(outputId, inputLibrary);
    final allAssets = await buildStep.findAssets(Glob('lib/**.dart')).toList();
    final extraLibraries = <LibraryElement>[];

    for (var asset in allAssets) {
      if (asset == inputId) continue;
      if (asset.path.endsWith('.mirror.dart') ||
          asset.path.endsWith('.g.dart')) {
        continue;
      }
      try {
        if (await buildStep.resolver.isLibrary(asset)) {
          final lib = await buildStep.resolver.libraryFor(asset);
          extraLibraries.add(lib);
        }
      } catch (e) {}
    }

    return _InternalGenerator(
      inputLibrary,
      outputId,
      importCollector,
      extraLibraries,
      buildStep.resolver,
    ).generate();
  }
}

class _TypeRegistry {
  final List<DartType> _types = [];
  final Map<String, int> _indexMap = {};

  int register(DartType type) {
    if (type is DynamicType || type is VoidType) {
      return _registerCore(type);
    }
    String key = _uniqueKey(type);

    if (_indexMap.containsKey(key)) {
      return _indexMap[key]!;
    }

    if (type is InterfaceType) {
      for (final arg in type.typeArguments) {
        register(arg);
      }
    }

    _types.add(type);
    final index = _types.length - 1;
    _indexMap[key] = index;
    return index;
  }

  int _registerCore(DartType type) {
    final key = type is DynamicType ? 'dynamic' : 'void';
    if (_indexMap.containsKey(key)) return _indexMap[key]!;
    _types.add(type);
    final index = _types.length - 1;
    _indexMap[key] = index;
    return index;
  }

  String _uniqueKey(DartType type) {
    if (type is InterfaceType) {
      final lib = type.element.library.firstFragment.source.uri.toString();
      final args = type.typeArguments.map(_uniqueKey).join(',');
      final suffix =
      type.nullabilitySuffix == NullabilitySuffix.question ? '?' : '';
      return '$lib|${type.element.name}<$args>$suffix';
    }
    return type.toString();
  }

  List<DartType> get types => _types;

  List<int> getTypeArgumentsIndices(DartType type) {
    if (type is InterfaceType) {
      return type.typeArguments.map((t) => register(t)).toList();
    }
    return [];
  }
}

class _AccessorRegistry {
  final Set<String> _getters = {};
  final Set<String> _setters = {};
  final Set<String> _methods = {};

  void registerGetter(String name) => _getters.add(name);

  void registerSetter(String name) {
    final normalized =
    name.endsWith('=') ? name.substring(0, name.length - 1) : name;
    _setters.add(normalized);
  }

  void registerMethod(String name) => _methods.add(name);

  void writeTo(StringBuffer buffer) {
    buffer.writeln("final _getters = <String, dynamic Function(dynamic)>{");
    for (final name in _getters) {
      buffer.writeln("  r'$name': (dynamic i) => i.$name,");
    }
    buffer.writeln("};");

    buffer.writeln(
      "final _setters = <String, void Function(dynamic, dynamic)>{",
    );
    for (final name in _setters) {
      buffer.writeln("  r'$name': (dynamic i, dynamic v) => i.$name = v,");
    }
    buffer.writeln("};");

    buffer.writeln("final _methods = <String, dynamic Function(dynamic)>{");
    for (final name in _methods) {
      buffer.writeln("  r'$name': (dynamic i) => i.$name,");
    }
    buffer.writeln("};");
  }
}

class _InternalGenerator {
  final LibraryElement entryPoint;
  final AssetId? outputId;
  final ImportCollector _imports;
  final List<LibraryElement> _extraLibraries;
  final Resolver _resolver;
  late final _TypeRegistry _typeRegistry;
  late final _AccessorRegistry _accessorRegistry;

  _InternalGenerator(
      this.entryPoint,
      this.outputId,
      this._imports,
      this._extraLibraries,
      this._resolver,
      ) {
    _typeRegistry = _TypeRegistry();
    _accessorRegistry = _AccessorRegistry();
  }

  Future<String> generate() async {
    final initialLibraries = _getTransitiveLibraries(entryPoint);
    initialLibraries.addAll(_extraLibraries);

    final allLibraries = _expandLibrariesBasedOnUsage(initialLibraries);

    final mirrorClasses = <ClassElement, DartObject>{};
    final mirrorEnums = <EnumElement, DartObject>{};
    final mirrorFunctions = <FunctionTypedElement, DartObject>{};

    for (final lib in allLibraries) {
      if (lib.isDartCore || lib.isInSdk) continue;

      for (final clazz in lib.classes) {
        final mirrorAnnotation = _findMirrorsAnnotation(clazz);
        if (mirrorAnnotation != null) {
          mirrorClasses[clazz] = mirrorAnnotation;
          _preRegisterTypes(clazz, mirrorAnnotation);
        }
      }
      for (final enumz in lib.enums) {
        final mirrorAnnotation = _getMirrorsAnnotation(enumz);
        if (mirrorAnnotation != null) {
          mirrorEnums[enumz] = mirrorAnnotation;
          _typeRegistry.register(enumz.thisType);
        }
      }
      for (final func in lib.topLevelFunctions) {
        final mirrorAnnotation = _getMirrorsAnnotation(func);
        if (mirrorAnnotation != null) {
          mirrorFunctions[func] = mirrorAnnotation;
          _typeRegistry.register(func.returnType);
          for (final p in func.formalParameters) {
            _typeRegistry.register(p.type);
          }
        }
      }
    }

    final classesBlock = StringBuffer();
    for (final entry in mirrorClasses.entries) {
      await _generateClassMirrorEntry(entry.key, entry.value, classesBlock);
    }

    final enumsBlock = StringBuffer();
    for (final entry in mirrorEnums.entries) {
      await _generateEnumMirrorEntry(entry.key, entry.value, enumsBlock);
    }

    final functionsBlock = StringBuffer();
    for (final entry in mirrorFunctions.entries) {
      await _generateFunctionMirrorEntry(
        entry.key,
        entry.value,
        functionsBlock,
      );
    }

    final initBuffer = StringBuffer();
    initBuffer.writeln("\nvoid initializeMirrors() {");

    _writeTypeTable(initBuffer);
    _accessorRegistry.writeTo(initBuffer);

    initBuffer.writeln("  m.types = _types;");

    if (classesBlock.isNotEmpty) {
      initBuffer.writeln("  m.classesMap = {");
      initBuffer.write(classesBlock);
      initBuffer.writeln("  };");
    } else {
      initBuffer.writeln("  m.classesMap = {};");
    }

    if (enumsBlock.isNotEmpty) {
      initBuffer.writeln("  m.enumsMap = {");
      initBuffer.write(enumsBlock);
      initBuffer.writeln("  };");
    } else {
      initBuffer.writeln("  m.enumsMap = {};");
    }

    if (functionsBlock.isNotEmpty) {
      initBuffer.writeln("  m.functionsMap = {");
      initBuffer.write(functionsBlock);
      initBuffer.writeln("  };");
    } else {
      initBuffer.writeln("  m.functionsMap = {};");
    }

    initBuffer.writeln("  m.gettersInvokers = _getters;");
    initBuffer.writeln("  m.settersInvokers = _setters;");
    initBuffer.writeln("  m.methodsInvokers = _methods;");

    initBuffer.writeln("}");

    final finalBuffer = StringBuffer();
    _writeHeader(finalBuffer);
    finalBuffer.write(initBuffer);

    return finalBuffer.toString();
  }

  Set<LibraryElement> _expandLibrariesBasedOnUsage(
      Set<LibraryElement> initial) {
    final visited = {...initial};
    final queue = Queue<LibraryElement>.from(initial);

    void collectTypeLibrary(DartType? type) {
      if (type == null) return;
      if (type is InterfaceType) {
        final lib = type.element.library;
        if (!lib.isDartCore && !lib.isInSdk && !visited.contains(lib)) {
          visited.add(lib);
          queue.add(lib);
        }
        for (var arg in type.typeArguments) {
          collectTypeLibrary(arg);
        }
      }
    }

    while (queue.isNotEmpty) {
      final lib = queue.removeFirst();
      if (lib.isDartCore || lib.isInSdk) continue;

      for (final clazz in lib.classes) {
        {
          for (var field in clazz.fields) {
            collectTypeLibrary(field.type);
          }

          for (var method in clazz.methods) {
            collectTypeLibrary(method.returnType);
            for (var param in method.formalParameters) {
              collectTypeLibrary(param.type);
            }
          }

          for (var ctor in clazz.constructors) {
            for (var param in ctor.formalParameters) {
              collectTypeLibrary(param.type);
            }
          }
        }
      }

      for (final imported in lib.fragments
          .map((f) => f.importedLibraries)
          .expand((x) => x)
          .toList()) {
        if (!imported.isDartCore &&
            !imported.isInSdk &&
            !visited.contains(imported)) {
          visited.add(imported);
          queue.add(imported);
        }
      }

      for (final exported in lib.exportedLibraries) {
        if (!exported.isDartCore &&
            !exported.isInSdk &&
            !visited.contains(exported)) {
          visited.add(exported);
          queue.add(exported);
        }
      }
    }
    return visited;
  }

  List<FieldElement> _getFields(ClassElement element) {
    final map = <String, FieldElement>{};
    for (final type in element.allSupertypes) {
      if (type.isDartCoreObject) continue;
      for (final field in type.element.fields) {
        if (!field.isStatic && !map.containsKey(field.displayName)) {
          map[field.displayName] = field;
        }
      }
    }
    for (final field in element.fields) {
      map[field.displayName] = field;
    }
    return map.values.toList();
  }

  List<PropertyAccessorElement> _getGetters(ClassElement element) {
    final map = <String, PropertyAccessorElement>{};
    for (final type in element.allSupertypes) {
      if (type.isDartCoreObject) continue;
      for (final getter in type.element.getters) {
        if (!getter.isStatic && !map.containsKey(getter.displayName)) {
          map[getter.displayName] = getter;
        }
      }
    }
    for (final getter in element.getters) {
      map[getter.displayName] = getter;
    }
    return map.values.toList();
  }

  List<PropertyAccessorElement> _getSetters(ClassElement element) {
    final map = <String, PropertyAccessorElement>{};
    for (final type in element.allSupertypes) {
      if (type.isDartCoreObject) continue;
      for (final setter in type.element.setters) {
        if (!setter.isStatic && !map.containsKey(setter.displayName)) {
          map[setter.displayName] = setter;
        }
      }
    }
    for (final setter in element.setters) {
      map[setter.displayName] = setter;
    }
    return map.values.toList();
  }

  List<MethodElement> _getMethods(ClassElement element) {
    final map = <String, MethodElement>{};
    for (final type in element.allSupertypes) {
      if (type.isDartCoreObject) continue;
      for (final method in type.element.methods) {
        if (!method.isStatic && !map.containsKey(method.displayName)) {
          map[method.displayName] = method;
        }
      }
    }
    for (final method in element.methods) {
      map[method.displayName] = method;
    }
    return map.values.toList();
  }

  void _preRegisterTypes(ClassElement element, DartObject annotation) {
    _typeRegistry.register(element.thisType);
    final capabilities = _parseCapabilities(annotation);

    if (capabilities.contains('fields')) {
      final fields = _getFields(element);
      for (final field in fields) {
        if (!field.isPrivate && !field.isStatic) {
          _typeRegistry.register(field.type);
          _accessorRegistry.registerGetter(field.displayName);
          if (!field.isFinal) {
            _accessorRegistry.registerSetter(field.displayName);
          }
        }
      }
    }
    if (capabilities.contains('methods')) {
      final methods = _getMethods(element);
      for (final m in methods) {
        if (!m.isPrivate && !m.isStatic && !m.isOperator) {
          _typeRegistry.register(m.returnType);
          for (final p in m.formalParameters) {
            _typeRegistry.register(p.type);
          }
          _accessorRegistry.registerMethod(m.displayName);
        }
      }
    }
    if (capabilities.contains('getters')) {
      final getters = _getGetters(element);
      for (final g in getters) {
        if (!g.isPrivate && !g.isStatic && !g.isSynthetic) {
          _typeRegistry.register(g.returnType);
          _accessorRegistry.registerGetter(g.displayName);
        }
      }
    }
    if (capabilities.contains('setters')) {
      final setters = _getSetters(element);
      for (final s in setters) {
        if (!s.isPrivate && !s.isStatic && !s.isSynthetic) {
          _typeRegistry.register(s.formalParameters.first.type);
          _accessorRegistry.registerSetter(s.displayName);
        }
      }
    }
    if (capabilities.contains('constructors')) {
      for (final c in element.constructors) {
        if (!c.isPrivate) {
          for (final p in c.formalParameters) {
            _typeRegistry.register(p.type);
          }
        }
      }
    }
  }

  void _writeHeader(StringBuffer buffer) {
    buffer.writeln("// dart format width=10000");
    buffer.writeln("// GENERATED CODE - DO NOT MODIFY BY HAND");
    buffer.writeln("// ignore_for_file: type=lint");
    buffer.writeln("import 'package:mirror/mirror.dart' as m;");

    for (final import in _imports.getImports()) {
      buffer.writeln(import);
    }
  }

  void _writeTypeTable(StringBuffer buffer) {
    buffer.writeln("\nfinal List<m.TypeMirror<dynamic>> _types = [");
    for (final type in _typeRegistry.types) {
      _writeTypeMirrorInstance(type, buffer);
      buffer.writeln(",");
    }
    buffer.writeln("]; \n");
  }

  void _writeTypeMirrorInstance(DartType type, StringBuffer buffer) {
    if (type is InterfaceType) {
      final qualifiedType = _getQualifiedTypeString(type);
      final indices = _typeRegistry.getTypeArgumentsIndices(type);
      final indicesStr =
      indices.isEmpty ? '<int>[]' : '<int>[${indices.join(', ')}]';
      buffer.write(
        "m.type<$qualifiedType>($indicesStr${type.nullabilitySuffix == NullabilitySuffix.question ? ', true' : ''})",
      );
    } else {
      if (type is VoidType) {
        buffer.write("m.type<void>(<int>[])");
      } else {
        buffer.write("m.type<dynamic>(<int>[])");
      }
    }
  }

  Future<void> _generateClassMirrorEntry(
      ClassElement element,
      DartObject annotation,
      StringBuffer buffer,
      ) async {
    final capabilities = _parseCapabilities(annotation);
    final typeIndex = _typeRegistry.register(element.thisType);
    final className = element.displayName;

    buffer.write(
      "    _types[$typeIndex].type: m.ClassMirror('$className', $typeIndex, ",
    );
    await _writeMetadata(element, buffer);
    buffer.write(", ");

    if (capabilities.contains('fields')) {
      buffer.write("<List<dynamic>>[");
      final fields = _getFields(element);
      for (final field in fields) {
        if (field.isPrivate || field.isStatic) continue;
        await _generateCompactField(field, buffer);
      }
      buffer.write("], ");
    } else {
      buffer.write("null, ");
    }

    if (capabilities.contains('getters')) {
      buffer.write("<List<dynamic>>[");
      final getters = _getGetters(element);
      for (final getter in getters) {
        if (!getter.isPrivate && !getter.isStatic && !getter.isSynthetic) {
          await _generateCompactGetter(getter, buffer);
        }
      }
      buffer.write("], ");
    } else {
      buffer.write("null, ");
    }

    if (capabilities.contains('setters')) {
      buffer.write("<List<dynamic>>[");
      final setters = _getSetters(element);
      for (final setter in setters) {
        if (!setter.isPrivate && !setter.isStatic && !setter.isSynthetic) {
          await _generateCompactSetter(setter, buffer);
        }
      }
      buffer.write("], ");
    } else {
      buffer.write("null, ");
    }

    if (capabilities.contains('methods')) {
      buffer.write("<List<dynamic>>[");
      final methods = _getMethods(element);
      for (final method in methods) {
        if (method.isPrivate || method.isStatic || method.isOperator) continue;
        await _generateCompactMethod(method, buffer);
      }
      buffer.write("], ");
    } else {
      buffer.write("null, ");
    }

    if (capabilities.contains('constructors') && !element.isAbstract) {
      buffer.write("<List<dynamic>>[");
      for (final ctor in element.constructors) {
        if (ctor.isPrivate) continue;
        await _generateCompactConstructor(ctor, buffer);
      }
      buffer.write("], ");
    } else {
      buffer.write("null");
    }

    buffer.writeln("),");
  }

  Future<void> _generateCompactField(
      FieldElement field,
      StringBuffer buffer,
      ) async {
    final typeIdx = _typeRegistry.register(field.type);
    buffer.write(
      "<dynamic>['${field.displayName}', $typeIdx, ${field.isFinal}, ${field.isStatic}, ",
    );

    Element elementToUse = field.nonSynthetic;
    if (field.metadata.annotations.isEmpty) {
      if (field.getter != null &&
          field.getter!.metadata.annotations.isNotEmpty) {
        elementToUse = field.getter!;
      }
    }

    await _writeMetadata(elementToUse, buffer);
    buffer.write("],");
  }

  Future<void> _generateCompactMethod(
      MethodElement method,
      StringBuffer buffer,
      ) async {
    final retIdx = _typeRegistry.register(method.returnType);
    buffer.write(
      "<dynamic>['${method.displayName}', $retIdx, <List<dynamic>>[",
    );
    for (final p in method.formalParameters) {
      await _generateCompactParam(p, buffer);
    }
    buffer.write("], ");
    await _writeMetadata(method, buffer);
    buffer.write("],");
  }

  Future<void> _generateCompactConstructor(
      ConstructorElement ctor,
      StringBuffer buffer,
      ) async {
    final name = (ctor.name?.isEmpty ?? true) ? '' : ctor.name!;
    final parent = ctor.enclosingElement;
    final parentPrefix = _imports.getPrefix(parent.library);
    final fullName =
    name.isEmpty
        ? '$parentPrefix${parent.name}.new'
        : '$parentPrefix${parent.name}.$name';

    buffer.write("<dynamic>['$name', () => $fullName, <List<dynamic>>[");
    for (final p in ctor.formalParameters) {
      await _generateCompactParam(p, buffer);
    }
    buffer.write("], ");
    await _writeMetadata(ctor, buffer);
    buffer.write("],");
  }

  Future<void> _generateCompactGetter(
      PropertyAccessorElement g,
      StringBuffer buffer,
      ) async {
    final idx = _typeRegistry.register(g.returnType);
    buffer.write("<dynamic>['${g.displayName}', $idx, ");
    await _writeMetadata(g, buffer);
    buffer.write("],");
  }

  Future<void> _generateCompactSetter(
      PropertyAccessorElement s,
      StringBuffer buffer,
      ) async {
    final idx = _typeRegistry.register(s.formalParameters.first.type);
    buffer.write("<dynamic>['${s.displayName}', $idx, ");
    await _writeMetadata(s, buffer);
    buffer.write("],");
  }

  Future<void> _generateCompactParam(
      FormalParameterElement p,
      StringBuffer buffer,
      ) async {
    final idx = _typeRegistry.register(p.type);
    buffer.write(
      "<dynamic>['${p.displayName}', ${p.isPositional}, ${p.isRequired}, $idx, ",
    );
    if (p.hasDefaultValue) {
      await AnnotationExtractor(
        p,
        _imports,
        _resolver,
      ).writeDefaultValueTo(buffer);
      buffer.write(", ");
    } else {
      buffer.write("null, ");
    }
    await _writeMetadata(p, buffer);
    buffer.write("], ");
  }

  Future<void> _generateEnumMirrorEntry(
      EnumElement element,
      DartObject annotation,
      StringBuffer buffer,
      ) async {
    final prefix = _imports.getPrefix(element.library);
    final enumName = '$prefix${element.name}';
    final typeIdx = _typeRegistry.register(element.thisType);

    buffer.write(
      "    _types[$typeIdx].type: m.EnumMirror('${element.displayName}', $typeIdx, <m.EnumConstantMirror>[",
    );
    for (final field in element.fields) {
      if (field.isEnumConstant) {
        final index = element.fields
            .where((f) => f.isEnumConstant)
            .toList()
            .indexOf(field);
        buffer.write(
          "m.EnumConstantMirror('${field.displayName}', $enumName.${field.name}, $index, ",
        );
        await _writeMetadata(field, buffer);
        buffer.write("), ");
      }
    }
    buffer.write("], ");
    await _writeMetadata(element, buffer);
    buffer.writeln("),");
  }

  Future<void> _generateFunctionMirrorEntry(
      FunctionTypedElement element,
      DartObject annotation,
      StringBuffer buffer,
      ) async {
    final prefix = _imports.getPrefix(element.library);
    final funcName = '$prefix${element.name}';
    final retIdx = _typeRegistry.register(element.returnType);

    buffer.write(
      "    '${element.displayName}': m.FunctionMirror('${element.displayName}', $retIdx, <m.ParameterMirror>[",
    );
    for (final p in element.formalParameters) {
      final pIdx = _typeRegistry.register(p.type);
      if (p.isPositional) {
        buffer.write(
          "m.PositionalParameter('${p.displayName}', _types[$pIdx], 0, ${p.isOptional}, ",
        );
        if (p.hasDefaultValue) {
          await AnnotationExtractor(
            p,
            _imports,
            _resolver,
          ).writeDefaultValueTo(buffer);
        } else {
          buffer.write("null");
        }
        buffer.write(", ");

        await _writeMetadata(p, buffer);
        buffer.write("), ");
      } else {
        buffer.write(
          "m.NamedParameter('${p.displayName}', _types[$pIdx], ${p.isRequired}, ",
        );

        if (p.hasDefaultValue) {
          await AnnotationExtractor(
            p,
            _imports,
            _resolver,
          ).writeDefaultValueTo(buffer);
        } else {
          buffer.write("null");
        }
        buffer.write(", ");

        await _writeMetadata(p, buffer);
        buffer.write("), ");
      }
    }
    buffer.write("], () => $funcName, ");
    await _writeMetadata(element, buffer);
    buffer.writeln("),");
  }

  Future<void> _writeMetadata(Element element, StringBuffer buffer) async {
    await AnnotationExtractor(element, _imports, _resolver).writeTo(buffer);
  }

  String _getQualifiedTypeString(DartType type) {
    if (type is InterfaceType) {
      final prefix = _imports.getPrefix(type.element.library);
      final name = type.element.name;
      final core = "$prefix$name";
      if (type.typeArguments.isNotEmpty) {
        final args = type.typeArguments
            .map((t) => _getQualifiedTypeString(t))
            .join(', ');
        return "$core<$args>";
      }
      return core;
    }
    return 'dynamic';
  }

  Set<LibraryElement> _getTransitiveLibraries(LibraryElement root) {
    final visited = <LibraryElement>{};
    final queue = Queue<LibraryElement>();
    queue.add(root);

    while (queue.isNotEmpty) {
      final current = queue.removeFirst();
      if (!visited.add(current)) continue;

      void addCandidate(LibraryElement? lib) {
        if (lib == null) return;
        if (visited.contains(lib)) return;
        if (lib.isInSdk || lib.isDartCore) return;
        queue.add(lib);
      }

      for (final importedLib
      in current.fragments
          .map((f) => f.importedLibraries)
          .expand((x) => x)
          .toList()) {
        addCandidate(importedLib);
      }
      for (final exportedLib in current.exportedLibraries) {
        addCandidate(exportedLib);
      }
    }
    return visited;
  }

  DartObject? _findMirrorsAnnotation(ClassElement element) {
    var annotation = _getMirrorsAnnotation(element);
    if (annotation != null) return annotation;
    return null;
  }

  DartObject? _getMirrorsAnnotation(Element element) {
    if (element.metadata.annotations.isEmpty) return null;
    for (final meta in element.metadata.annotations) {
      final constantValue = meta.computeConstantValue();
      if (constantValue == null) continue;
      final type = constantValue.type;
      if (type is InterfaceType && _isMirrorsType(type.element)) {
        return constantValue;
      }
    }
    return null;
  }

  bool _isMirrorsType(InterfaceElement element) {
    if (element.name == 'Mirrors') return true;
    return element.allSupertypes.any((s) => s.element.name == 'Mirrors');
  }

  Set<String> _parseCapabilities(DartObject annotation) {
    final type = annotation.type;
    if (type is! InterfaceType) return {};

    final result = <String>{};
    final allTypes = [type, ...type.allSupertypes];

    for (final t in allTypes) {
      final name = t.element.name;
      if (name == 'FieldsCapability') result.add('fields');
      if (name == 'GettersCapability') result.add('getters');
      if (name == 'SettersCapability') result.add('setters');
      if (name == 'MethodsCapability') result.add('methods');
      if (name == 'ConstructorsCapability') result.add('constructors');
    }
    return result;
  }
}