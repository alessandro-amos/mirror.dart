/// Base interface for all reflection capabilities.
abstract class MirrorCapability {}

/// Capability to reflect on fields.
abstract class FieldsCapability implements MirrorCapability {}

/// Capability to reflect on getters.
abstract class GettersCapability implements MirrorCapability {}

/// Capability to reflect on setters.
abstract class SettersCapability implements MirrorCapability {}

/// Capability to reflect on methods.
abstract class MethodsCapability implements MirrorCapability {}

/// Capability to reflect on constructors.
abstract class ConstructorsCapability implements MirrorCapability {}

/// Interface that includes all standard capabilities.
abstract class AllCapability
    implements
        FieldsCapability,
        GettersCapability,
        SettersCapability,
        MethodsCapability,
        ConstructorsCapability {}

/// Annotation used to mark classes, enums, or functions as reflectable.
///
/// By default, this enables [AllCapability].
/// To use specific capabilities, create a custom class implementing
/// the desired capability interfaces and use it as an annotation.
///
/// Example:
/// ```dart
/// class MyReflector implements MethodsCapability, ConstructorsCapability {
///   const MyReflector();
/// }
///
/// @MyReflector()
/// class MyClass {}
/// ```
abstract class Mirrors {
  const Mirrors();
}

class Entrypoint {
  const Entrypoint();
}

const entrypoint = Entrypoint();
