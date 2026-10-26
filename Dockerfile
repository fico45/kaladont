FROM dart:3.13.7 AS build
WORKDIR /kaladont
COPY pubspec.* ./
RUN dart pub get --enforce-lockfile
COPY analysis_options.yaml ./
COPY bin ./bin
COPY lib ./lib
RUN mkdir -p build && dart run nyxx_commands:compile --no-compile --no-format -o build/main.g.dart bin/main.dart
RUN dart compile exe build/main.g.dart -o build/server

FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /kaladont/build/server /app/server
USER 65532:65532
WORKDIR /app
ENTRYPOINT ["/app/server"]
