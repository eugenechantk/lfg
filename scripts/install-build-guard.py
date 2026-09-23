#!/usr/bin/python3
"""Install a stable FlowDeck supervisor without changing the vendor binary."""
import json
import os
from pathlib import Path
import shlex
import shutil
import time

home = Path.home()
entry = home / '.local/bin/flowdeck'
vendor = home / '.local/share/flowdeck/flowdeck'
install = home / '.local/lib/lfg-build-guard'
marker = '# LFG build guard shim v1'
if not vendor.is_file():
    raise SystemExit('FlowDeck vendor binary is missing: ' + str(vendor))
if entry.is_symlink():
    if entry.resolve() != vendor.resolve():
        raise SystemExit('Unexpected FlowDeck entrypoint; refusing to replace it')
elif entry.exists() and marker not in entry.read_text():
    raise SystemExit('Unrecognized FlowDeck entrypoint; refusing to replace it')
install.mkdir(parents=True, exist_ok=True)
entry.parent.mkdir(parents=True, exist_ok=True)
backup = install / 'flowdeck.original-link.json'
if not backup.exists():
    backup.write_text(json.dumps({'entry': str(entry), 'target': os.readlink(entry) if entry.is_symlink() else None, 'time': time.time()}, indent=2) + '\n')
source = Path(__file__).with_name('build_guard.py')
target = install / 'build_guard.py'
temporary = target.with_suffix('.tmp')
shutil.copyfile(source, temporary)
temporary.chmod(0o755)
temporary.replace(target)
for path, tail in [(entry, ' flowdeck --vendor ' + shlex.quote(str(vendor)) + ' --'),
                   (entry.with_name('lfg-build-guard'), '')]:
    temporary = path.with_name(path.name + '.guard-tmp')
    temporary.write_text('#!/bin/sh\n' + marker + '\nexec /usr/bin/python3 ' + shlex.quote(str(target)) + tail + ' "$@"\n')
    temporary.chmod(0o755)
    temporary.replace(path)
print(json.dumps({'flowdeck': str(entry), 'vendor': str(vendor), 'guard': str(target), 'originalEntrypoint': str(backup)}, indent=2))
