$p = "D:\sana\lib\main.dart"
$enc = New-Object System.Text.UTF8Encoding($false)
$lines = [System.Collections.Generic.List[string]]([IO.File]::ReadAllLines($p, [Text.Encoding]::UTF8))

if ($lines[2853] -notmatch "'manual_content'") { Write-Error "line 2854 mismatch"; exit 1 }
if ($lines[2859] -notmatch "^\s+\],\s*$") { Write-Error "line 2860 mismatch"; exit 1 }

$block = @(
  '',
  '                                                    const SizedBox(height: 16),',
  '                                                    ListTile(',
  '                                                      leading: const Icon(Icons.install_mobile, color: Colors.teal),',
  '                                                      title: Text(',
  "                                                        tr(language, 'install_sana'),",
  '                                                        style: const TextStyle(',
  '                                                          fontSize: 16,',
  '                                                          fontWeight: FontWeight.bold,',
  '                                                          color: Colors.teal,',
  '                                                        ),',
  '                                                      ),',
  '                                                      trailing: const Icon(Icons.chevron_right, color: Colors.teal),',
  '                                                      onTap: _showAdaptiveInstallDialog,',
  '                                                    ),'
)

$final = New-Object System.Collections.Generic.List[string]
foreach ($l in $lines[0..2858]) { $final.Add($l) }
foreach ($l in $block)          { $final.Add($l) }
foreach ($l in $lines[2859..($lines.Count-1)]) { $final.Add($l) }

[IO.File]::WriteAllLines($p, $final, $enc)
Write-Host "Wrote $($final.Count) lines (was $($lines.Count))"

$chk = [IO.File]::ReadAllLines($p, [Text.Encoding]::UTF8)
for ($i = 2853; $i -lt 2880; $i++) { Write-Host ("{0,5}: {1}" -f ($i+1), $chk[$i]) }
