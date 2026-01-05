/// Type-safe error handling without throwing exceptions
sealed class Result<T> {
  const Result();

  /// Create a successful result
  factory Result.success(T data) => Success(data);

  /// Create a failed result
  factory Result.failure(Exception exception) => Failure(exception);

  /// Transform successful result or pass through failure
  Result<R> map<R>(R Function(T) fn) {
    return switch (this) {
      Success(data: final data) => Success(fn(data)),
      Failure(exception: final ex) => Failure(ex),
    };
  }

  /// Flat-map for chaining operations
  Future<Result<R>> asyncMap<R>(Future<Result<R>> Function(T) fn) async {
    return switch (this) {
      Success(data: final data) => await fn(data),
      Failure(exception: final ex) => Failure(ex),
    };
  }

  /// Get data or return default
  T getOrDefault(T defaultValue) {
    return switch (this) {
      Success(data: final data) => data,
      Failure() => defaultValue,
    };
  }

  /// Get data or throw
  T getOrThrow() {
    return switch (this) {
      Success(data: final data) => data,
      Failure(exception: final ex) => throw ex,
    };
  }

  /// Execute callback for success or failure
  void fold(void Function(T) onSuccess, void Function(Exception) onFailure) {
    switch (this) {
      case Success(data: final data):
        onSuccess(data);
      case Failure(exception: final ex):
        onFailure(ex);
    }
  }

  /// Check if this is a success
  bool get isSuccess => this is Success;

  /// Check if this is a failure
  bool get isFailure => this is Failure;
}

/// Successful result containing data
final class Success<T> extends Result<T> {
  final T data;

  const Success(this.data);

  @override
  String toString() => 'Success($data)';
}

/// Failed result containing exception
final class Failure<T> extends Result<T> {
  final Exception exception;

  const Failure(this.exception);

  @override
  String toString() => 'Failure(${exception.toString()})';
}

/// Common exception types for music operations
class MusicException implements Exception {
  final String message;
  final Exception? originalException;

  MusicException(this.message, [this.originalException]);

  @override
  String toString() => message;
}

class NetworkException extends MusicException {
  NetworkException(super.message);
}

class CacheException extends MusicException {
  CacheException(super.message);
}

class AuthException extends MusicException {
  AuthException(super.message);
}

class ParseException extends MusicException {
  ParseException(super.message, [super.originalException]);
}
