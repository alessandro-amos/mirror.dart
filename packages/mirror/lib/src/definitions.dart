import 'dart:collection';

List<TypeMirror> types = [];

Map<Type, ClassMirror> classesMap = {};

Map<Type, EnumMirror> enumsMap = {};

Map<String, FunctionMirror> functionsMap = {};

Map<String, dynamic Function(dynamic)> gettersInvokers = {};

Map<String, void Function(dynamic, dynamic)> settersInvokers = {};

Map<String, dynamic Function(dynamic)> methodsInvokers = {};

ClassMirror reflectClass(Type type) {
  final mirror = classesMap[type];
  if (mirror != null) return mirror;
  throw ReflectException(
    "Cannot mirror type '$type'. Is it annotated with @Mirrors?",
  );
}

ClassMirror? tryReflectClass(Type type) {
  return classesMap[type];
}

EnumMirror reflectEnum(Type type) {
  final mirror = enumsMap[type];
  if (mirror != null) return mirror;
  throw ReflectException(
    "Cannot mirror enum '$type'. Is it annotated with @Mirrors?",
  );
}

FunctionMirror reflectFunction(String name) {
  final mirror = functionsMap[name];
  if (mirror != null) return mirror;
  throw ReflectException(
    "Cannot mirror function '$name'. Is it annotated with @Mirrors?",
  );
}

InstanceMirror<T> reflectObject<T>(T object) {
  return InstanceMirror<T>(object);
}

List<ClassMirror> get classes => List.unmodifiable(classesMap.values);

List<EnumMirror> get enums => List.unmodifiable(enumsMap.values);

List<FunctionMirror> get functions => List.unmodifiable(functionsMap.values);

abstract class HasOwner<T extends DeclarationMirror> {
  T get owner;
}

class ReflectException implements Exception {
  final String message;

  ReflectException(this.message);

  @override
  String toString() => 'ReflectException: $message';
}

class MissingCapabilityException extends ReflectException {
  MissingCapabilityException(super.message);
}

class MissingMemberException extends ReflectException {
  MissingMemberException(super.message);
}

abstract class DeclarationMirror {
  final String name;

  final List<dynamic> metadata;

  const DeclarationMirror(this.name, this.metadata);

  bool hasMetadata<T>() => metadata.any((a) => a is T);

  T? getMetadata<T>() => metadata.whereType<T>().firstOrNull;

  List<T> getAllMetadata<T>() => metadata.whereType<T>().toList();

  String get simpleName => name;

  Symbol get simpleNameSymbol => Symbol(name);

  @override
  String toString() => '$runtimeType($name)';
}

abstract class ObjectMirror {
  dynamic invoke(
      String memberName,
      List positionalArguments, [
        Map<Symbol, dynamic> namedArguments,
      ]);

  dynamic invokeGetter(String getterName);

  void invokeSetter(String setterName, dynamic value);
}

class TypeMirror<T> {
  Type get type => T;

  final List<int> _typeArgumentIndices;

  final bool isNullable;

  const TypeMirror(this._typeArgumentIndices, this.isNullable);

  List<TypeMirror> get typeArguments {
    return _typeArgumentIndices.map((i) => types[i]).toList();
  }

  D captureGenericType<D>(D Function<S>() f) {
    return f<T>();
  }

  List<T> castList(List<dynamic> list) {
    return list.cast<T>();
  }

  Set<T> castSet(Set<dynamic> set) {
    return set.cast<T>();
  }

  bool isList() {
    return T == List || T.toString().startsWith('List<');
  }

  @override
  String toString() {
    final suffix = isNullable ? '?' : '';
    if (_typeArgumentIndices.isEmpty) return '$type$suffix';
    try {
      return '$type<${typeArguments.join(', ')}>$suffix';
    } catch (e) {
      return '$type$suffix';
    }
  }
}

class InstanceMirror<T> implements ObjectMirror {
  final T reflectee;

  final ClassMirror? _classMirror;

  InstanceMirror(this.reflectee)
      : _classMirror = reflectClass(reflectee.runtimeType);

  ClassMirror? get type => _classMirror;

  @override
  dynamic invoke(
      String memberName,
      List positionalArguments, [
        Map<Symbol, dynamic> namedArguments = const {},
      ]) {
    if (_classMirror == null) {
      throw ReflectException(
        "Cannot mirror on type  '${reflectee.runtimeType}'. Is it annotated with @Mirrors?",
      );
    }
    final method = _classMirror.getMethodStrict(memberName);
    return method.invoke(reflectee, positionalArguments, namedArguments);
  }

