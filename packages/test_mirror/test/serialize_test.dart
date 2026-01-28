import 'package:test_mirror/serializer.dart';
import 'package:test/test.dart';

import 'serialize_test.mirror.dart';

@serializable
enum Status { active, inactive, suspended }

@serializable
class Address {
  String street;
  int number;

  Address(this.street, this.number);
}

@serializable
class User {
  int? id;
  String? name;
  bool isAdmin = false;
  Status status = Status.active;
  Address? address;
  List<String> tags = [];

  User();
}

void main() {
  initializeMirrors();

  group('JsonSerializer', () {
    final serializer = JsonSerializer();

    test('should serialize simple object correctly', () {
      final address = Address('Main St', 123);
      final json = serializer.toJson(address);

      expect(json, {'street': 'Main St', 'number': 123});
    });

    test('should deserialize simple object correctly', () {
      final json = {'street': 'Second St', 'number': 456};
      final address = serializer.fromJson<Address>(json);

      expect(address.street, 'Second St');
      expect(address.number, 456);
    });

    test('should serialize complex object with enum and list', () {
      final user = User()
        ..id = 1
        ..name = 'Alice'
        ..isAdmin = true
        ..status = Status.suspended
        ..tags = ['editor', 'pro']
        ..address = Address('Tech Park', 101);

      final json = serializer.toJson(user);

      expect(json['id'], 1);
      expect(json['name'], 'Alice');
      expect(json['isAdmin'], true);
      expect(json['status'], 'suspended');
      expect(json['tags'], ['editor', 'pro']);
      expect(json['address'], {'street': 'Tech Park', 'number': 101});
    });

    test('should deserialize complex object', () {
      final json = {
        'id': 2,
        'name': 'Bob',
        'isAdmin': false,
        'status': 'inactive',
        'tags': ['guest'],
        'address': {'street': 'Home Ln', 'number': 202},
      };

      final user = serializer.fromJson<User>(json);

      expect(user.id, 2);
      expect(user.name, 'Bob');
      expect(user.isAdmin, false);
      expect(user.status, Status.inactive);
      expect(user.tags, contains('guest'));
      expect(user.address?.street, 'Home Ln');
    });

    test('should use default values when fields are missing', () {
      final json = {'id': 3, 'name': 'Charlie'};

      final user = serializer.fromJson<User>(json);

      expect(user.id, 3);
      expect(user.name, 'Charlie');
      expect(user.isAdmin, false);
      expect(user.status, Status.active);
      expect(user.tags, isEmpty);
      expect(user.address, null);
    });

    test('should handle null values explicitly', () {
      final user = User()
        ..id = 4
        ..name = 'Dave'
        ..address = null;
      final json = serializer.toJson(user);
      expect(json['address'], null);
    });

    test('should throw error for missing required arguments', () {
      final json = {'street': 'No Number St'};
      expect(
        () => serializer.fromJson<Address>(json),
        throwsA(isA<Exception>()),
      );
    });

    test(
      'should deserialize root level List<String> using registered types',
      () {
        final json = ['tag1', 'tag2', 'tag3'];

        final list = serializer.fromJson<List<String>>(json);

        expect(list, isA<List<String>>());
        expect(list.length, 3);
        expect(list, containsAll(['tag1', 'tag2', 'tag3']));
      },
    );
  });
}
