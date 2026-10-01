"""Reference contract; no host mounts or credentials accessed."""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
skill = (root / "SKILL.md").read_text()
reference = root / "references/boot-layout.md"
assert reference.exists(), "missing current boot-layout reference"
text = reference.read_text()
for required in (
    "bcachefs_subvol", "subvol=", "@root", "@home", "@docker",
    "local-bottom", "--make-rprivate", "umount", "Emergency",
    "panic=5", "one-shot", "rollback", "0700", "fstab", "VM",
):
    assert required in text, required
assert "references/boot-layout.md" in skill
for path in (root / "SKILL.md", reference, root / "README.md"):
    content = path.read_text()
    assert not re.search(r"/home/(?!user(?:/|\b))[a-z][\w-]*", content), path.name
    assert not re.search(r"\b[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\b", content), path.name
assert "bcachefs 上放 swapfile 永遠失敗" not in skill, "unversioned absolute claim"
print("PASS: current layout, rollout safeguards and portable examples")
