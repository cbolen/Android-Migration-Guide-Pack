# Toolchain Upgrade Guide: JDK → Gradle → AGP

Before raising `compileSdk` or `targetSdk`, the build toolchain must support the target API level.
This is a prerequisite step that should be completed on its own branch, reviewed, and merged
before the API-level migration begins. Mixing toolchain upgrades with API behaviour changes makes
regressions very hard to isolate.

---

## The Dependency Chain

```
JDK version
  └── Gradle version
        └── Android Gradle Plugin (AGP) version
              └── compileSdk / targetSdk
                    └── Kotlin plugin version
                          └── Jetpack library versions
```

Each layer has a minimum version requirement imposed by the layer above it. You cannot skip
levels — an AGP 4.x project cannot jump directly to AGP 8.x without intermediate steps.

---

## Compatibility Matrix

| AGP | Min Gradle | Min JDK | Max compileSdk |
|---|---|---|---|
| 4.2.x | 6.7.1 | 8 | 31 |
| 7.0.x | 7.0 | 11 | 32 |
| 7.1.x | 7.2 | 11 | 32 |
| 7.2.x | 7.3.3 | 11 | 32 |
| 7.3.x | 7.4 | 11 | 33 |
| 7.4.x | 7.5 | 11 | 33 |
| 8.0.x | 8.0 | 17 | 34 |
| 8.1.x | 8.0 | 17 | 34 |
| 8.2.x | 8.2 | 17 | 35 |
| 8.3.x | 8.4 | 17 | 35 |
| 8.4.x | 8.6 | 17 | 35 |
| 8.5.x | 8.7 | 17 | 35 |

> **Rule of thumb:** to reach `compileSdk 35` you need AGP 8.2+ and JDK 17.
> To reach `compileSdk 33` you need AGP 7.3+.

### Kotlin Plugin Compatibility

| Kotlin | Min AGP |
|---|---|
| 1.8.x | 7.1.3 |
| 1.9.x | 7.4.2 |
| 2.0.x | 8.3.0 |
| 2.1.x | 8.3.0 |

---

## Upgrade Order

Work through these steps in sequence. Complete and validate each step before moving to the next.
Each step should be its own commit so it is independently revertible.

### Step 1 — Install JDK 17

AGP 8.x will not build with JDK 11 or earlier.

In Android Studio: **File → Project Structure → SDK Location → JDK Location**
Select or download JDK 17 (Jetbrains Runtime 17 is bundled with recent Android Studio versions).

Verify on the command line:
```bash
java -version
# should report: openjdk version "17.x.x"
```

Set `JAVA_HOME` in your shell profile if running Gradle from the terminal:
```bash
export JAVA_HOME=/path/to/jdk17
```

In `gradle.properties`, pin the JDK for the Gradle daemon:
```properties
org.gradle.java.home=/path/to/jdk17
```

---

### Step 2 — Upgrade the Gradle Wrapper

Update `gradle/wrapper/gradle-wrapper.properties`:
```properties
distributionUrl=https\://services.gradle.org/distributions/gradle-8.7-bin.zip
```

Or run:
```bash
./gradlew wrapper --gradle-version=8.7
```

Validate:
```bash
./gradlew --version
# should report: Gradle 8.7
```

---

### Step 3 — Upgrade AGP

The right strategy depends on where you are starting from:

**Starting on AGP 7.x — jump straight to the latest 8.x**
The 7→8 breaking changes are well-documented and largely mechanical. The AGP Upgrade Assistant
handles this jump reliably in one pass. There is no benefit in stopping at 8.0 when your
target is 8.5 — just go to the latest.

**Starting on AGP 4.x — two hops: 4.x → 7.x, then 7.x → 8.x**
The 4→7 gap involves more manual work (namespace migration, `compile` → `implementation`,
significant DSL changes) and the Upgrade Assistant is less reliable across that distance.
Stopping at 7.x first means each set of breakages is isolated and easier to diagnose before
taking the next step.

