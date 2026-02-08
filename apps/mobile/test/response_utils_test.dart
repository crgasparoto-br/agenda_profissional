import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/app_exception.dart';
import 'package:mobile/services/response_utils.dart';

void main() {
  test('ensureExpectedStatus does not throw for expected status', () {
    expect(
      () => ensureExpectedStatus(actualStatus: 200, expectedStatus: 200, operation: 'op'),
      returnsNormally,
    );
  });

  test('ensureExpectedStatus throws AppException with error message from payload', () {
    expect(
      () => ensureExpectedStatus(
        actualStatus: 400,
        expectedStatus: 200,
        operation: 'bootstrap-tenant',
        responseData: {'error': 'Invalid payload'},
      ),
      throwsA(
        isA<AppException>()
            .having((e) => e.code, 'code', 'unexpected_status')
            .having((e) => e.status, 'status', 400)
            .having((e) => e.message, 'message', 'Invalid payload'),
      ),
    );
  });

  test('requireJsonMap returns map when payload is valid', () {
    final map = requireJsonMap(data: {'ok': true}, operation: 'op');
    expect(map['ok'], true);
  });

  test('requireJsonMap throws AppException for invalid payload', () {
    expect(
      () => requireJsonMap(data: 'not-a-map', operation: 'op'),
      throwsA(
        isA<AppException>()
            .having((e) => e.code, 'code', 'invalid_payload')
            .having((e) => e.message, 'message', 'Invalid response payload for op'),
      ),
    );
  });
}
