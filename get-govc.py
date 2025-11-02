#!/usr/bin/env python3

import argparse
import json
import os
import sys
import tarfile
import urllib.request
import shutil
import subprocess
import warnings
warnings.filterwarnings("ignore", category=RuntimeWarning, module="tarfile")

GITHUB_API = "https://api.github.com/repos/vmware/govmomi/releases"
DEFAULT_BIN_NAME = "govc"
DEFAULT_DIR = os.path.expanduser("~/bin")
DEFAULT_FILENAME = "govc_Linux_x86_64.tar.gz"

def parse_args():
    parser = argparse.ArgumentParser(description="Download the govc binary from GitHub")
    parser.add_argument("-v", "--ver", help="Specify version to download (default: latest)", default="latest")
    parser.add_argument("-n", "--name", help=f"Rename binary (default: {DEFAULT_BIN_NAME})", default=DEFAULT_BIN_NAME)
    parser.add_argument("-d", "--dir", help=f"Directory to extract binary (default: {DEFAULT_DIR})", default=DEFAULT_DIR)
    parser.add_argument("-p", "--print", action="store_true", help="Print available versions and exit")
    parser.add_argument("-q", "--quiet", action="store_true", help="Suppress output except for errors")
    return parser.parse_args()

def version_key(version):
    parts = version.lower().lstrip("v").split(".")
    return [int(part) if part.isdigit() else part for part in parts]

def fetch_govc_releases():
    with urllib.request.urlopen(GITHUB_API) as response:
        return json.load(response)

def get_release_assets():
    releases = fetch_govc_releases()
    asset_map = {}
    for release in releases:
        for asset in release.get("assets", []):
            name = asset.get("name", "")
            if name == DEFAULT_FILENAME:
                url = asset.get("browser_download_url")
                version = url.split("/download/")[1].split("/")[0]
                asset_map[version] = url
    return asset_map

def print_versions(asset_map):
    for version in sorted(asset_map.keys(), key=version_key):
        print(version)

def download_with_progress(url, dest, quiet=False):
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req) as response, open(dest, "wb") as out_file:
        total_size = int(response.info().get("Content-Length", 0))
        downloaded = 0
        block_size = 8192
        while True:
            chunk = response.read(block_size)
            if not chunk:
                break
            out_file.write(chunk)
            downloaded += len(chunk)
            if not quiet and total_size:
                done = int(50 * downloaded / total_size)
                sys.stdout.write(
                    f"\r[{'=' * done}{' ' * (50 - done)}] {downloaded / 1024 / 1024:.1f}MB / {total_size / 1024 / 1024:.1f}MB"
                )
                sys.stdout.flush()
        if not quiet and total_size:
            print()

def extract_govc(tar_path, dir_path, bin_name, quiet=False):
    with tarfile.open(tar_path, "r:gz") as tar:
        member = next((m for m in tar.getmembers() if os.path.basename(m.name) == "govc"), None)
        if not member:
            raise RuntimeError("govc binary not found in tarball.")
        tar.extract(member, path=dir_path)

        extracted_path = os.path.join(dir_path, member.name)
        final_path = os.path.join(dir_path, bin_name)
        if extracted_path != final_path:
            os.rename(extracted_path, final_path)

        try:
            os.chown(final_path, os.getuid(), os.getgid())
        except PermissionError:
            if not quiet:
                print(f"⚠  Could not change ownership of {final_path}")

        os.chmod(final_path, 0o755)
        if not quiet:
            print(f"✅ govc extracted to {final_path} with mode 0755")

        return final_path

def run_govc_version(bin_path, quiet=False):
    try:
        output = subprocess.check_output([bin_path, "version"], stderr=subprocess.STDOUT)
        if not quiet:
            print(output.decode().strip())
    except Exception as e:
        print(f"❌ Failed to run {bin_path} version: {e}", file=sys.stderr)
        sys.exit(1)

def check_existing_govc(bin_path, target_version):
    if not os.path.exists(bin_path):
        return False
    try:
        output = subprocess.check_output([bin_path, "version"], stderr=subprocess.STDOUT).decode().strip()
        # Expected output: govc <version>
        existing_version = output.split(" ")[-1]
        return existing_version == target_version.lstrip("v")
    except (subprocess.CalledProcessError, FileNotFoundError):
        return False

def main():
    args = parse_args()

    try:
        asset_map = get_release_assets()
    except Exception as e:
        print("Fetching govc releases info...", file=sys.stderr)
        print(f"❌ Error: {e}", file=sys.stderr)
        sys.exit(1)

    if not asset_map:
        print("❌ No govc releases found", file=sys.stderr)
        sys.exit(1)

    if args.print:
        print_versions(asset_map)
        return

    if args.ver == "latest":
        version = sorted(asset_map.keys(), key=version_key)[-1]
    else:
        version = next((v for v in asset_map if v == args.ver or v.lstrip("v") == args.ver.lstrip("v")), None)
        if not version:
            print(f"❌ No suitable govc release found for version '{args.ver}'", file=sys.stderr)
            sys.exit(1)

    final_path = os.path.join(args.dir, args.name)
    if check_existing_govc(final_path, version):
        if not args.quiet:
            print(f"✅ govc version {version.lstrip('v')} is already installed at {final_path}")
        return

    url = asset_map[version]
    if not args.quiet:
        print(f"Selected version: {version}")
        print(f"Downloading: {url}")

    os.makedirs(args.dir, exist_ok=True)
    tar_path = os.path.join("/tmp", f"govc-{version}.tar.gz")

    try:
        download_with_progress(url, tar_path, quiet=args.quiet)
        bin_path = extract_govc(tar_path, args.dir, args.name, quiet=args.quiet)
    except Exception as e:
        print(f"❌ Error during download or extraction: {e}", file=sys.stderr)
        sys.exit(1)
    finally:
        if os.path.exists(tar_path):
            os.remove(tar_path)

    run_govc_version(bin_path, quiet=args.quiet)

if __name__ == "__main__":
    main()
