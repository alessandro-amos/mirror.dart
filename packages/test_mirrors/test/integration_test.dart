import 'package:mirrors/mirrors.dart';
import 'package:test/test.dart';

import 'integration_test.mirrors.dart';

class Mirrored extends Mirrors implements AllCapability {
  const Mirrored();
}

class RestApi {
  final String path;

  const RestApi(this.path);
}

class Get {
  final String route;

  const Get([this.route = '/']);
}

class Validation {
  final bool required;

  const Validation({this.required = true});
}

@Mirrored()
@RestApi('/users')
class UserController {
  String status = 'init';

  UserController();

  @Get('/profile')
  String getProfile(@Validation(required: true) int id) {
    return 'User Profile $id';
  }

  bool updateData(String data, {bool force = false}) {
    if (force) {
      status = 'forced: $data';
    } else {
      status = 'updated: $data';
    }
    return true;
  }
}

void main() {
  initializeMirrors();

  group('Integration Test - Definitions & Generated Code', () {
    test('Should reflect class metadata correctly', () {
      final mirror = reflectClass(UserController);

      expect(mirror.name, 'UserController');
      expect(mirror.hasMetadata<RestApi>(), isTrue);

      final annotation = mirror.getMetadata<RestApi>();
      expect(annotation?.path, '/users');
    });

    test('Should reflect methods and parameters metadata', () {
      final mirror = reflectClass(UserController);
      final method = mirror.getMethodStrict('getProfile');

      expect(method.returnType.type, String);
      expect(method.hasMetadata<Get>(), isTrue);
      expect(method.getMetadata<Get>()?.route, '/profile');

      expect(method.parameters.length, 1);
      final param = method.parameters.first;
      expect(param.name, 'id');
      expect(param.type.type, int);
      expect(param.hasMetadata<Validation>(), isTrue);
      expect(param.getMetadata<Validation>()?.required, isTrue);
    });

    test('Should invoke methods with named arguments', () {
      final controller = UserController();
      final mirror = reflectObject(controller);

      final result1 = mirror.invoke('updateData', ['test1']);
      expect(result1, true);
      expect(controller.status, 'updated: test1');

      mirror.invoke('updateData', ['test2'], {Symbol('force'): true});
      expect(controller.status, 'forced: test2');
    });

    test('Should invoke getters and setters correctly', () {
      final controller = UserController();
      final mirror = reflectObject(controller);

      mirror.invokeSetter('status', 'active');
      expect(controller.status, 'active');
      expect(mirror.invokeGetter('status'), 'active');
    });

    test('Should throw correct exceptions for missing members', () {
      final mirror = reflectClass(UserController);

      expect(
        () => mirror.getMethodStrict('nonExistent'),
        throwsA(isA<MissingMemberException>()),
      );
    });
  });
}
