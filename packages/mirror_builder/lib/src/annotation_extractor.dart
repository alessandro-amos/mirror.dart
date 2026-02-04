import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';

import 'import_collector.dart';

class AnnotationExtractor {
  final Element element;
  final ImportCollector imports;
  final Resolver resolver;

  AnnotationExtractor(this.element, this.imports, this.resolver);

  Future<void> writeTo(StringBuffer buffer) async {
    final metadata = await _collectAllAnnotations();

    if (metadata.isEmpty) {
      buffer.write("const <dynamic>[]");
      return;
    }

    buffer.write("const <dynamic>[");
    for (var i = 0; i < metadata.length; i++) {
      if (i > 0) buffer.write(", ");
      await _writeAnnotation(metadata[i], buffer);
    }
    buffer.write("]");
  }

  Future<void> writeDefaultValueTo(StringBuffer buffer) async {
    final node = await _getAstNodeFor(element);

    if (node is DefaultFormalParameter && node.defaultValue != null) {
      await _writeExpression(node.defaultValue!, buffer);
    } else {
      if (element is FormalParameterElement) {
        buffer.write(
          (element as FormalParameterElement).defaultValueCode ?? 'null',
        );
      } else {
        buffer.write('null');
      }
    }
  }

  Future<List<Annotation>> _collectAllAnnotations() async {
    final annotations = <Annotation>[];

    Future<void> addFor(Element? e) async {
      if (e == null) return;
      final meta = await _getMetadataFor(e);
      if (meta != null) {
        annotations.addAll(meta);
      }
    }

    await addFor(element);

    if (element is ClassElement) {
      final cls = element as ClassElement;
      for (final supertype in cls.allSupertypes) {
        if (supertype.isDartCoreObject) continue;
        await addFor(supertype.element);
      }
    } else if (element.enclosingElement is ClassElement) {
      final cls = element.enclosingElement as ClassElement;
      final name = element.name;

      if (name != null) {
        for (final supertype in cls.allSupertypes) {
          if (supertype.isDartCoreObject) continue;
          Element? match;

          if (element is MethodElement) {
            match = supertype.element.getMethod(name);
          } else if (element is GetterElement) {
            match = supertype.element.getGetter(name);
          } else if (element is SetterElement) {
            var lookupName = name;
            if (lookupName.endsWith('=')) {
              lookupName = lookupName.substring(0, lookupName.length - 1);
            }
            match = supertype.element.getSetter(lookupName);
          } else if (element is FieldElement) {
            match = supertype.element.getField(name);
          }

          await addFor(match);
        }
      }
    }

    return annotations;
  }

  Future<AstNode?> _getAstNodeFor(Element target) async {
    final library = target.library;
    if (library == null) return null;

    try {
      final libraryId = await resolver.assetIdForElement(library);
      if (!await resolver.isLibrary(libraryId)) return null;

      final resolvedLib = await resolver.libraryFor(libraryId);
      final session = resolvedLib.session;

      final result = await session.getResolvedLibraryByElement(resolvedLib);

      if (result is ResolvedLibraryResult) {
        final declaration = result.getFragmentDeclaration(
          target.firstFragment,
        );
        return declaration?.node;
      }
    } catch (e) {
      return null;
    }
    return null;
  }

  Future<NodeList<Annotation>?> _getMetadataFor(Element target) async {
    final node = await _getAstNodeFor(target);
    if (node == null) return null;

    if (target is VariableElement) {
      if (node is VariableDeclaration) {
        final parent = node.parent;
        if (parent is VariableDeclarationList) {
          final grandParent = parent.parent;
          if (grandParent is AnnotatedNode) {
            return grandParent.metadata;
          }
        }
      }
    }

    if (node is AnnotatedNode) {
      return node.metadata;
    } else if (node is FormalParameter) {
      return node.metadata;
    }

    return null;
  }

  Future<void> _writeAnnotation(Annotation node, StringBuffer buffer) async {
    final element = node.element;

    if (element != null) {
      final lib = element.library;
      if (lib != null) {
        buffer.write(imports.getPrefix(lib));
      }
    }

    buffer.write(node.name.name);
    if (node.constructorName != null) {
      buffer.write('.${node.constructorName!.name}');
    }

    if (node.arguments != null) {
      await _writeArguments(node.arguments!, buffer);
    }
  }

  Future<void> _writeArguments(ArgumentList args, StringBuffer buffer) async {
    buffer.write('(');
    for (int i = 0; i < args.arguments.length; i++) {
      if (i > 0) buffer.write(', ');
      await _writeExpression(args.arguments[i], buffer);
    }
    buffer.write(')');
  }

  Future<void> _writeExpression(
      Expression expression,
      StringBuffer buffer,
      ) async {
    if (expression is BooleanLiteral) {
      buffer.write(expression.value.toString());
    } else if (expression is DoubleLiteral) {
      buffer.write(expression.value.toString());
    } else if (expression is IntegerLiteral) {
      buffer.write(expression.value.toString());
    } else if (expression is StringLiteral) {
      buffer.write(expression.toSource());
    } else if (expression is NullLiteral) {
      buffer.write('null');
    } else if (expression is SimpleIdentifier) {
      await _writeIdentifier(expression, buffer);
    } else if (expression is PrefixedIdentifier) {
      await _writePrefixedIdentifier(expression, buffer);
    } else if (expression is MethodInvocation) {
      await _writeMethodInvocation(expression, buffer);
    } else if (expression is InstanceCreationExpression) {
      await _writeInstanceCreation(expression, buffer);
    } else if (expression is ListLiteral) {
      await _writeListLiteral(expression, buffer);
    } else if (expression is SetOrMapLiteral) {
      await _writeSetOrMapLiteral(expression, buffer);
    } else if (expression is ConstructorReference) {
      await _writeConstructorReference(expression, buffer);
    } else if (expression is NamedExpression) {
      buffer.write(expression.name.label.name);
      buffer.write(': ');
      await _writeExpression(expression.expression, buffer);
    } else if (expression is BinaryExpression) {
      await _writeExpression(expression.leftOperand, buffer);
      buffer.write(' ${expression.operator.lexeme} ');
      await _writeExpression(expression.rightOperand, buffer);
    } else if (expression is PropertyAccess) {
      await _writeExpression(expression.target!, buffer);
      buffer.write('.${expression.propertyName.name}');
    } else {
      buffer.write(expression.toSource());
    }
  }

