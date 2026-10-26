pipeline {
    agent { label 'docker' }

    options {
        skipDefaultCheckout(true)
        disableConcurrentBuilds()
        timeout(time: 30, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '10'))
    }

    stages {
        stage('Checkout') {
            steps {
                deleteDir()
                checkout scm
            }
        }

        stage('Prepare Dart') {
            steps {
                sh 'git --version && python3 --version && docker info > /dev/null'
                script {
                    env.DART_CONTAINER = sh(
                        script: 'docker create --workdir /workspace --entrypoint sleep dart:3.13.7 infinity',
                        returnStdout: true
                    ).trim()
                    env.CI_IMAGE = "kaladont-ci:${env.DART_CONTAINER.take(12)}"
                }
                sh '''
                    docker start "$DART_CONTAINER"
                    tar cf - bin lib test pubspec.yaml pubspec.lock analysis_options.yaml | docker cp - "$DART_CONTAINER:/workspace"
                    docker exec "$DART_CONTAINER" dart --version
                    docker exec "$DART_CONTAINER" dart pub get --enforce-lockfile
                '''
            }
        }

        stage('Formatting') {
            steps {
                sh 'docker exec "$DART_CONTAINER" dart format --output=none --set-exit-if-changed bin lib test'
            }
        }

        stage('Strict analysis') {
            steps {
                sh 'docker exec "$DART_CONTAINER" dart analyze --fatal-infos'
            }
        }

        stage('Dart tests') {
            steps {
                sh 'docker exec "$DART_CONTAINER" dart test'
            }
        }

        stage('Database regressions') {
            steps {
                script {
                    // No published ports or connection to development Supabase.
                    env.DB_CONTAINER = sh(
                        script: 'docker create --network none --tmpfs /var/lib/postgresql/data -e POSTGRES_HOST_AUTH_METHOD=trust postgres:17',
                        returnStdout: true
                    ).trim()
                }
                sh '''
                    docker start "$DB_CONTAINER"
                    python3 tool/test_database.py --container "$DB_CONTAINER"
                '''
            }
        }

        stage('AOT executable') {
            steps {
                sh '''
                    docker exec "$DART_CONTAINER" mkdir -p build
                    docker exec "$DART_CONTAINER" dart run nyxx_commands:compile --no-compile --no-format -o build/main.g.dart bin/main.dart
                    docker exec "$DART_CONTAINER" dart compile exe build/main.g.dart -o build/server
                    mkdir -p build
                    docker cp "$DART_CONTAINER:/workspace/build/server" build/server
                '''
                archiveArtifacts artifacts: 'build/server', fingerprint: true
            }
        }

        stage('Docker build') {
            steps {
                sh 'docker build --tag "$CI_IMAGE" .'
            }
        }
    }

    post {
        always {
            // Only remove resources created by this build, including on failure.
            sh '''
                if [ -n "${DB_CONTAINER:-}" ]; then docker rm -f -v "$DB_CONTAINER"; fi
                if [ -n "${DART_CONTAINER:-}" ]; then docker rm -f -v "$DART_CONTAINER"; fi
                if [ -n "${CI_IMAGE:-}" ]; then
                    if docker image inspect "$CI_IMAGE" > /dev/null 2>&1; then
                        docker image rm "$CI_IMAGE"
                    fi
                fi
            '''
        }
    }
}
