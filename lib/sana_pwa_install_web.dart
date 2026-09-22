// lib/sana_pwa_install_web.dart
import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

class SanaPwaInstall {
  static Future<bool> canInstallNow() async {
    if (!kIsWeb) return false;
    try {
      final prompt = globalContext.getProperty<JSAny?>('__sanaPwaPrompt'.toJS);
      return prompt != null;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isInstalled() async {
    if (!kIsWeb) return false;
    try {
      final installed =
          globalContext.getProperty<JSAny?>('__sanaPwaInstalled'.toJS);
      if (installed != null) return true;

      final media = web.window.matchMedia('(display-mode: standalone)');
      if (media.matches) return true;

      final navStandalone = globalContext
          .getProperty<JSObject?>('navigator'.toJS)
          ?.getProperty<JSAny?>('standalone'.toJS);
      if (navStandalone != null) {
        final asBool = navStandalone.dartify();
        if (asBool == true) return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  static bool _isIos() {
    try {
      final ua = web.window.navigator.userAgent.toLowerCase();
      if (ua.contains('iphone') || ua.contains('ipad') || ua.contains('ipod')) {
        return true;
      }
      if (ua.contains('macintosh') && web.window.navigator.maxTouchPoints > 1) {
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  static bool _isSafari() {
    try {
      final ua = web.window.navigator.userAgent.toLowerCase();
      if (!ua.contains('safari')) return false;
      if (ua.contains('chrome') || ua.contains('crios')) return false;
      if (ua.contains('fxios') || ua.contains('edgios')) return false;
      return true;
    } catch (_) {
      return false;
    }
  }

  static bool _isAndroid() {
    try {
      final ua = web.window.navigator.userAgent.toLowerCase();
      return ua.contains('android');
    } catch (_) {
      return false;
    }
  }

  static bool _isChrome() {
    try {
      final ua = web.window.navigator.userAgent.toLowerCase();
      if (ua.contains('edg')) return false;
      if (ua.contains('opr')) return false;
      return ua.contains('chrome') || ua.contains('crios');
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isIosSafari() async {
    if (!kIsWeb) return false;
    return _isIos() && _isSafari();
  }

  static Future<bool> isAndroidChrome() async {
    if (!kIsWeb) return false;
    return _isAndroid() && _isChrome();
  }

  static Future<String> triggerInstall() async {
    if (!kIsWeb) return 'NOT_WEB';
    try {
      final prompt =
          globalContext.getProperty<JSObject?>('__sanaPwaPrompt'.toJS);
      if (prompt == null) return 'NO_PROMPT';
      prompt.callMethod<JSAny?>('prompt'.toJS);
      globalContext.setProperty('__sanaPwaPrompt'.toJS, null);
      return 'OK';
    } catch (e) {
      return 'ERROR: $e';
    }
  }

  static Future<bool> canInstallNow2() async {
    if (!kIsWeb) return false;
    try {
      final prompt = globalContext.getProperty<JSAny?>('__sanaPwaPrompt'.toJS);
      return prompt != null;
    } catch (_) {
      return false;
    }
  }
}