  Future<void> _writeIdentifier(
      SimpleIdentifier identifier,
      StringBuffer buffer,
      ) async {
    final elem = identifier.element;
    if (elem != null && elem.library != null) {
      if (identifier.parent is NamedExpression &&
          (identifier.parent as NamedExpression).name == identifier.parent) {
        buffer.write(identifier.name);
        return;
      }
      buffer.write(imports.getPrefix(elem.library!));
    }
    buffer.write(identifier.name);
  }

  Future<void> _writePrefixedIdentifier(
      PrefixedIdentifier identifier,
      StringBuffer buffer,
      ) async {
    final elem = identifier.element;
    if (elem != null && elem.library != null) {
      buffer.write(imports.getPrefix(elem.library!));
      if (elem.enclosingElement is InterfaceElement) {
        buffer.write('${elem.enclosingElement!.name}.');
      }
      buffer.write(identifier.identifier.name);
    } else {
      buffer.write(identifier.toSource());
    }
  }

  Future<void> _writeInstanceCreation(
      InstanceCreationExpression expression,
      StringBuffer buffer,
      ) async {
    if (expression.keyword != null) {
      buffer.write('${expression.keyword!.lexeme} ');
    }

    final constructorName = expression.constructorName;
    final type = constructorName.type;
    final element = type.element;

    if (element is InterfaceElement) {
      buffer.write(imports.getPrefix(element.library));
      buffer.write(element.name);
      if (constructorName.name != null) {
        buffer.write('.${constructorName.name!.name}');
      }
    } else {
      buffer.write(constructorName.toSource());
    }

    if (type.typeArguments != null) {
      _writeTypeArgumentList(type.typeArguments!, buffer);
    }

    await _writeArguments(expression.argumentList, buffer);
  }

  Future<void> _writeListLiteral(
      ListLiteral expression,
      StringBuffer buffer,
      ) async {
    if (expression.constKeyword != null) buffer.write('const ');
    if (expression.typeArguments != null) {
      _writeTypeArgumentList(expression.typeArguments!, buffer);
    }
    buffer.write('[');
    for (var i = 0; i < expression.elements.length; i++) {
      if (i > 0) buffer.write(', ');
      final elem = expression.elements[i];
      if (elem is Expression) {
        await _writeExpression(elem, buffer);
      } else {
        buffer.write(elem.toSource());
      }
    }
    buffer.write(']');
  }

  Future<void> _writeSetOrMapLiteral(
      SetOrMapLiteral expression,
      StringBuffer buffer,
      ) async {
    if (expression.constKeyword != null) buffer.write('const ');
    if (expression.typeArguments != null) {
      _writeTypeArgumentList(expression.typeArguments!, buffer);
    }
    buffer.write('{');
    for (var i = 0; i < expression.elements.length; i++) {
      if (i > 0) buffer.write(', ');
      final elem = expression.elements[i];
      if (elem is MapLiteralEntry) {
        await _writeExpression(elem.key, buffer);
        buffer.write(': ');
        await _writeExpression(elem.value, buffer);
      } else if (elem is Expression) {
        await _writeExpression(elem, buffer);
      } else {
        buffer.write(elem.toSource());
      }
    }
    buffer.write('}');
  }

  Future<void> _writeMethodInvocation(
      MethodInvocation expression,
      StringBuffer buffer,
      ) async {
    if (expression.target != null) {
      await _writeExpression(expression.target!, buffer);
      buffer.write('.');
    } else {
      final elem = expression.methodName.element;
      if (elem != null && elem.library != null) {
        buffer.write(imports.getPrefix(elem.library!));
      }
    }
    buffer.write(expression.methodName.name);
    await _writeArguments(expression.argumentList, buffer);
  }

  Future<void> _writeConstructorReference(
      ConstructorReference expression,
      StringBuffer buffer,
      ) async {
    final elem = expression.constructorName.type.element;
    if (elem != null && elem.library != null) {
      buffer.write(imports.getPrefix(elem.library));
    }
    buffer.write(expression.toSource());
  }

  void _writeTypeArgumentList(TypeArgumentList list, StringBuffer buffer) {
    buffer.write('<');
    for (var i = 0; i < list.arguments.length; i++) {
      if (i > 0) buffer.write(', ');
      _writeTypeAnnotation(list.arguments[i], buffer);
    }
    buffer.write('>');
  }

  void _writeTypeAnnotation(TypeAnnotation type, StringBuffer buffer) {
    if (type is NamedType) {
      final elem = type.element;
      if (elem != null && elem.library != null) {
        buffer.write(imports.getPrefix(elem.library));
      }
      buffer.write(type.name.lexeme);
      if (type.typeArguments != null) {
        _writeTypeArgumentList(type.typeArguments!, buffer);
      }
      if (type.question != null) buffer.write('?');
    } else {
      buffer.write(type.toSource());
    }
  }
}