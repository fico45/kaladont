# Local Jenkins with OrbStack

The root `Jenkinsfile` verifies the bot without starting it or deploying it.
It uses Dart 3.13.7 (matching `mise.toml`, Docker and Codemagic) and PostgreSQL 17.
No Discord, Supabase or registry credentials are needed for these checks.

## Agent setup

On the machine running OrbStack, configure a Jenkins agent with:

- The label `docker` and a writable workspace.
- Git, Python 3, a POSIX shell, `tar`, and the Docker CLI on its `PATH`.
- Access to the running OrbStack Docker daemon and outbound access to the Git
  remote, Docker Hub and pub.dev.
- Jenkins Pipeline (including Declarative Pipeline) and Git plugins.

The standard Jenkins image does not include every prerequisite above. If Jenkins
or its agent runs in a container, install Git, Python 3 and the Docker CLI in that
agent image and connect it to the OrbStack Docker socket. Ensure the agent user
has permission to use the socket. Docker access gives the agent control over that
daemon; use a trusted agent and trusted repository branches.

The pipeline uses Docker CLI commands and `docker cp`, so it needs neither the
Docker Pipeline plugin nor matching workspace paths between Jenkins and Docker.
This avoids the shared-filesystem requirement of containerized Jenkins stages
described in the [Jenkins Docker documentation](https://www.jenkins.io/doc/book/pipeline/docker/).
It uses the agent's configured Docker context or `DOCKER_HOST`.

## Create the job

1. Create a **Pipeline** job and select **Pipeline script from SCM**, with **Git**.
2. Set the repository to `git@github.com:fico45/kaladont.git` (or its HTTPS URL).
   Add Jenkins checkout credentials if required and select the branch to verify.
3. Set **Script Path** to `Jenkinsfile`, save, and choose **Build Now**.
4. Configure SCM polling or a webhook in Jenkins if automatic runs are wanted.
   The Jenkinsfile itself does not install a trigger.

A Multibranch Pipeline also works: configure the same repository, credentials and
script path. Keep the agent label `docker`, or change the label in `Jenkinsfile`
to match your agent. Set up the agent and job on the other machine before the
first run; committing this file alone does not provision Jenkins.

## Build behavior

Stages run sequentially and stop at the first failure:

1. Clean the job workspace and check out the selected revision.
2. Create a Dart container, copy only verification inputs, and enforce the lockfile.
3. Check formatting of `bin`, `lib` and `test`.
4. Run `dart analyze --fatal-infos` and `dart test` in separate stages.
5. Create an isolated PostgreSQL container and run `python3 tool/test_database.py`
   against it. The container has no network access or published ports and stores
   data in a temporary filesystem. The runner applies migrations and checks
   rollback, replay protection, concurrency, tenant isolation and dictionary counts.
6. Generate Nyxx metadata, compile AOT and archive `build/server` in Jenkins.
7. Build the production Dockerfile with a unique local image tag.

The archived executable targets the Dart container's Linux architecture (ARM64 on
an Apple Silicon daemon by default); it is not a macOS executable. The production
image contains the runtime libraries needed by the bot.

The pipeline always attempts to remove its Dart/PostgreSQL containers and its
tagged Docker image, including after ordinary failures or cancellation. Jenkins
retains the last ten build records and their archived executable. Docker's shared
build cache and downloaded base images remain. Agent loss or a daemon outage can
prevent cleanup; remove orphaned build resources after restoring connectivity.

This is a verification pipeline: there is no image push, deployment or live bot
execution. The existing GitHub Actions workflows and Codemagic configuration are
unchanged. GitHub Actions does dependency resolution plus separate image
build/push/deployment; Codemagic runs Dart checks and AOT. Only this Jenkinsfile
includes the database regression runner in CI.
