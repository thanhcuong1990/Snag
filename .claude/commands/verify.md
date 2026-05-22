Run build verification for the platforms affected by recent code changes, or for a specific platform if specified.

## Usage
- `/verify`           — auto-detect changed platforms and verify each
- `/verify ios`       — verify iOS only
- `/verify mac`       — verify macOS only
- `/verify android`   — verify Android only
- `/verify all`       — verify all three regardless of changes

## Steps

1. If no argument was given, run `git diff HEAD --name-only` to identify which platforms have changed files:
   - `mac/**` → mac
   - `ios/**`, `Package.swift` → ios
   - `android/**` → android

2. For each affected platform (or the one explicitly requested), run:
   ```
   bash scripts/verify_build.sh <platform>
   ```

3. Carefully read the full build output. Look for:
   - Any line containing `error:` — must be fixed
   - Any line containing `warning:` — must be fixed (builds use `-warnings-as-errors`)
   - Gradle lines starting with `e:` or `w:` — same treatment

4. If any build fails or has warnings:
   - Show the relevant error/warning lines
   - Fix each issue in the source files
   - Re-run `bash scripts/verify_build.sh <platform>` to confirm clean
   - Repeat until all builds pass with zero errors and zero warnings

5. Report the final status for each platform: ✅ clean or ❌ with details.
