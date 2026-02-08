class AppException implements Exception {
  const AppException({
    required this.message,
    required this.code,
    this.status,
  });

  final String message;
  final String code;
  final int? status;

  @override
  String toString() {
    final suffix = status != null ? ' (status: $status)' : '';
    return 'AppException[$code]: $message$suffix';
  }
}
