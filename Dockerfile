# Official Dart image: https://hub.docker.com/_/dart
# Specify the Dart SDK base image version using dart:<version> (ex: dart:2.12)
FROM dart:3.1.5 AS build

# Resolve app dependencies.
WORKDIR /kaladont
COPY pubspec.* /kaladont/
RUN dart pub get

# Copy app source code and AOT compile it.
COPY . .
# Ensure packages are still up-to-date if anything has changed
RUN dart pub get --offline
RUN dart run nyxx_commands:compile bin/main.dart
RUN dart compile exe ./out.g.dart -o bin/server

# Build minimal serving image from AOT-compiled `/server` and required system
# libraries and configuration files stored in `/runtime/` from the build stage.
FROM debian:bullseye

COPY --from=build /runtime/ /
COPY --from=build /kaladont/bin/server /app/bin/

# Start server.
WORKDIR /app/bin
CMD ["./server"]
