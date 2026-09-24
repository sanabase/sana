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

marker = "const Map<String, Map<String, String>> _translations = {"

def extract(src):
    s = src.index(marker)
    e = src.index("String tr(", s)
    return src[s:e].rstrip()

old_block   = extract(text)
clean_block = extract(clean)

newer_english = {
    "disable_reminders": "Disable reminders",
    "enable_reminders": "Enable reminders",
    "saved_successfully": "Saved successfully",
    "reminder_saved_successfully":
        'Reminder "{name}" saved successfully for {date} at {time}.',
    "delete_success": "Deleted successfully",
    "delete_failed": "Delete failed.",
    "reminder_setting_failed": "Reminder setting failed.",
    "error_loading": "Error loading data.",
    "loading": "Loading...",
    "pwa_install_hint": "Install SANA on your phone for reliable reminders.",
    "pwa_step_1": "Tap the Share button at the bottom of Safari.",
    "pwa_step_2": 'Scroll and tap "Add to Home Screen".',
    "pwa_step_3": 'Tap "Add" at the top right.',
}

def dart_quote(s: str) -> str:
    return "'" + s.replace("\\", "\\\\").replace("'", "\\'") + "'"

anchor = "    'reminders_enabled': 'Reminders enabled',"
if anchor not in clean_block:
    raise RuntimeError("English anchor not found in clean block.")

addition = "\n".join(
    f"    '{k}': {dart_quote(v)}," for k, v in newer_english.items()
)

clean_block = clean_block.replace(anchor, anchor + "\n" + addition, 1)

if text.count(marker) != 1:
    raise RuntimeError(f"Expected 1 _translations block, found {text.count(marker)}")

text = text.replace(old_block, clean_block, 1)
MAIN.write_text(text, encoding="utf-8")
print("DONE: _translations replaced.")
print("DONE: source = c38f92a42b6e9bbcbba11674f9bc0c7ab3748e63")
print("DONE: 13 newer English keys preserved.")
print("DONE: nothing else touched.")