// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

bool isTabUnlocked(String userId) =>
    html.window.sessionStorage['qm-unlocked-user'] == userId;
void rememberTabUnlock(String userId) {
  html.window.sessionStorage['qm-unlocked-user'] = userId;
}

void clearTabUnlock() {
  html.window.sessionStorage.remove('qm-unlocked-user');
}
