import 'package:mirror/mirror.dart';

class Serializable extends Mirrors
    implements
        ConstructorsCapability,
        FieldsCapability,
        GettersCapability,
        SettersCapability {
  const Serializable();
}

const serializable = Serializable();

class JsonSerializer {
  dynamic toJson(Object? object) {
    if (object == null) return null;
    if (object is num || object is String || object is bool) return object;

    if (object is List) {
      return object.map(toJson).toList();
    }

    if (object is Map) {
      return object.map((k, v) => MapEntry(k.toString(), toJson(v)));
    }

    if (enumsMap.containsKey(object.runtimeType)) {
      return object.toString().split('.').last;
    }

    try {
      final mirror = reflectObject(object);
      final classMirror = mirror.type;

      if (classMirror == null) return object.toString();

      final json = <String, dynamic>{};
      final fields = classMirror.fields;

      if (fields != null) {
        for (var field in fields.values) {
          if (field.isStatic || field.name.startsWith('_')) continue;

          try {
            final value = mirror.invokeGetter(field.name);
            json[field.name] = toJson(value);
          } catch (_) {}
        }
      }

      return json;
    } catch (_) {
      return object.toString();
    }
  }

  T fromJson<T>(dynamic json) {
    if (json == null) return null as T;
    if (json is T) return json;

    if (enumsMap.containsKey(T)) {
      return _decodeEnum(json, T) as T;
    }

    if (json is List) {
      try {
        // Busca o TypeMirror correspondente a T (ex: List<User>) na lista global
        final typeMirror = types.firstWhere((t) => t.type == T);
        return _decodeValue(json, typeMirror) as T;
      } catch (_) {
        throw ArgumentError(
          "List deserialization for '$T' failed. Ensure the type is registered in 'types'.",
        );
      }
    }

    final classMirror = reflectClass(T);
    return _deserializeObject(json, classMirror) as T;
  }

  dynamic _decodeValue(dynamic json, TypeMirror targetType) {
    if (json == null) return null;
    if (targetType.type == dynamic) return json;
    if (targetType.type == String) return json.toString();
    if (targetType.type == int) return (json as num).toInt();
    if (targetType.type == double) return (json as num).toDouble();
    if (targetType.type == bool) return json as bool;

    if (enumsMap.containsKey(targetType.type)) {
      return _decodeEnum(json, targetType.type);
    }

    if (json is List) {
      final itemType = targetType.typeArguments.first;
      final list = itemType.castList([]);
      for (var item in json) {
        list.add(_decodeValue(item, itemType));
      }
      return list;
    }

    try {
      final classMirror = reflectClass(targetType.type);
      return _deserializeObject(json, classMirror);
    } catch (_) {
      return json;
    }
  }

  dynamic _decodeEnum(dynamic json, Type type) {
    final enumMirror = reflectEnum(type);
    return enumMirror.values
        .firstWhere(
          (e) => e.name == json.toString(),
          orElse: () =>
              throw Exception("Enum value '$json' not found in $type"),
        )
        .value;
  }

  dynamic _deserializeObject(
    Map<String, dynamic> json,
    ClassMirror classMirror,
  ) {
    final constructor = classMirror.getConstructor('new');
    if (constructor == null) {
      throw Exception("Constructor 'new' not found for ${classMirror.name}");
    }

    final positionalArgs = [];
    final namedArgs = <Symbol, dynamic>{};
    final usedKeys = <String>{};

    for (var param in constructor.parameters) {
      final key = param.name;
      usedKeys.add(key);

      if (!json.containsKey(key)) {
        if (param.isOptional) {
          if (param.isPositional) positionalArgs.add(param.defaultValue);
          continue;
        }
        throw Exception(
          "Missing required argument '$key' for ${classMirror.name}",
        );
      }

      final value = _decodeValue(json[key], param.type);
      if (param.isPositional) {
        positionalArgs.add(value);
      } else {
        namedArgs[Symbol(key)] = value;
      }
    }

    final instanceMirror = classMirror.newInstance(
      'new',
      positionalArgs,
      namedArgs,
    );

    final instance = instanceMirror.reflectee;

    for (var entry in json.entries) {
      if (usedKeys.contains(entry.key)) continue;

      final key = entry.key;
      final value = entry.value;

      var setter = classMirror.getSetter(key);
      if (setter != null) {
        final decodedValue = _decodeValue(value, setter.paramType);
        instanceMirror.invokeSetter(key, decodedValue);
        continue;
      }

      final field = classMirror.getField(key);
      if (field != null &&
          !field.isFinal &&
          !field.isStatic &&
          field.setter != null) {
        final decodedValue = _decodeValue(value, field.type);
        instanceMirror.invokeSetter(key, decodedValue);
      }
    }

    return instance;
  }
}
