import 'dart:convert';
import 'dart:io';

void logEvent(String level, String message, {StackTrace? stackTrace}) {
  stderr.writeln(
    jsonEncode({
      'time': DateTime.now().toUtc().toIso8601String(),
      'level': level,
      'message': message,
      if (stackTrace != null) 'stack': stackTrace.toString(),
    }),
  );
}
