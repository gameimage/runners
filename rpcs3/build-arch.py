#!/usr/bin/env python3

######################################################################
# @author      : Ruan E. Formigoni (ruanformigoni@gmail.com)
# @file        : build-arch
# @description : Build rpcs3 distribution layers
######################################################################

import json
import subprocess
import sys
import shutil
import re
from pathlib import Path
from collections import defaultdict

SCRIPT_DIR = Path(__file__).parent


def fetch_rpcs3_urls():
  """
  Fetch download URLs for RPCS3 AppImages from GitHub releases.

  Returns:
    Tuple of (stable_urls, unstable_urls) where stable are from non-draft and non-prerelease
    and unstable are from prerelease releases
  """
  result = subprocess.run(
    ["gh", "api", "--paginate", "repos/RPCS3/rpcs3-binaries-linux/releases"],
    capture_output=True,
    text=True
  )

  if result.returncode != 0:
    print(f"Error fetching RPCS3 releases: {result.stderr}", file=sys.stderr)
    return [], []

  try:
    releases = json.loads(result.stdout)
    stable_urls = []
    unstable_urls = []

    for release in releases:
      is_draft = release.get("draft", False)
      is_prerelease = release.get("prerelease", False)

      # Skip draft releases
      if is_draft:
        continue

      for asset in release.get("assets", []):
        url = asset.get("browser_download_url", "")
        if url.endswith(".AppImage"):
          if is_prerelease:
            unstable_urls.append(url)
          else:
            stable_urls.append(url)

    return stable_urls, unstable_urls
  except json.JSONDecodeError as e:
    print(f"Error parsing JSON: {e}", file=sys.stderr)
    return [], []


def get_latest_per_minor_version(urls, count=10):
  """
  Get the latest version from each minor version series.
  For example: 0.0.38-max, 0.0.37-max, 0.0.36-max, etc.

  Args:
    urls: List of download URLs
    count: Number of minor versions to keep (default: 10)

  Returns:
    List of URLs for the latest patch version of each minor version
  """
  # Group URLs by major.minor version
  versions = defaultdict(list)

  for url in urls:
    filename = Path(url).name
    # Try to extract version pattern (e.g., v0.0.38-16857)
    match = re.search(r'v?(\d+)\.(\d+)\.(\d+)-(\d+)', filename)
    if match:
      major = int(match.group(1))
      minor = int(match.group(2))
      patch = int(match.group(3))
      build = int(match.group(4))
      minor_key = f"{major}.{minor}.{patch}"
      versions[minor_key].append((build, url))

  # Get the latest (highest build number) for each minor version
  latest_per_minor = {}
  for minor_key, version_list in versions.items():
    version_list.sort(key=lambda x: x[0])
    latest_per_minor[minor_key] = version_list[-1][1]

  # Sort minor versions in descending order and take the first N
  def version_sort_key(v):
    parts = v.split('.')
    return (int(parts[0]), int(parts[1]), int(parts[2]))

  sorted_minors = sorted(latest_per_minor.keys(), key=version_sort_key, reverse=True)
  result = [latest_per_minor[minor] for minor in sorted_minors[:count]]

  return result


def download_appimage(url, dest_dir):
  """
  Download an RPCS3 AppImage.

  Args:
    url: Download URL
    dest_dir: Destination directory

  Returns:
    Path to downloaded AppImage or None if failed
  """
  filename = Path(url).name
  filepath = dest_dir / filename

  print(f"Downloading: {url}")
  print(f"Destination: {filepath}")

  if filepath.exists():
    print(f"File already exists: {filepath}")
    return filepath

  result = subprocess.run(
    ["wget", "--progress=dot:mega", "-O", str(filepath), url],
    capture_output=False
  )

  if result.returncode != 0:
    print(f"Error downloading {url}", file=sys.stderr)
    return None

  # Make executable
  filepath.chmod(0o755)

  return filepath


def extract_appimage(appimage_path, build_dir):
  """
  Extract RPCS3 AppImage.

  Args:
    appimage_path: Path to the AppImage
    build_dir: Build directory

  Returns:
    Path to extracted rpcs3 directory or None if failed
  """
  print(f"Extracting: {appimage_path}")

  # Extract AppImage
  result = subprocess.run(
    [str(appimage_path), "--appimage-extract"],
    cwd=build_dir,
    capture_output=True
  )

  if result.returncode != 0:
    print(f"Error extracting {appimage_path}: {result.stderr.decode()}", file=sys.stderr)
    return None

  # Remove AppImage
  appimage_path.unlink()

  # Move rpcs3 directory
  squashfs_root = build_dir / "squashfs-root"
  usr_dir = squashfs_root / "usr"
  rpcs3_dir = build_dir / "rpcs3"

  if usr_dir.exists():
    shutil.move(str(usr_dir), str(rpcs3_dir))
  else:
    print(f"Error: usr directory not found in {squashfs_root}", file=sys.stderr)
    return None

  # Remove squashfs-root (handle both directory and symlink)
  if squashfs_root.is_symlink():
    squashfs_root.unlink()
  elif squashfs_root.is_dir():
    shutil.rmtree(squashfs_root)

  return rpcs3_dir


def get_version_from_appimage(appimage_name):
  """
  Extract version string from AppImage filename.

  Args:
    appimage_name: Filename of the AppImage

  Returns:
    Version string
  """
  # Try to extract version pattern (e.g., v0.0.38-16857)
  match = re.search(r'v?(\d+\.\d+\.\d+)-(\d+)', appimage_name)
  if match:
    return f"{match.group(1)}-{match.group(2)}"

  # Fallback to using the full stem
  return Path(appimage_name).stem