  @override
  dynamic invokeGetter(String getterName) {
    if (_classMirror == null) {
      throw ReflectException(
        "Cannot mirror on type  '${reflectee.runtimeType}'. Is it annotated with @Mirrors?",
      );
    }

    final getter = _classMirror.getGetter(getterName);
    if (getter != null) return getter.invoke(reflectee);

    final field = _classMirror.getField(getterName);
    if (field != null && field.getter != null) {
      return field.getter!.invoke(reflectee);
    }

    throw MissingMemberException(
      'Getter "$getterName" not found in ${_classMirror.name}',
    );
  }

  @override
  void invokeSetter(String setterName, dynamic value) {
    if (_classMirror == null) {
      throw ReflectException(
        "Cannot mirror on type  '${reflectee.runtimeType}'. Is it annotated with @Mirrors?",
      );
    }
    final normalizedName = setterName.endsWith('=')
        ? setterName.substring(0, setterName.length - 1)
        : setterName;

    final setter = _classMirror.getSetter(normalizedName);
    if (setter != null) {
      setter.invoke(reflectee, value);
      return;
    }

    final field = _classMirror.getField(normalizedName);
    if (field != null && field.setter != null) {
      field.setter!.invoke(reflectee, value);
      return;
    }

    throw MissingMemberException(
      'Setter "$setterName" not found in ${_classMirror.name}',
    );
  }
}

class ClassMirror extends DeclarationMirror implements ObjectMirror {
  final int _typeIndex;
  final List<dynamic>? _fields;
  final List<dynamic>? _methods;
  final List<dynamic>? _getters;
  final List<dynamic>? _setters;
  final List<dynamic>? _constructors;

  Map<String, VariableMirror>? _fieldsCache;
  Map<String, MethodMirror>? _methodsCache;
  Map<String, GetterMirror>? _gettersCache;
  Map<String, SetterMirror>? _settersCache;
  Map<String, ConstructorMirror>? _constructorsCache;

  ClassMirror(
      String name,
      this._typeIndex,
      List<dynamic> metadata,
      this._fields,
      this._getters,
      this._setters,
      this._methods,
      this._constructors,
      ) : super(name, metadata);

  TypeMirror get type => types[_typeIndex];

  @override
  dynamic invoke(
      String memberName,
      List positionalArguments, [
        Map<Symbol, dynamic> namedArguments = const {},
      ]) {
    final method = getMethodStrict(memberName);
    if (!method.isStatic) {
      throw ReflectException('Method "$memberName" is not static.');
    }
    return method.invoke(null, positionalArguments, namedArguments);
  }

  @override
  dynamic invokeGetter(String getterName) {
    final getter = getGetter(getterName);
    if (getter != null && getter.isStatic) return getter.invoke(null);

    final field = getField(getterName);
    if (field != null && field.isStatic && field.getter != null) {
      return field.getter!.invoke(null);
    }
    throw MissingMemberException(
      'Static getter "$getterName" not found in $name',
    );
  }

  @override
  void invokeSetter(String setterName, dynamic value) {
    final normalized = setterName.endsWith('=')
        ? setterName.substring(0, setterName.length - 1)
        : setterName;
    final setter = getSetter(normalized);
    if (setter != null && setter.isStatic) {
      setter.invoke(null, value);
      return;
    }
    final field = getField(normalized);
    if (field != null && field.isStatic && field.setter != null) {
      field.setter!.invoke(null, value);
      return;
    }
    throw MissingMemberException(
      'Static setter "$setterName" not found in $name',
    );
  }

  Map<String, VariableMirror>? get fields {
    if (_fields == null) return null;
    if (_fieldsCache != null) return UnmodifiableMapView(_fieldsCache!);
    _fieldsCache = {};
    for (final raw in _fields) {
      final variable = VariableMirror(
        raw[0] as String,
        types[raw[1]],
        raw[2],
        raw[3],
        raw[4] ?? const [],
      )..owner = this;
      _fieldsCache![variable.name] = variable;
    }
    return UnmodifiableMapView(_fieldsCache!);
  }

  Map<String, MethodMirror>? get methods {
    if (_methods == null) return null;
    if (_methodsCache != null) return UnmodifiableMapView(_methodsCache!);
    _methodsCache = {};
    for (final raw in _methods) {
      final method = MethodMirror(
        raw[0] as String,
        types[raw[1]],
        _unpackParams(raw[2]),
        raw[3] ?? const [],
      )..owner = this;
      _methodsCache![method.name] = method;
    }
    return UnmodifiableMapView(_methodsCache!);
  }

