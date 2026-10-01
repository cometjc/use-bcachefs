# use-bcachefs

Linux bcachefs integration guidance and read-only DKMS/initramfs/GRUB checks.
No runtime Python dependencies. Requires Python >=3.9; individual checks use
system utilities described by their `--help` output. Boot guidance is for
custom initramfs-tools deployments, not an automatic installer or formatter.

## Install the command

```bash
uv tool install git+https://github.com/cometjc/use-bcachefs.git
use-bcachefs --help
use-bcachefs dkms-port-check --help
use-bcachefs grub-canary-check --help
```

For a local checkout use `uv tool install .`. `uv` is an installer, not a
runtime requirement of the installed command.

## Install the skill

Clone this repository into a new `use-bcachefs` directory under your agent's
skill root, for example `~/.agents/skills/use-bcachefs`. Do not overwrite an
existing directory. Keep `SKILL.md` and `references/` together; installing the
Python command alone does not install the agent instructions.

## Verify without host changes

```bash
python3 tests/boot-layout-self-check.py
bash tests/dkms-port-check-self-check.sh
bash tests/grub-canary-check-self-check.sh
```

These tests use fixtures, not real disks. The command checks do not update
fstab, GRUB or initramfs. Read [SKILL.md](SKILL.md) for the relevant references.
