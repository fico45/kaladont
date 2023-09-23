# Official Dart image: https://hub.docker.com/_/dart
# Specify the Dart SDK base image version using dart:<version> (ex: dart:2.12)
FROM dart:stable AS build

# Resolve app dependencies.
WORKDIR /
COPY pubspec.* /

RUN dart pub get

# Copy app source code and AOT compile it.
COPY . .
# Ensure packages are still up-to-date if anything has changed
RUN dart pub get --offline
RUN dart run nyxx_commands:compile bin/main.dart
RUN dart compile exe ./out.g.dart -o bin/server

# Build minimal serving image from AOT-compiled `/server` and required system
# libraries and configuration files stored in `/runtime/` from the build stage.
FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /bin/server /app/bin/

# Include files in the /public directory to enable static asset handling
COPY --from=build /public/ /public
COPY .env /app/bin/.env

# Start server.
EXPOSE 8080
WORKDIR /app/bin
CMD ["./server"]