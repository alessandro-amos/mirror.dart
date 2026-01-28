import 'package:mirror/mirror.dart';

import 'example.mirror.dart';

class Mirrored extends Mirrors implements AllCapability {
  const Mirrored();
}

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

@entrypoint
void main() {
  initializeMirrors();

  final todo = reflectClass(Todo);

  final todoInstance = todo.newInstance<Todo>('new', ['Learn mirrors']);

  print(functions.where((element) => element.name == 'addTodo').first);

  print('Created todo: ${todoInstance.invokeGetter('message')}');
}
