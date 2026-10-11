#!/usr/bin/env python3
import argparse, hashlib, json, plistlib, tempfile, zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_JS = ROOT / 'patches' / 'tubetv-stable-v1.js'
DEFAULT_MAP = ROOT / 'patches' / 'youtube-4.54.01.json'
DEFAULT_NATIVE = ROOT / 'patches' / 'youtube-4.54.01-native.hex'

def sha256(data):
    return hashlib.sha256(data).hexdigest()

def sha256_file(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()

def to_int(value):
    return int(value, 0) if isinstance(value, str) else int(value)

def patch_executable(path, js_text, patch_map, native_hex):
    data = bytearray(path.read_bytes())
    base_sha = patch_map['base_executable_sha256']
    got = sha256(data)
    if got != base_sha:
        raise SystemExit(f'Unsupported executable SHA-256: {got}\nExpected: {base_sha}')

    cave = patch_map['cave']
    cave_start = to_int(cave['start'])
    js_start = to_int(cave['js_start'])
    js_capacity = int(cave['js_capacity'])
    native_start = to_int(cave['native_start'])
    native_end = to_int(cave['native_end'])
    js = js_text.strip().encode('utf-8')
    if len(js) > js_capacity:
        raise SystemExit(f'Injection JS is {len(js)} bytes; max is {js_capacity}')
    if any(data[cave_start:native_end]):
        raise SystemExit('Expected code cave is not empty; refusing to patch unknown binary')

    data[cave_start:js_start] = b'yttv\0\0\0\0'
    data[js_start:js_start + js_capacity] = js.ljust(js_capacity, b' ')
    native = bytes.fromhex(native_hex)
    if len(native) != native_end - native_start:
        raise SystemExit('Native support block length does not match patch map')
    data[native_start:native_end] = native

    for patch in patch_map['patches']:
        off = to_int(patch['offset'])
        old = bytes.fromhex(patch['old'])
        new = bytes.fromhex(patch['new'])
        if data[off:off + len(old)] != old:
            raise SystemExit(f"{patch['name']}: unexpected bytes at 0x{off:X}")
        data[off:off + len(new)] = new

    path.write_bytes(data)
    return sha256(data)

def patch_plist(path):
    with path.open('rb') as f:
        info = plistlib.load(f)
    info['CFBundleDisplayName'] = 'TubeTV'
    info['CFBundleIdentifier'] = 'cz.caseycz.tubetv'
    info['CFBundleName'] = 'TubeTV'
    devices = list(info.get('UISupportedDevices') or [])
    for device in ('AppleTV11,1', 'AppleTV6,2', 'AppleTV5,3'):
        if device not in devices:
            devices.append(device)
    info['UISupportedDevices'] = devices
    for item in info.get('CFBundleURLTypes', []):
        if item.get('CFBundleURLName') == 'com.google.ios.youtube':
            item['CFBundleURLName'] = 'cz.caseycz.tubetv'
    with path.open('wb') as f:
        plistlib.dump(info, f, fmt=plistlib.FMT_BINARY, sort_keys=False)

def validate_base_package(src, patch_map):
    package_sha = sha256_file(src)
    expected_package_sha = patch_map.get('reference_package_sha256')
    expected_size = patch_map.get('reference_package_size')
    if expected_package_sha:
        if package_sha == expected_package_sha:
            print('Base package: exact reference Tube.tipa match')
        else:
            print(f'Base package SHA-256 differs from recorded reference: {package_sha}')
            print(f'Reference SHA-256: {expected_package_sha}')
            print('Continuing only if the embedded executable and metadata match the validated base.')
    if expected_size and src.stat().st_size != int(expected_size):
        print(f'Base package size differs from recorded reference: {src.stat().st_size} bytes')
    return package_sha

def validate_base_info(info, patch_map):
    expected_version = patch_map.get('youtube_tvos_version')
    actual_version = info.get('CFBundleShortVersionString') or info.get('CFBundleVersion')
    if expected_version and actual_version != expected_version:
        raise SystemExit(f'Unsupported YouTube tvOS version: {actual_version}\nExpected: {expected_version}')
    expected_bundle = patch_map.get('base_bundle_identifier')
    actual_bundle = info.get('CFBundleIdentifier')
    if expected_bundle and actual_bundle != expected_bundle:
        raise SystemExit(f'Unexpected base bundle identifier: {actual_bundle}\nExpected: {expected_bundle}')

def main():
    parser = argparse.ArgumentParser(description='Build TubeTV from a user-supplied decrypted YouTube tvOS 4.54.01 IPA/TIPA')
    parser.add_argument('input')
    parser.add_argument('-o', '--output', default='TubeTV-Stable.ipa')
    parser.add_argument('--js', default=str(DEFAULT_JS))
    parser.add_argument('--patch-map', default=str(DEFAULT_MAP))
    parser.add_argument('--native-hex', default=str(DEFAULT_NATIVE))
    args = parser.parse_args()

    src, out = Path(args.input), Path(args.output)
    js_path, map_path, native_path = Path(args.js), Path(args.patch_map), Path(args.native_hex)
    for path in (src, js_path, map_path, native_path):
        if not path.is_file():
            raise SystemExit(f'File not found: {path}')

    patch_map = json.loads(map_path.read_text(encoding='utf-8'))
    js_text = js_path.read_text(encoding='utf-8')
    native_hex = native_path.read_text(encoding='utf-8').replace('\n', '').strip()
    js_sha = sha256(js_text.encode('utf-8'))
    validate_base_package(src, patch_map)

    with tempfile.TemporaryDirectory(prefix='tubetv-') as temp:
        root = Path(temp)
        with zipfile.ZipFile(src, 'r') as archive:
            archive.extractall(root)
        apps = list((root / 'Payload').glob('*.app'))
        if len(apps) != 1:
            raise SystemExit(f'Expected one Payload/*.app, found {len(apps)}')
        app = apps[0]
        plist_path = app / 'Info.plist'
        with plist_path.open('rb') as f:
            info = plistlib.load(f)
        validate_base_info(info, patch_map)
        executable = app / info.get('CFBundleExecutable', 'YouTubeUnstable')

        executable_sha = patch_executable(executable, js_text, patch_map, native_hex)
        patch_plist(plist_path)

        if out.exists():
            out.unlink()
        with zipfile.ZipFile(out, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
            for path in sorted(root.rglob('*')):
                if path.is_file():
                    archive.write(path, path.relative_to(root).as_posix())

    print(f'Created: {out}')
    print(f'Executable SHA-256: {executable_sha}')
    if js_sha == patch_map['stable_js_sha256']:
        expected = patch_map['stable_executable_sha256']
        if executable_sha != expected:
            raise SystemExit(f'Result does not match validated stable executable: {expected}')
        print('Baseline check: exact v1.0.0 executable match')
    else:
        print(f'Custom injection JS SHA-256: {js_sha}')

if __name__ == '__main__':
    main()