**Never mix an AGP upgrade with `targetSdk` bumps in the same branch.** AGP changes affect
the build pipeline; `targetSdk` changes affect runtime behaviour. A crash or test failure in
a mixed branch is ambiguous — you cannot tell which layer caused it. Always get the toolchain
to its final version and validated before starting the API-level migration.

In `build.gradle` (project level):
```groovy
// Before
classpath 'com.android.tools.build:gradle:4.2.2'

// After (example: moving to 7.4.2)
classpath 'com.android.tools.build:gradle:7.4.2'
```

Or in `libs.versions.toml`:
```toml
[versions]
agp = "8.4.2"

[plugins]
android-application = { id = "com.android.application", version.ref = "agp" }
```

#### Use the AGP Upgrade Assistant

Android Studio includes an automated upgrade tool:
**Tools → AGP Upgrade Assistant**

It handles many of the mechanical changes automatically:
- Migrates deprecated DSL properties
- Adds the `namespace` property to module-level `build.gradle` files
- Updates `packagingOptions` → `packaging`
- Migrates `compileSdkVersion` / `targetSdkVersion` to `compileSdk` / `targetSdk` (integer form)
- Flags anything it cannot fix automatically

Run it once per major version hop. Review every change it makes before committing.

---

### Step 4 — Fix AGP Breaking Changes

Common issues encountered between major AGP versions:

#### AGP 4.x → 7.x

**`namespace` required in module build files (AGP 7.3+)**
```groovy
// Before — namespace was implicit from the manifest package attribute
android {
    compileSdkVersion 30
}

// After
android {
    namespace "com.example.inventoryapp"
    compileSdk 33
}
```

**`buildConfig` disabled by default (AGP 8.0+)**
```groovy
android {
    buildFeatures {
        buildConfig = true  // add this if your code references BuildConfig
    }
}
```

**`packagingOptions` renamed to `packaging`**
```groovy
// Before
packagingOptions {
    exclude 'META-INF/LICENSE'
}

// After
packaging {
    resources.excludes += 'META-INF/LICENSE'
}
```

**`compile` configuration removed**
```groovy
// Before
compile 'androidx.appcompat:appcompat:1.3.1'

// After
implementation 'androidx.appcompat:appcompat:1.3.1'
```

#### AGP 7.x → 8.x

**Integer SDK versions required**
```groovy
// Before
compileSdkVersion 33
targetSdkVersion 33
minSdkVersion 26

// After
compileSdk 33
targetSdk 33
minSdk 26
```

**`javaCompileOptions.annotationProcessorOptions` moved**
```groovy
// Before
android {
    defaultConfig {
        javaCompileOptions {
            annotationProcessorOptions { ... }
        }
    }
}

// After — use KSP instead of KAPT where possible
```

---

### Step 5 — Upgrade the Kotlin Plugin

The Kotlin plugin version must be compatible with your AGP version (see matrix above).

In `build.gradle` (project level):
```groovy
// Before
classpath "org.jetbrains.kotlin:kotlin-gradle-plugin:1.7.10"

// After
classpath "org.jetbrains.kotlin:kotlin-gradle-plugin:1.9.24"
```

Or in `libs.versions.toml`:
```toml
[versions]
kotlin = "1.9.24"

[plugins]
kotlin-android = { id = "org.jetbrains.kotlin.android", version.ref = "kotlin" }
```

**`jvmTarget` and `sourceCompatibility` must be aligned:**
```groovy
compileOptions {
    sourceCompatibility JavaVersion.VERSION_17
    targetCompatibility JavaVersion.VERSION_17
}
kotlinOptions {
    jvmTarget = '17'
}
```

---

### Step 6 — Upgrade Jetpack Library Versions

With a new AGP and Kotlin version in place, update Jetpack dependencies to versions that are
compatible with the new compileSdk. Old library versions may produce deprecation errors or fail
to compile against newer API levels.

Minimum recommended versions for targeting API 35:

