/// Error dengan kode status HTTP untuk layanan eksternal (Spotify, Gemini, dll).
class ApiError implements Exception {
  ApiError(this.status, this.message);
  final int status;
  final String message;

  @override
  String toString() => message;
}
