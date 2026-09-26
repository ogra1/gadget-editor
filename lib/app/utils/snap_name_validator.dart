import 'package:flutter/material.dart';

/// Utility class for validating snap names according to snap store requirements
class SnapNameValidator {
  /// Validates a snap name according to snap store rules
  ///
  /// Rules:
  /// - Must start with a lowercase ASCII letter
  /// - Can only contain lowercase letters, numbers, and hyphens
  /// - Must be 40 characters or less
  /// - Cannot start or end with a hyphen
  static ValidationResult validate(String? name) {
    // Check for null or empty
    if (name == null || name.isEmpty) {
      return ValidationResult(
        isValid: false,
        errorMessage: 'Snap name cannot be empty',
      );
    }

    // Check length
    if (name.length > 40) {
      return ValidationResult(
        isValid: false,
        errorMessage: 'Snap name must be 40 characters or less',
      );
    }

    // Check if it starts with a lowercase letter
    if (!name.startsWith(RegExp(r'^[a-z]'))) {
      return ValidationResult(
        isValid: false,
        errorMessage: 'Snap name must start with a lowercase letter',
      );
    }

    // Check if it ends with a hyphen
    if (name.endsWith('-')) {
      return ValidationResult(
        isValid: false,
        errorMessage: 'Snap name cannot end with a hyphen',
      );
    }

    // Check for valid characters (lowercase letters, numbers, hyphens only)
    final validChars = RegExp(r'^[a-z0-9-]+$');
    if (!validChars.hasMatch(name)) {
      return ValidationResult(
        isValid: false,
        errorMessage: 'Snap name can only contain lowercase letters, numbers, and hyphens',
      );
    }

    // Check if it starts with a hyphen
    if (name.startsWith('-')) {
      return ValidationResult(
        isValid: false,
        errorMessage: 'Snap name cannot start with a hyphen',
      );
    }

    // All validations passed
    return ValidationResult(
      isValid: true,
      errorMessage: null,
    );
  }

  /// Helper method to get a formatted error message for display
  static String getErrorMessage(String? name) {
    final result = validate(name);
    return result.errorMessage ?? '';
  }
}

/// Result class for validation operations
class ValidationResult {
  final bool isValid;
  final String? errorMessage;

  ValidationResult({
    required this.isValid,
    this.errorMessage,
  });
}
