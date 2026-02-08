import '../models/app_exception.dart';

void ensureExpectedStatus({
  required int? actualStatus,
  required int expectedStatus,
  required String operation,
  Object? responseData,
}) {
  if (actualStatus == expectedStatus) return;

  throw AppException(
    message: _messageFromResponseData(responseData, fallback: 'Unexpected status for $operation'),
    code: 'unexpected_status',
    status: actualStatus,
  );
}

Map<String, dynamic> requireJsonMap({
  required Object? data,
  required String operation,
}) {
  if (data is Map<String, dynamic>) {
    return data;
  }

  throw AppException(
    message: 'Invalid response payload for $operation',
    code: 'invalid_payload',
  );
}

String _messageFromResponseData(Object? data, {required String fallback}) {
  if (data is Map<String, dynamic>) {
    final error = data['error'];
    if (error is String && error.isNotEmpty) return error;

    final message = data['message'];
    if (message is String && message.isNotEmpty) return message;
  }

  return fallback;
}
