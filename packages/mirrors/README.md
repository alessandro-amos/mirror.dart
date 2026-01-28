# Mirrors

**Mirrors** is a lightweight static reflection library for Dart, using code generation.
It is designed as a modern alternative to `reflectable`.

## Installation

Add the following to your `pubspec.yaml`:

```yaml
dependencies:
  mirrors: ^1.0.0

dev_dependencies:
  mirrors_builder: ^1.0.0
  build_runner: ^2.4.0

```

## Usage

Unlike `dart:mirrors`, this library requires you to be explicit about what capabilities you want to enable (methods,
fields, constructors, etc.) to keep the generated code size small.

### 1. Define your Reflection Strategy

Create a constant class that extends `Mirrors` and implements the capabilities you need. You can use `AllCapability` for
full access or pick specific interfaces like `MethodsCapability` or `FieldsCapability`.

```dart
import 'package:mirrors/mirrors.dart';

// Create a custom annotation that defines your reflection capabilities
class Mirrored extends Mirrors implements AllCapability {
  const Mirrored();
}

// Or, for a more restrictive configuration:
// class Reflector extends Mirrors implements MethodsCapability, GettersCapability {
//   const Reflector();
// }

```

### 2. Annotate your code

Use your custom annotation (e.g., `@Mirrored`) to mark classes, enums, or functions for reflection.

```dart
// Use the annotation you defined in Step 1
@Mirrored()
class Todo {
  final String message;
  bool done = false;

  Todo(this.message);
}

@Mirrored()
void addTodo(List<Todo> todos, String message) {
  todos.add(Todo(message));
}

```

### 3. Generate the code

Run the build runner to generate the static reflection data.

```bash
dart run build_runner build

```

### 4. Use Reflection

Import the generated file (usually `main.mirrors.dart` or `<filename>.mirrors.dart` depending on your setup) and
initialize the system.

```dart
import 'package:mirrors/mirrors.dart';
import 'main.mirrors.dart'; // Import generated code

void main() {
  // 1. Initialize the generated mirrors
  initializeMirrors();

  // 2. Reflect on a class definition
  final todoClass = reflectClass(Todo);

  // 3. Create an instance dynamically
  final todoInstance = todoClass.newInstance<Todo>('new', ['Learn mirrors']);

  // 4. Invoke getters, setters, or methods
  print('Created todo: ${todoInstance.invokeGetter('message')}');

  // 5. Inspect global functions
  final addFunc = functions.firstWhere((element) => element.name == 'addTodo');
  print('Found function: ${addFunc.name}');
}

```