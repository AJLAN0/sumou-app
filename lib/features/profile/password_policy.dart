/// Client-side mirror of the password policy enforced authoritatively by the
/// `change-own-password` Edge Function.
///
/// This helper exists for immediate form feedback and preflight validation
/// only. The server remains authoritative.
enum PasswordPolicyFailure {
  tooShort,
  tooLong,
  missingUppercase,
  missingLowercase,
  missingDigit,
  missingSymbol,
  surroundingWhitespace,
  matchesCurrent,
}

class PasswordPolicyResult {
  const PasswordPolicyResult(this.failures);

  final Set<PasswordPolicyFailure> failures;

  bool get isValid => failures.isEmpty;
}

class PasswordPolicy {
  PasswordPolicy._();

  static const int minLength = 12;
  static const int maxLength = 72;

  static final RegExp _uppercase = RegExp(r'[A-Z]');
  static final RegExp _lowercase = RegExp(r'[a-z]');
  static final RegExp _digit = RegExp(r'[0-9]');
  static final RegExp _symbol = RegExp(r'[^A-Za-z0-9\s]');
  static final RegExp _edgeWhitespace = RegExp(r'^\s|\s$');

  static PasswordPolicyResult validate({
    required String currentPassword,
    required String newPassword,
  }) {
    final failures = <PasswordPolicyFailure>{};
    if (newPassword.length < minLength) {
      failures.add(PasswordPolicyFailure.tooShort);
    }
    if (newPassword.length > maxLength) {
      failures.add(PasswordPolicyFailure.tooLong);
    }
    if (!_uppercase.hasMatch(newPassword)) {
      failures.add(PasswordPolicyFailure.missingUppercase);
    }
    if (!_lowercase.hasMatch(newPassword)) {
      failures.add(PasswordPolicyFailure.missingLowercase);
    }
    if (!_digit.hasMatch(newPassword)) {
      failures.add(PasswordPolicyFailure.missingDigit);
    }
    if (!_symbol.hasMatch(newPassword)) {
      failures.add(PasswordPolicyFailure.missingSymbol);
    }
    if (_edgeWhitespace.hasMatch(newPassword)) {
      failures.add(PasswordPolicyFailure.surroundingWhitespace);
    }
    if (newPassword == currentPassword) {
      failures.add(PasswordPolicyFailure.matchesCurrent);
    }
    return PasswordPolicyResult(Set.unmodifiable(failures));
  }
}
