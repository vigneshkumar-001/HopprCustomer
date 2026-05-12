# Android release signing (Play App Signing ON)

This project reads signing credentials from `android/key.properties`.

## Important security notes

- Never commit `android/key.properties` to git.
- Never commit keystore files (`*.jks`, `*.keystore`) to git.
- Use strong, unique passwords and store them securely.
- Back up the keystore in at least two secure locations.

## 1) Create a new upload keystore

From the repository root:

```bash
keytool -genkeypair -v -keystore android/keystore/upload-keystore.jks -alias hoppercustoner -keyalg RSA -keysize 2048 -validity 10000
```

## 2) Export upload certificate (PEM)

```bash
keytool -export -rfc -alias hoppercustoner -file upload_certificate.pem -keystore android/keystore/upload-keystore.jks
```

## 3) Register/reset upload key in Play Console

Play Console → your app → Setup → App integrity → App signing → Upload key certificate / Reset upload key  
Upload `upload_certificate.pem`.

## 4) Configure `android/key.properties`

Copy the example file:

```bash
cp android/key.properties.example android/key.properties
```

Edit `android/key.properties` and set:

- `storeFile` (default `keystore/upload-keystore.jks`)
- `storePassword`
- `keyAlias` (default `hoppercustoner`)
- `keyPassword`

## 5) Build AAB

```bash
flutter build appbundle --release
```

## CI (GitHub Actions) - recommended

Do not commit the keystore or `android/key.properties` to git. Store them as GitHub Actions secrets:

- `ANDROID_KEYSTORE_B64` - base64 of `android/keystore/upload-keystore.jks`
- `KEYSTORE_PASSWORD`
- `KEY_PASSWORD`
- `KEY_ALIAS`

Workflow: `.github/workflows/android-release.yml`
