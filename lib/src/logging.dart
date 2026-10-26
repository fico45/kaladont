import 'dart:convert';
import 'dart:io';

void logEvent(
  String level,
  String message, {
  Map<String, Object?> context = const {},
  StackTrace? stackTrace,
}) {
  stderr.writeln(
    jsonEncode({
      'time': DateTime.now().toUtc().toIso8601String(),
      'level': level,
      'process_id': pid,
      'message': message,
      if (context.isNotEmpty) 'context': context,
      if (stackTrace != null) 'stack': stackTrace.toString(),
    }),
  );
}
