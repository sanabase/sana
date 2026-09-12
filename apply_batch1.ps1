# ============================================================
# SANA - Batch 1: Header/branding/UI polish + admin button placement
# Run this from PowerShell INSIDE the root of your local "sana"
# git clone (the folder that contains pubspec.yaml).
# ============================================================
$patch = @'
diff --git a/android/app/src/main/AndroidManifest.xml b/android/app/src/main/AndroidManifest.xml
index 79cd912..a9bd4e5 100644
--- a/android/app/src/main/AndroidManifest.xml
+++ b/android/app/src/main/AndroidManifest.xml
@@ -9,7 +9,7 @@
     <uses-permission android:name="android.permission.READ_MEDIA_IMAGES"/>
     <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32"/>
     <application
-        android:label="sana"
+        android:label="SANA"
         android:name="${applicationName}"
         android:icon="@mipmap/ic_launcher">
         <activity
diff --git a/ios/Runner/Info.plist b/ios/Runner/Info.plist
index fc85d50..b713f4d 100644
--- a/ios/Runner/Info.plist
+++ b/ios/Runner/Info.plist
@@ -13,7 +13,7 @@
 	<key>CFBundleInfoDictionaryVersion</key>
 	<string>6.0</string>
 	<key>CFBundleName</key>
-	<string>sana</string>
+	<string>SANA</string>
 	<key>CFBundlePackageType</key>
 	<string>APPL</string>
 	<key>CFBundleShortVersionString</key>
@@ -46,10 +46,10 @@
 	<key>UIApplicationSupportsIndirectInputEvents</key>
 	<true/>
 	<key>NSCameraUsageDescription</key>
-	<string>sana needs camera access so you can take a photo of your medication.</string>
+	<string>SANA needs camera access so you can take a photo of your medication.</string>
 	<key>NSPhotoLibraryUsageDescription</key>
-	<string>sana needs photo library access so you can attach medication photos and documents.</string>
+	<string>SANA needs photo library access so you can attach medication photos and documents.</string>
 	<key>NSMicrophoneUsageDescription</key>
-	<string>sana needs microphone access for voice features.</string>
+	<string>SANA needs microphone access for voice features.</string>
 </dict>
 </plist>