| Library | Min version |
|---|---|
| `androidx.core:core-ktx` | 1.13.0 |
| `androidx.appcompat:appcompat` | 1.7.0 |
| `com.google.android.material:material` | 1.12.0 |
| `androidx.lifecycle:lifecycle-runtime-ktx` | 2.8.0 |
| `androidx.activity:activity-ktx` | 1.9.0 |
| `androidx.constraintlayout:constraintlayout` | 2.1.4 |
| `androidx.recyclerview:recyclerview` | 1.3.2 |
| `androidx.work:work-runtime-ktx` | 2.9.0 |

> `activity-ktx 1.9.0` is required for `OnBackPressedCallback` and the
> `registerForActivityResult` APIs used in the API-level migration.

---

### Step 7 — Validate the Build

After each step, confirm the project still compiles and tests pass before proceeding:

```bash
./gradlew assembleDebug
./gradlew lint
./gradlew test
```

Key things to verify:
- No `BUILD FAILED` errors
- No new `Error` severity lint issues introduced by the toolchain change
- `BuildConfig` fields still accessible if used
- ProGuard / R8 rules still valid (AGP 8 changed some default R8 behaviour)

---

## Common Gotchas

**ProGuard / R8 rule changes between AGP versions**
AGP 8 enables full R8 mode by default in release builds, which is more aggressive than the
shrinking in AGP 7. If your release build crashes but debug does not, check R8 rules first.
Add `-dontoptimize` temporarily to isolate the issue, then add specific keep rules.

**Annotation processors (KAPT) and AGP 8**
KAPT is slower and has known issues with incremental compilation in AGP 8. Migrate annotation
processors to KSP (Kotlin Symbol Processing) where the library supports it. Room, Hilt, and
Glide all have KSP support.

```toml
# libs.versions.toml
ksp = "1.9.24-1.0.20"
```

```groovy
// build.gradle — replace kapt with ksp
plugins {
    id 'com.google.devtools.ksp' version '1.9.24-1.0.20'
}
// Replace: kapt "androidx.room:room-compiler:$room_version"
ksp "androidx.room:room-compiler:$room_version"
```

**Version catalog migration**
AGP 8 works best with `libs.versions.toml` (Gradle version catalogs). If your project still
uses hardcoded version strings in `build.gradle`, consider migrating to a version catalog at
this point — Android Studio can generate one from your existing dependencies via
**File → Project Structure → Suggestions**.

**Gradle configuration cache**
AGP 8 has improved support for Gradle's configuration cache, which significantly speeds up
incremental builds. Enable it in `gradle.properties`:
```properties
org.gradle.configuration-cache=true
```
Some plugins are not yet compatible — the build will tell you which ones on first run.

---

## Suggested Branch Strategy

**Starting on AGP 7.x (jump straight to latest 8.x):**
```
main
 └── chore/toolchain-jdk17          ← Steps 1-2: JDK + Gradle wrapper
      └── chore/agp-8x              ← Steps 3-4: AGP 7→8 in one hop + fixes
           └── chore/kotlin          ← Step 5: Kotlin upgrade
                └── chore/deps       ← Step 6: Jetpack versions
```

**Starting on AGP 4.x (two hops):**
```
main
 └── chore/toolchain-jdk17          ← Steps 1-2: JDK + Gradle wrapper
      └── chore/agp-7x              ← Steps 3-4: AGP 4→7 + fixes
           └── chore/agp-8x         ← Steps 3-4: AGP 7→8 + fixes
                └── chore/kotlin     ← Step 5: Kotlin upgrade
                     └── chore/deps  ← Step 6: Jetpack versions
```

Each branch targets the previous one as its base. Once all are reviewed and merged, the
API-level migration (targetSdk bumps) can begin on a clean foundation.

---

## References

- [AGP release notes](https://developer.android.com/build/releases/gradle-plugin)
- [AGP / Gradle / JDK compatibility matrix](https://developer.android.com/build/releases/gradle-plugin#updating-plugin)
- [Kotlin / AGP compatibility](https://kotlinlang.org/docs/gradle-configure-project.html#apply-the-plugin)
- [Migrate to KSP](https://developer.android.com/build/migrate-to-ksp)
- [Gradle version catalogs](https://docs.gradle.org/current/userguide/version_catalogs.html)
- [R8 full mode](https://developer.android.com/build/shrink-code#enable-fullmode)
