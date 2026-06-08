import 'package:flutter/foundation.dart';

// Platform detection yang aman untuk web (tidak pakai dart:io)
bool get isWeb => kIsWeb;
bool get isAndroid =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
bool get isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
bool get isMobile => isAndroid || isIOS;
