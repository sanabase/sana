# ============================================================
# BATCH 2: Localization & Stock Labels
# ============================================================

# 1. Update medication_detail_screen.dart - add Stock label
$medDetailPath = "lib\screens\medication_detail_screen.dart"
$medContent = Get-Content $medDetailPath -Raw

# Find the qtyLbl declaration and replace it
$oldQty = 'String qtyLbl = "Quantity";'
$newQty = @'
    String qtyLbl = 'Stock';
    if (code == 'ar') qtyLbl = 'المخزون';
    else if (code == 'es') qtyLbl = 'Stock';
    else if (code == 'fr') qtyLbl = 'Stock';
    else if (code == 'de') qtyLbl = 'Bestand';
    else if (code == 'tr') qtyLbl = 'Stok';
    else if (code == 'hi') qtyLbl = 'स्टॉक';
    else if (code == 'zh') qtyLbl = '库存';
'@

$medContent = $medContent -replace [regex]::Escape($oldQty), $newQty
Set-Content $medDetailPath $medContent

Write-Host "✅ Updated medication_detail_screen.dart" -ForegroundColor Green

# 2. Update sharing_service.dart - simpler approach
$shareServicePath = "lib\services\sharing_service.dart"
$shareServiceContent = Get-Content $shareServicePath -Raw

# Add languageCode parameter to shareMedications
$oldParam = 'static Future<void> shareMedications({'
$newParam = @'
static Future<void> shareMedications({
    String? languageCode,
'@
$shareServiceContent = $shareServiceContent -replace [regex]::Escape($oldParam), $newParam

# Replace the header line with language-aware version
$oldHeader = 'reportText.writeln("📋 sana Medical Record Report");'
$newHeader = @'
    if (languageCode == 'ar') {
      reportText.writeln('📋 تقرير السجلات الطبية');
    } else if (languageCode == 'es') {
      reportText.writeln('📋 Informe de Registros Médicos');
    } else if (languageCode == 'fr') {
      reportText.writeln('📋 Rapport des Dossiers Médicaux');
    } else if (languageCode == 'de') {
      reportText.writeln('📋 Bericht der Krankenakten');
    } else if (languageCode == 'tr') {
      reportText.writeln('📋 Tıbbi Kayıt Raporu');
    } else if (languageCode == 'hi') {
      reportText.writeln('📋 मेडिकल रिकॉर्ड रिपोर्ट');
    } else if (languageCode == 'zh') {
      reportText.writeln('📋 医疗记录报告');
    } else {
      reportText.writeln('📋 sana Medical Record Report');
    }
'@
$shareServiceContent = $shareServiceContent -replace [regex]::Escape($oldHeader), $newHeader

Set-Content $shareServicePath $shareServiceContent

Write-Host "✅ Updated sharing_service.dart" -ForegroundColor Green
Write-Host "`n✅ BATCH 2 COMPLETE!" -ForegroundColor Green