// PATCH_S123_APP_INFO: the version is written in two places — pubspec.yaml
// (what Play Console sees) and lib/app_info.dart (what the Settings screen
// shows). A release where those disagree is a support ticket that is very
// hard to diagnose from a screenshot, so they are checked against each other
// here rather than by remembering.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ayat_studio_app/app_info.dart';

void main() {
  test('kAppVersion and kAppBuildNumber match pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match =
        RegExp(r'^version:\s*(\S+)\+(\d+)\s*$', multiLine: true)
            .firstMatch(pubspec);
    expect(match, isNotNull, reason: 'pubspec.yaml has no version: x.y.z+n');
    expect(match!.group(1), kAppVersion,
        reason: 'lib/app_info.dart kAppVersion is out of date');
    expect(int.parse(match.group(2)!), kAppBuildNumber,
        reason: 'lib/app_info.dart kAppBuildNumber is out of date');
  });

  test('the version is a plain three-part release number', () {
    expect(RegExp(r'^\d+\.\d+\.\d+$').hasMatch(kAppVersion), isTrue,
        reason: 'Play Console rejects anything else as versionName');
    expect(kAppBuildNumber, greaterThan(0));
  });

  test('support and policy links are present and https', () {
    expect(kPrivacyPolicyUrl, startsWith('https://'));
    expect(kSupportEmail, contains('@'));
    expect(kSupportTelegram, isNotEmpty);
  });
}
