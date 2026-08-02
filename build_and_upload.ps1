$ErrorActionPreference = 'Stop'

# Upload is handled automatically by android/app/build.gradle.kts after assembleRelease.
Write-Host 'Building release APK (Drive upload runs via Gradle after assemble)...'
flutter build apk --release
if ($LASTEXITCODE -ne 0) {
    throw "flutter build apk --release failed with exit code $LASTEXITCODE"
}

Write-Host 'Success: build finished (APK uploaded to gdrive:AppBuilds/Irodoku.apk if rclone succeeded).'