def build_layer(image_path, rpcs3_dir, version, channel):
  """
  Build an RPCS3 layer.

  Args:
    image_path: Path to the flatimage
    rpcs3_dir: Path to the rpcs3 directory
    version: Version string
    channel: "stable" or "unstable"

  Returns:
    Path to created layer file or None if failed
  """
  print(f"Building layer for version: {version} ({channel})")

  # Copy boot script
  boot_script = SCRIPT_DIR / "boot.sh"
  boot_dest = rpcs3_dir / "boot"
  shutil.copy(boot_script, boot_dest)

  # Create layer directories
  # Structure: /opt/gameimage/runners/rpcs3/RPCS3/rpcs3-binaries-linux/main/{channel}/{version}/
  root_dir = Path("root")
  layer_version_dir = root_dir / "opt" / "gameimage" / "runners" / "rpcs3" / "RPCS3" / "rpcs3-binaries-linux" / "main" / channel / version
  config_dir = root_dir / "home" / "rpcs3" / ".config"

  layer_version_dir.parent.mkdir(parents=True, exist_ok=True)
  config_dir.mkdir(parents=True, exist_ok=True)

  # Move rpcs3_dir (which contains boot) to version directory
  shutil.move(str(rpcs3_dir), str(layer_version_dir))

  # Create layer with distribution=main and channel
  layer_name = f"rpcs3--RPCS3--rpcs3-binaries-linux--main--{channel}--{version}.layer"
  print(f"Creating layer: {layer_name}")

  result = subprocess.run(
    [str(image_path), "fim-layer", "create", str(root_dir), layer_name],
    capture_output=True,
    env={**subprocess.os.environ, "FIM_DEBUG": "1"}
  )

  if result.returncode != 0:
    print(f"Error creating layer: {result.stderr.decode()}", file=sys.stderr)
    return None

  # Remove temporary directory
  shutil.rmtree(root_dir)

  return Path(layer_name)


def package_rpcs3(image_path, stable_count=5, unstable_count=5):
  """
  Package RPCS3 distributions.

  Args:
    image_path: Path to the flatimage
    stable_count: Number of stable minor versions to build (default: 5)
    unstable_count: Number of unstable minor versions to build (default: 5)
  """
  print("\n=== Fetching RPCS3 releases ===")

  # Fetch all URLs (separated by channel)
  stable_urls, unstable_urls = fetch_rpcs3_urls()

  if not stable_urls and not unstable_urls:
    print("No URLs found for RPCS3, exiting...")
    return

  build_dir = SCRIPT_DIR / "build"

  # Process stable releases
  if stable_urls:
    print(f"\n=== Processing STABLE releases ===")
    selected_stable = get_latest_per_minor_version(stable_urls, count=stable_count)
    print(f"Found {len(selected_stable)} stable versions to build")

    for url in selected_stable:
      print(f"\n=== Processing {Path(url).name} (STABLE) ===")

      # Download AppImage
      appimage_path = download_appimage(url, build_dir)
      if not appimage_path:
        continue

      # Extract AppImage
      rpcs3_dir = extract_appimage(appimage_path, build_dir)
      if not rpcs3_dir:
        continue

      # Get version from filename
      version = get_version_from_appimage(appimage_path.name)

      # Build layer
      layer_path = build_layer(image_path, rpcs3_dir, version, "stable")
      if not layer_path:
        print(f"Failed to build layer for {url}", file=sys.stderr)
        continue

  # Process unstable releases
  if unstable_urls:
    print(f"\n=== Processing UNSTABLE releases ===")
    selected_unstable = get_latest_per_minor_version(unstable_urls, count=unstable_count)
    print(f"Found {len(selected_unstable)} unstable versions to build")

    for url in selected_unstable:
      print(f"\n=== Processing {Path(url).name} (UNSTABLE) ===")

      # Download AppImage
      appimage_path = download_appimage(url, build_dir)
      if not appimage_path:
        continue

      # Extract AppImage
      rpcs3_dir = extract_appimage(appimage_path, build_dir)
      if not rpcs3_dir:
        continue

      # Get version from filename
      version = get_version_from_appimage(appimage_path.name)

      # Build layer
      layer_path = build_layer(image_path, rpcs3_dir, version, "unstable")
      if not layer_path:
        print(f"Failed to build layer for {url}", file=sys.stderr)
        continue


def main():
  if len(sys.argv) != 2:
    print("Usage: build-arch.py <image_path>")
    sys.exit(1)

  image_path = Path(sys.argv[1])

  if not image_path.is_file():
    print(f"Error: {image_path} is not a regular file")
    sys.exit(1)

  # Change to script directory
  subprocess.os.chdir(SCRIPT_DIR)

  # Create dist directory
  dist_dir = SCRIPT_DIR.parent / "dist"
  dist_dir.mkdir(exist_ok=True)

  # Re-create build directory
  build_dir = SCRIPT_DIR / "build"
  if build_dir.exists():
    shutil.rmtree(build_dir)
  build_dir.mkdir()
  subprocess.os.chdir(build_dir)

  # Build RPCS3 distributions (5 stable + 5 unstable)
  package_rpcs3(image_path, stable_count=5, unstable_count=5)

  # Create SHA256 checksums and move to dist
  print("\n=== Creating SHA256 checksums ===")
  for layer_file in build_dir.glob("**/*.layer"):
    # Create checksum
    checksum_file = dist_dir / f"{layer_file.name}.sha256sum"
    result = subprocess.run(
      ["sha256sum", str(layer_file)],
      capture_output=True,
      text=True
    )
    if result.returncode == 0:
      checksum_file.write_text(result.stdout)

    # Move layer to dist
    shutil.copy(layer_file, dist_dir)
    print(f"Copied {layer_file.name} to dist/")


if __name__ == "__main__":
  main()
