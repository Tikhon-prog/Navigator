"""Lightweight CI guard against accidentally committing secrets or local keys."""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
SKIP_DIRS = {".git", ".dart_tool", "build", ".pub-cache", "__pycache__"}
TEXT_SUFFIXES = {
    ".dart", ".py", ".yaml", ".yml", ".json", ".md", ".txt",
    ".gradle", ".kts", ".properties", ".xml", ".sh", ".bat",
    ".plist", ".swift", ".xcconfig", ".pbxproj", ".entitlements",
    ".strings", ".html", ".js", ".ts", ".css", ".toml", ".ini", ".cfg", ".conf",
}
TOKEN_PATTERNS = [
    re.compile(r"\bghp_[A-Za-z0-9]{30,}\b"),
    re.compile(r"\bgithub_pat_[A-Za-z0-9_]{30,}\b"),
    re.compile(r"\bxox[baprs]-[A-Za-z0-9-]{20,}\b"),
    re.compile(r"\bAIza[0-9A-Za-z_-]{30,}\b"),
    re.compile(r"\bsk-[A-Za-z0-9_-]{20,}\b"),
    # Yandex OAuth tokens begin with y0_, y1_, y2_, or y3_.
    re.compile(r"\by[0-3]_[A-Za-z0-9_-]{24,}\b"),
    re.compile(
        r"(?im)\b(?:NAVIGATOR_TOKEN_SECRET|NAVIGATOR_DATA_API_TOKEN|YANDEX_OAUTH_TOKEN|YANDEX_TOKEN|YANDEX_CLIENT_SECRET|CLIENT_SECRET|API_SECRET)\b"
        r"\s*[:=]\s*['\"]?[A-Za-z0-9._-]{24,}"
    ),
    re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
]
FORBIDDEN_FILENAMES = {"key.properties"}
FORBIDDEN_SUFFIXES = {".jks", ".keystore", ".p12", ".pfx", ".pem"}


def main() -> int:
    findings = []
    for path in ROOT.rglob("*"):
        if not path.is_file():
            continue
        relative = path.relative_to(ROOT)
        if any(part in SKIP_DIRS for part in relative.parts):
            continue
        if path.name.startswith(".env") and path.name != ".env.example":
            findings.append(f"{relative}: environment files must not be committed")
            continue
        if path.name in FORBIDDEN_FILENAMES or path.suffix.lower() in FORBIDDEN_SUFFIXES:
            findings.append(f"{relative}: local signing/private-key file must not be committed")
            continue
        if path.suffix.lower() not in TEXT_SUFFIXES:
            continue
        try:
            content = path.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            findings.append(f"{relative}: could not inspect file")
            continue
        for pattern in TOKEN_PATTERNS:
            if pattern.search(content):
                findings.append(f"{relative}: possible credential pattern detected")
                break
    if findings:
        print("Security check failed:")
        for finding in findings:
            print(f" - {finding}")
        return 1
    print("Security check passed: no local env files, signing keys, or known token patterns found.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
