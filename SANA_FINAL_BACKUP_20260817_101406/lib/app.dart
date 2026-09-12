import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/routes/app_routes.dart';
import 'providers/settings_provider.dart';
import 'providers/language_provider.dart';

class sanaApp extends StatefulWidget {
  const sanaApp({super.key});

  @override
  State<sanaApp> createState() => _sanaAppState();
}

class _sanaAppState extends State<sanaApp> {
  @override
  Widget build(BuildContext context) {
    return Consumer2<SettingsProvider, LanguageProvider>(
      builder: (context, settings, language, child) {
        return MaterialApp(
          title: 'sana',
          debugShowCheckedModeBanner: false,
          themeMode: settings.isDarkMode ? ThemeMode.dark : ThemeMode.light,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.blue, brightness: Brightness.light),
            scaffoldBackgroundColor: Colors.white,
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.blueGrey, brightness: Brightness.dark),
            scaffoldBackgroundColor: Colors.black,
            useMaterial3: true,
          ),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          locale: language.locale,
          supportedLocales: const [
            Locale('en'),
            Locale('ar'),
            Locale('fr'),
            Locale('es'),
            Locale('de'),
            Locale('tr'),
          ],
          localeResolutionCallback: (locale, supportedLocales) {
            if (locale == null) return supportedLocales.first;
            for (final supported in supportedLocales) {
              if (supported.languageCode == locale.languageCode) {
                return supported;
              }
            }
            return supportedLocales.first;
          },
          initialRoute: AppRoutes.splash,
          routes: AppRoutes.routes,
          onGenerateRoute: AppRoutes.onGenerateRoute,
        );
      },
    );
  }
}