diff --git a/lib/app.dart b/lib/app.dart
index b715766..f90d19a 100644
--- a/lib/app.dart
+++ b/lib/app.dart
@@ -19,7 +19,7 @@ class _sanaAppState extends State<sanaApp> {
     return Consumer2<SettingsProvider, LanguageProvider>(
       builder: (context, settings, language, child) {
         return MaterialApp(
-          title: 'sana',
+          title: 'SANA',
           debugShowCheckedModeBanner: false,
           themeMode: settings.isDarkMode ? ThemeMode.dark : ThemeMode.light,
           theme: ThemeData(
diff --git a/lib/core/routes/app_routes.dart b/lib/core/routes/app_routes.dart
index 1b7b8de..2c16da8 100644
--- a/lib/core/routes/app_routes.dart
+++ b/lib/core/routes/app_routes.dart
@@ -10,6 +10,7 @@ import '../../screens/add_pharmacy_screen.dart';
 import '../../screens/documents_screen.dart';
 import '../../screens/insurance_screen.dart';
 import '../../screens/share_screen.dart';
+import '../../screens/admin_screen.dart';
 
 class AppRoutes {
   AppRoutes._();
@@ -24,6 +25,7 @@ class AppRoutes {
   static const String addPharmacy = '/add-pharmacy';
   static const String documents = '/documents';
   static const String insurance = '/insurance';
+  static const String admin = '/admin';
 
   static final Map<String, WidgetBuilder> routes = {
     splash: (context) => const SplashScreen(),
@@ -42,6 +44,7 @@ class AppRoutes {
     addPharmacy: (context) => const AddPharmacyScreen(),
     documents: (context) => const DocumentsScreen(),
     insurance: (context) => const InsuranceScreen(),
+    admin: (context) => const AdminScreen(),
   };
 
   static Route<dynamic> onGenerateRoute(RouteSettings settings) {
diff --git a/lib/screens/admin_screen.dart b/lib/screens/admin_screen.dart
new file mode 100644
index 0000000..8516448
--- /dev/null
+++ b/lib/screens/admin_screen.dart
@@ -0,0 +1,32 @@
+import 'package:flutter/material.dart';
+
+/// Placeholder Admin screen.
+///
+/// This wires up the admin entry point in the header (button placement).
+/// Full admin functionality — user table, activation, payment confirmation,
+/// expiry/renewal — is implemented in a later pass on top of this screen.
+class AdminScreen extends StatelessWidget {
+  const AdminScreen({super.key});
+
+  @override
+  Widget build(BuildContext context) {
+    return Scaffold(
+      appBar: AppBar(
+        title: const Text('Admin'),
+        backgroundColor: Colors.teal,
+        foregroundColor: Colors.white,
+      ),
+      body: const Center(
+        child: Padding(
+          padding: EdgeInsets.all(24.0),
+          child: Text(
+            'Admin panel coming soon.\n\nUser management, activation, and '
+            'subscription tools will appear here.',
+            textAlign: TextAlign.center,
+            style: TextStyle(fontSize: 16, color: Colors.black54),
+          ),
+        ),
+      ),
+    );
+  }
+}
diff --git a/lib/screens/home_screen.dart b/lib/screens/home_screen.dart
index 117b5aa..3dc8146 100644
--- a/lib/screens/home_screen.dart
+++ b/lib/screens/home_screen.dart
@@ -18,6 +18,7 @@ import 'medication_detail_screen.dart';
 import 'documents_screen.dart';
 import 'insurance_screen.dart';
 import 'sharing_screen.dart';
+import '../core/routes/app_routes.dart';
 
 class HomeScreen extends StatelessWidget {
   const HomeScreen({super.key});
@@ -54,7 +55,7 @@ class HomeScreen extends StatelessWidget {
       builder: (ctx) => AlertDialog(
         title: const Text('Get Your Own Copy'),
         content: const Text(
-          'Unlock the full source code and personal license for sana / SANA.\n\nContact support or complete payment to receive your standalone copy.',
+          'Unlock the full source code and personal license for SANA.\n\nContact support or complete payment to receive your standalone copy.',
         ),
         actions: [
           TextButton(
@@ -338,65 +339,102 @@ class HomeScreen extends StatelessWidget {
                       child: Column(
                         crossAxisAlignment: CrossAxisAlignment.start,
                         children: [
-                          Stack(
-                            alignment: Alignment.center,
+                          Row(
+                            crossAxisAlignment: CrossAxisAlignment.center,
                             children: [
-                              Center(
-                                child: Container(
-                                  padding: const EdgeInsets.symmetric(
-                                      horizontal: 24, vertical: 5),
-                                  decoration: BoxDecoration(
-                                    color: Colors.amber.shade100,
-                                    borderRadius: BorderRadius.circular(20),
-                                    border: Border.all(
-                                        color: Colors.amber.shade700,
-                                        width: 1.5),
-                                    boxShadow: [
-                                      BoxShadow(
-                                        color: Colors.amber.shade700
-                                            .withValues(alpha: 0.15),
-                                        blurRadius: 6,
-                                        offset: const Offset(0, 2),
+                              // Health logo — far left of the header.
+                              Icon(
+                                Icons.health_and_safety_rounded,
+                                size: 28,
+                                color: Colors.teal.shade700,
+                              ),
+                              const SizedBox(width: 6),
+                              // SANA badge, clickable link to the SANA site.
+                              Expanded(
+                                child: Center(
+                                  child: InkWell(
+                                    borderRadius: BorderRadius.circular(14),
+                                    onTap: () async {
+                                      final uri = Uri.parse(
+                                          'https://malazhub.github.io/sana/');
+                                      await launchUrl(uri,
+                                          mode:
+                                              LaunchMode.externalApplication);
+                                    },
+                                    child: Container(
+                                      padding: const EdgeInsets.symmetric(
+                                          horizontal: 14, vertical: 3),
+                                      decoration: BoxDecoration(
+                                        color: Colors.amber.shade100,
+                                        borderRadius:
+                                            BorderRadius.circular(14),
+                                        border: Border.all(
+                                            color: Colors.amber.shade700,
+                                            width: 1),
+                                        boxShadow: [
+                                          BoxShadow(
+                                            color: Colors.amber.shade700
+                                                .withValues(alpha: 0.15),
+                                            blurRadius: 4,
+                                            offset: const Offset(0, 1),
+                                          ),
+                                        ],
+                                      ),
+                                      child: Row(
+                                        mainAxisSize: MainAxisSize.min,
+                                        children: [
+                                          Text(
+                                            'SANA',
+                                            style: TextStyle(
+                                              fontSize: 22,
+                                              fontWeight: FontWeight.bold,
+                                              color: Colors.amber.shade900,
+                                              letterSpacing: 1.2,
+                                            ),
+                                          ),
+                                          const SizedBox(width: 5),
+                                          Icon(Icons.open_in_new,
+                                              size: 13,
+                                              color: Colors.amber.shade900),
+                                        ],
                                       ),
-                                    ],
-                                  ),
-                                  child: Text(
-                                    'SANA',
-                                    style: TextStyle(
-                                      fontSize: 40,
-                                      fontWeight: FontWeight.bold,
-                                      color: Colors.amber.shade900,
-                                      letterSpacing: 2,
                                     ),
                                   ),
                                 ),
                               ),
-                              Positioned(
-                                right: 0,
-                                child: IconButton(
-                                  icon: Icon(Icons.share,
-                                      size: 26, color: Colors.teal.shade900),
-                                  onPressed: () {
-                                    Share.share(
-                                        'https://malazhub.github.io/sana/');
-                                  },
-                                ),
+                              IconButton(
+                                icon: Icon(Icons.share,
+                                    size: 22, color: Colors.teal.shade900),
+                                tooltip: 'Share SANA',
+                                onPressed: () {
+                                  Share.share(
+                                      'https://malazhub.github.io/sana/');
+                                },
+                              ),
+                              IconButton(
+                                icon: Icon(Icons.admin_panel_settings_outlined,
+                                    size: 22, color: Colors.teal.shade900),
+                                tooltip: 'Admin',
+                                onPressed: () {
+                                  Navigator.pushNamed(
+                                      context, AppRoutes.admin);
+                                },
                               ),
                             ],
                           ),
-                          const SizedBox(height: 4),
+                          const SizedBox(height: 2),
                           Center(
                             child: Text(
                               subHeader,
                               textAlign: TextAlign.center,
                               style: TextStyle(
-                                fontSize: 26,
+                                fontSize: 15,
                                 fontWeight: FontWeight.w600,
                                 color: Colors.teal.shade900,
                               ),
                             ),
                           ),
-                          const SizedBox(height: 10),
+                          const SizedBox(height: 8),
                           Expanded(
                             child: Column(
                               children: [
diff --git a/lib/screens/share_screen.dart b/lib/screens/share_screen.dart
index ec840e0..4f5509b 100644
--- a/lib/screens/share_screen.dart
+++ b/lib/screens/share_screen.dart
@@ -88,7 +88,7 @@ class _ShareScreenState extends State<ShareScreen> {
 
     return Scaffold(
       appBar: AppBar(
-        title: const Text('📁 sana Share'),
+        title: const Text('📁 SANA Share'),
         backgroundColor: Colors.teal,
         foregroundColor: Colors.white,
       ),
diff --git a/lib/screens/splash_screen.dart b/lib/screens/splash_screen.dart
index 9d11620..04051e7 100644
--- a/lib/screens/splash_screen.dart
+++ b/lib/screens/splash_screen.dart
@@ -35,7 +35,7 @@ class _SplashScreenState extends State<SplashScreen> {
             ),
             const SizedBox(height: 24),
             const Text(
-              'sana',
+              'SANA',
               style: TextStyle(
                 fontSize: 32,
                 fontWeight: FontWeight.bold,
diff --git a/linux/my_application.cc b/linux/my_application.cc
index 42c7682..6a3abbd 100644
--- a/linux/my_application.cc
+++ b/linux/my_application.cc
@@ -40,11 +40,11 @@ static void my_application_activate(GApplication* application) {
   if (use_header_bar) {
     GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
     gtk_widget_show(GTK_WIDGET(header_bar));
-    gtk_header_bar_set_title(header_bar, "sana");
+    gtk_header_bar_set_title(header_bar, "SANA");
     gtk_header_bar_set_show_close_button(header_bar, TRUE);
     gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
   } else {
-    gtk_window_set_title(window, "sana");
+    gtk_window_set_title(window, "SANA");
   }
 
   gtk_window_set_default_size(window, 1280, 720);
diff --git a/windows/runner/Runner.rc b/windows/runner/Runner.rc
index ab123c7..6c59eb2 100644
--- a/windows/runner/Runner.rc
+++ b/windows/runner/Runner.rc
@@ -90,12 +90,12 @@ BEGIN
         BLOCK "040904e4"
         BEGIN
             VALUE "CompanyName", "com.example" "\0"
-            VALUE "FileDescription", "sana" "\0"
+            VALUE "FileDescription", "SANA" "\0"
             VALUE "FileVersion", VERSION_AS_STRING "\0"
-            VALUE "InternalName", "sana" "\0"
+            VALUE "InternalName", "SANA" "\0"
             VALUE "LegalCopyright", "Copyright (C) 2026 com.example. All rights reserved." "\0"
             VALUE "OriginalFilename", "sana.exe" "\0"
-            VALUE "ProductName", "sana" "\0"
+            VALUE "ProductName", "SANA" "\0"
             VALUE "ProductVersion", VERSION_AS_STRING "\0"
         END
     END

'@

$patchFile = Join-Path $env:TEMP "sana_batch1.patch"
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($patchFile, $patch, $utf8NoBom)

if (-not (Test-Path ".\pubspec.yaml")) {
  Write-Host "ERROR: run this from the root of your local sana repo (folder with pubspec.yaml)." -ForegroundColor Red
  exit 1
}

git apply --check $patchFile
if ($LASTEXITCODE -ne 0) {
  Write-Host "Patch does not apply cleanly - no files were changed. Paste this error back to Claude." -ForegroundColor Red
  exit 1
}

git apply $patchFile
Write-Host "Batch 1 applied successfully. Review with: git status  /  git diff" -ForegroundColor Green
Write-Host "When you're happy with it, commit it yourself, e.g.:" -ForegroundColor Cyan
Write-Host '  git add -A' -ForegroundColor Cyan
Write-Host '  git commit -m "Batch 1: header/branding UI polish + admin button placement"' -ForegroundColor Cyan
Write-Host '  git push' -ForegroundColor Cyan
