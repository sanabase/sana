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

start = "const map = <String, Map<String, String>>{"
end   = "return map[language]?[key]"

# In current main there are TWO such maps (one for SanaInstallBanner,
# one for _SanaInstallHelp). We only replace the SECOND occurrence.
# Locate both.
def find_all(src, needle):
    idx, out = 0, []
    while True:
        i = src.find(needle, idx)
        if i == -1: break
        out.append(i); idx = i + len(needle)
    return out

curr_starts = find_all(text, start)
if len(curr_starts) != 2:
    raise SystemExit(f"Expected 2 maps, found {len(curr_starts)}")

# Replace both from clean (clean has the same two maps, both good).
clean_starts = find_all(clean, start)
if len(clean_starts) != 2:
    raise SystemExit(f"Clean has {len(clean_starts)} maps, expected 2")

# Replace in reverse order so indices stay valid.
for cs, cc in reversed(list(zip(curr_starts, clean_starts))):
    ce_curr = text.index(end, cs)
    ce_clean = clean.index(end, cc)
    text = text[:cs] + clean[cc:ce_clean].rstrip() + text[ce_curr:]

MAIN.write_text(text, encoding="utf-8")
print("DONE: both const-map blocks replaced.")