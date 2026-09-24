from pathlib import Path
import subprocess

ROOT = Path(r"D:\sana")
MAIN = ROOT / "lib" / "main.dart"
CLEAN_COMMIT = "c38f92a42b6e9bbcbba11674f9bc0c7ab3748e63"

text  = MAIN.read_text(encoding="utf-8-sig")
clean = subprocess.check_output(
    ["git", "show", f"{CLEAN_COMMIT}:lib/main.dart"],
    cwd=ROOT,
).decode("utf-8")

start = "void _showChromeManualGuide()"
end   = "void _showIosGuide()"

s = text.index(start); e = text.index(end, s)
cs = clean.index(start); ce = clean.index(end, cs)

text = text[:s] + clean[cs:ce].rstrip() + text[e:]
MAIN.write_text(text, encoding="utf-8")
print("DONE: _showChromeManualGuide replaced.")