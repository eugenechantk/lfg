#!/usr/bin/env python3
"""Build a local Codex desktop image. No user credentials enter its build context."""
import argparse, hashlib, json, os, pathlib, shutil, subprocess, urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[2]
DEFAULT_CUA = ROOT / '.codex/tools/cua/Applications/Cua Spaces.app/Contents/MacOS/cua'
DOCKER = shutil.which('docker') or '/Applications/Docker.app/Contents/Resources/bin/docker'
SEED = 'lfg-codex-image-seed'
PINS = {'node': '24.21.0', 'codex-acp': '1.13.1', 'acp-sdk': '1.5.0', 'mcp-remote': '0.14.3'}
GOG_VERSION = '0.45.0'

def run(args, **kwargs):
    return subprocess.run([str(a) for a in args], check=True, text=True, **kwargs)

def fetch(url):
    with urllib.request.urlopen(url, timeout=90) as response:
        return response.read()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cua', default=str(DEFAULT_CUA) if DEFAULT_CUA.exists() else 'cua')
    parser.add_argument('--tag', default='lfg-cua-codex:1')
    args = parser.parse_args()
    cache = ROOT / '.codex/tools/cua-codex-build'
    (cache / 'tools').mkdir(parents=True, exist_ok=True)
    probe = subprocess.run([DOCKER, 'inspect', SEED], capture_output=True, text=True)
    if probe.returncode:
        run([args.cua, 'spaces', 'create', 'linux', '--name', SEED, '--on', 'local', '--kind', 'container', '--runtime', 'runc'])
    else:
        state = json.loads(probe.stdout)[0]['State']
        if state.get('Paused'): run([DOCKER, 'unpause', SEED])
        elif not state.get('Running'): run([DOCKER, 'start', SEED])
    run([args.cua, 'agent', 'ensure', 'local:' + SEED, 'openai-codex', 'acp-sdk', 'mcp-remote'])
    for tool, version in PINS.items():
        run([DOCKER, 'exec', SEED, 'test', '-f', f'/home/cua/.cua/tools/{tool}/{version}/.cua-installed'])
        run([DOCKER, 'cp', f'{SEED}:/home/cua/.cua/tools/{tool}', cache / 'tools/'])
    arch = run([DOCKER, 'image', 'inspect', 'ghcr.io/trycua/linux@sha256:fd00735ceb6c65ab628d962640068c9f63076a49a62d86f6b6eb5ac4bbcbbf6b', '--format', '{{.Architecture}}'], capture_output=True).stdout.strip()
    if arch != 'arm64': raise SystemExit('This profile currently targets the Pro’s ARM64 runtime.')
    archive = f'gogcli_{GOG_VERSION}_linux_{arch}.tar.gz'
    release = f'https://github.com/openclaw/gogcli/releases/download/v{GOG_VERSION}/'
    checksums = fetch(release + 'checksums.txt').decode()
    expected = next(line.split()[0] for line in checksums.splitlines() if line.split()[-1] == archive)
    tar = cache / 'gog.tar.gz'
    if not tar.exists() or hashlib.sha256(tar.read_bytes()).hexdigest() != expected:
        tar.write_bytes(fetch(release + archive))
    if hashlib.sha256(tar.read_bytes()).hexdigest() != expected: raise SystemExit('gog checksum mismatch')
    shutil.copyfile(ROOT / 'infra/cua-codex/config.toml', cache / 'config.toml')
    run([DOCKER, 'build', '--platform', 'linux/arm64', '-t', args.tag, '-f', ROOT / 'infra/cua-codex/Dockerfile', cache])
    run([DOCKER, 'pause', SEED])
    print(json.dumps({'image': args.tag, 'tools': PINS, 'gog': GOG_VERSION, 'gog_sha256': expected}))

if __name__ == '__main__': main()
