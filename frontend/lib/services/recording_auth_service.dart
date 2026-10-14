/// Manages biometric authentication state for recording sessions.
/// Ensures that biometric prompt triggers exactly ONCE when starting a new
/// recording session, and is never asked again during that session.
class RecordingAuthService {
  static bool _sessionAuthenticated = false;

  /// Whether the user has successfully authenticated biometrics for the current recording session.
  static bool get isSessionAuthenticated => _sessionAuthenticated;

  /// Mark the current recording session as authenticated.
  static void markSessionAuthenticated() {
    _sessionAuthenticated = true;
  }

  /// Reset the session authentication so that the next new recording requires a fresh biometric check.
  static void resetSessionAuth() {
    _sessionAuthenticated = false;
  }
}