  Map<String, ConstructorMirror>? get constructors {
    if (_constructors == null) return null;
    if (_constructorsCache != null) {
      return UnmodifiableMapView(_constructorsCache!);
    }
    _constructorsCache = {};
    for (final raw in _constructors) {
      final ctor = ConstructorMirror(
        raw[0] as String,
        raw[1],
        _unpackParams(raw[2]),
        raw[3] ?? const [],
      )..owner = this;
      _constructorsCache![ctor.name] = ctor;
    }
    return UnmodifiableMapView(_constructorsCache!);
  }

  Map<String, GetterMirror>? get getters {
    if (_gettersCache != null) return UnmodifiableMapView(_gettersCache!);
    final combined = <String, GetterMirror>{};

    if (_getters != null) {
      for (final raw in _getters) {
        final g = GetterMirror(
          raw[0] as String,
          types[raw[1]],
          raw[2] ?? const [],
        )..owner = this;
        combined[g.name] = g;
      }
    }
    _gettersCache = combined;
    return UnmodifiableMapView(_gettersCache!);
  }

  Map<String, SetterMirror>? get setters {
    if (_settersCache != null) return UnmodifiableMapView(_settersCache!);
    final combined = <String, SetterMirror>{};

    if (_setters != null) {
      for (final raw in _setters) {
        final s = SetterMirror(
          raw[0] as String,
          types[raw[1]],
          raw[2] ?? const [],
        )..owner = this;
        combined[s.name] = s;
      }
    }
    _settersCache = combined;
    return UnmodifiableMapView(_settersCache!);
  }

  VariableMirror? getField(String name) => fields?[name];

  GetterMirror? getGetter(String name) => getters?[name];

  SetterMirror? getSetter(String name) => setters?[name];

  MethodMirror? getMethod(String name) => methods?[name];

  ConstructorMirror? getConstructor(String name) => constructors?[name];

  MethodMirror getMethodStrict(String name) {
    final m = methods?[name];
    if (m == null) {
      throw MissingMemberException(
        'Method "$name" not found in class "$name".',
      );
    }
    return m;
  }

  InstanceMirror<T> newInstance<T>([
    String constructorName = 'new',
    List args = const [],
    Map<Symbol, dynamic> namedArgs = const {},
  ]) {
    final c = constructors?[constructorName];
    if (c == null) {
      throw MissingMemberException('Constructor "$constructorName" not found');
    }
    return reflectObject(c.invoke(args, namedArgs) as T);
  }

  List<ParameterMirror> _unpackParams(List<dynamic> rawParams) {
    if (rawParams.isEmpty) return const [];
    return rawParams.map((p) {
      final name = p[0] as String;
      final isPositional = p[1];
      final isRequired = p[2];
      final type = types[p[3]];
      final defaultValue = p[4];
      final meta = p[5] ?? const [];

      if (isPositional) {
        return PositionalParameter(
          name,
          type,
          0,
          !isRequired,
          defaultValue,
          meta,
        );
      } else {
        return NamedParameter(name, type, isRequired, defaultValue, meta);
      }
    }).toList();
  }
}

class EnumMirror extends DeclarationMirror {
  final int _typeIndex;

  final List<EnumConstantMirror> values;

  EnumMirror(String name, this._typeIndex, this.values, List<dynamic> metadata)
      : super(name, metadata);

  TypeMirror get type => types[_typeIndex];
}

class EnumConstantMirror extends DeclarationMirror {
  final dynamic value;

  final int index;

  const EnumConstantMirror(
      String name,
      this.value,
      this.index,
      List<dynamic> metadata,
      ) : super(name, metadata);
}

class FunctionMirror extends DeclarationMirror {
  final int _returnTypeIndex;

  final List<ParameterMirror> parameters;
  final Function Function() _invoker;

  FunctionMirror(
      String name,
      this._returnTypeIndex,
      this.parameters,
      this._invoker,
      List<dynamic> metadata,
      ) : super(name, metadata);

  TypeMirror get returnType => types[_returnTypeIndex];

  dynamic invoke([
    List args = const [],
    Map<Symbol, dynamic> namedArgs = const {},
  ]) => Function.apply(_invoker(), args, namedArgs);
}

