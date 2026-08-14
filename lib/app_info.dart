// PATCH_S123_APP_INFO: the version shown in-app, kept beside pubspec.yaml's
// `version:` line rather than pulled in with package_info_plus — one more
// plugin, one more Android build surface, for a string we already know at
// build time.
//
// Bump BOTH this and pubspec.yaml together when releasing; the test in
// test/app_info_test.dart fails if they ever drift apart.
const String kAppVersion = '1.1.0';
const int kAppBuildNumber = 2;

const String kSupportTelegram = 't.me/TilawaEhnacher';
const String kSupportEmail = 'Hammer24678@gmail.com';
const String kPrivacyPolicyUrl =
    'https://hammer24678-star.github.io/ayat-studio-app/privacy-policy.html';
