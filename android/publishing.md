# Publishing Snag to Maven Central

This guide explains how to publish the `snag` library to Maven Central using the `vanniktech` Maven Publish plugin already configured in the project.

## 1. Prerequisites

- A Sonatype account with access to the `io.github.thanhcuong1990` namespace.
- GPG installed on your machine for signing the artifacts.
- Generated GPG keys (Secret Key Ring file, Key ID, and Password).

## 2. Configuration

Create or update your `~/.gradle/gradle.properties` (recommended for security) or the local `android/gradle.properties` with the following variables:

```properties
# Sonatype Central Portal (Central Portal)
mavenCentralUsername=<YOUR_SONATYPE_USERNAME_OR_TOKEN_ID>
mavenCentralPassword=<YOUR_SONATYPE_PASSWORD_OR_TOKEN_PASSWORD>

# GPG Signing
signing.keyId=<SHORT_KEY_ID>
signing.password=<GPG_KEY_PASSWORD>
signing.secretKeyRingFile=/Users/hv/.gnupg/secring.gpg
```

> [!IMPORTANT] > **Use absolute paths**: Gradle does not expand `~` to your home directory in `gradle.properties`. You must use the full absolute path (e.g., `/Users/hv/.gnupg/secring.gpg`).
> For modern GPG, you might need to export your subkey to a file:
> `gpg --export-secret-keys <KEY_ID> > secret.gpg`
> Then set `signing.secretKeyRingFile=/path/to/secret.gpg`.

## 3. Publishing Tasks

Run the following commands from the `android` directory:

### Publish to local Maven repository

Verify the artifacts locally before pushing to remote.

```bash
./gradlew :snag:publishToMavenLocal
```

Artifacts will be available at `~/.m2/repository/io/github/thanhcuong1990/snag/1.0.16/`.

### Publish to Maven Central

This will upload the artifacts to Sonatype Central.

```bash
./gradlew :snag:publishAllPublicationsToMavenCentralRepository
```

## 4. Finalizing

Log in to the [Sonatype Central Portal](https://central.sonatype.com/) to release the publication if `automaticRelease = false` is set (which it is currently in `build.gradle.kts`).

## 5. Usage

Once published and synced (can take up to 30 mins), users can add it to their `build.gradle`:

```kotlin
implementation("io.github.thanhcuong1990:snag:1.0.16")
```