class MethodMirror extends DeclarationMirror implements HasOwner<ClassMirror> {
  @override
  late final ClassMirror owner;

  final TypeMirror returnType;

  final List<ParameterMirror> parameters;

  MethodMirror(
      String name,
      this.returnType,
      this.parameters, [
        List<dynamic> metadata = const [],
      ]) : super(name, metadata);

  bool get isStatic => false;

  dynamic invoke(
      dynamic instance, [
        List args = const [],
        Map<Symbol, dynamic> namedArgs = const {},
      ]) {
    final invoker = methodsInvokers[name];
    if (invoker == null) {
      throw ReflectException("Implementation for method '$name' not found.");
    }

    final fn = invoker(instance) as Function;
    return Function.apply(fn, args, namedArgs);
  }
}

class ConstructorMirror extends DeclarationMirror
    implements HasOwner<ClassMirror> {
  @override
  late final ClassMirror owner;
  final Function Function() _factory;

  final List<ParameterMirror> parameters;

  ConstructorMirror(
      String name,
      this._factory,
      this.parameters, [
        List<dynamic> metadata = const [],
      ]) : super(name, metadata);

  dynamic invoke([
    List args = const [],
    Map<Symbol, dynamic> namedArgs = const {},
  ]) {
    return Function.apply(_factory(), args, namedArgs);
  }
}

class VariableMirror extends DeclarationMirror
    implements HasOwner<DeclarationMirror> {
  @override
  late final DeclarationMirror owner;

  final TypeMirror type;

  final bool isFinal;

  final bool isStatic;

  VariableMirror(
      String name,
      this.type,
      this.isFinal,
      this.isStatic, [
        List<dynamic> metadata = const [],
      ]) : super(name, metadata);

  GetterMirror? get getter {
    if (!gettersInvokers.containsKey(name)) return null;
    return GetterMirror(name, type, metadata).._isStatic = isStatic;
  }

  SetterMirror? get setter {
    if (isFinal) return null;
    if (!settersInvokers.containsKey(name)) return null;
    return SetterMirror(name, type, metadata).._isStatic = isStatic;
  }
}

class GetterMirror extends DeclarationMirror
    implements HasOwner<DeclarationMirror> {
  @override
  late final DeclarationMirror owner;

  final TypeMirror returnType;
  bool _isStatic = false;

  GetterMirror(
      String name,
      this.returnType, [
        List<dynamic> metadata = const [],
      ]) : super(name, metadata);

  bool get isStatic => _isStatic;

  dynamic invoke(dynamic instance) {
    final invoker = gettersInvokers[name];
    if (invoker == null) {
      throw ReflectException("Implementation for getter '$name' not found.");
    }
    return invoker(instance);
  }
}

class SetterMirror extends DeclarationMirror
    implements HasOwner<DeclarationMirror> {
  @override
  late final DeclarationMirror owner;

  final TypeMirror paramType;
  bool _isStatic = false;

  SetterMirror(String name, this.paramType, [List<dynamic> metadata = const []])
      : super(name, metadata);

  bool get isStatic => _isStatic;

  void invoke(dynamic instance, dynamic value) {
    final invoker = settersInvokers[name];
    if (invoker == null) {
      throw ReflectException("Implementation for setter '$name' not found.");
    }
    invoker(instance, value);
  }
}

abstract class ParameterMirror extends DeclarationMirror {
  final TypeMirror type;

  final bool isOptional;

  final dynamic defaultValue;

  const ParameterMirror(
      super.name,
      super.metadata,
      this.type,
      this.isOptional,
      this.defaultValue,
      );

  bool get isNamed;

  bool get isPositional => !isNamed;
}

class PositionalParameter extends ParameterMirror {
  final int index;

  const PositionalParameter(
      String name,
      TypeMirror type,
      this.index,
      bool isOptional,
      dynamic defaultValue, [
        List<dynamic> metadata = const [],
      ]) : super(name, metadata, type, isOptional, defaultValue);

  @override
  bool get isNamed => false;
}

class NamedParameter extends ParameterMirror {
  bool get isRequired => !isOptional;

  const NamedParameter(
      String name,
      TypeMirror type,
      bool isRequired,
      dynamic defaultValue, [
        List<dynamic> metadata = const [],
      ]) : super(name, metadata, type, !isRequired, defaultValue);

  @override
  bool get isNamed => true;
}

TypeMirror<T> type<T>(List<int> args, [bool isNullable = false]) {
  return TypeMirror<T>(args, isNullable);
}