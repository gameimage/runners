#!/usr/bin/env python3

######################################################################
# @author      : Ruan E. Formigoni (ruanformigoni@gmail.com)
# @file        : build-arch
# @description : Build retroarch distribution layers
######################################################################

import subprocess
import sys
import shutil
import re
from pathlib import Path
from collections import defaultdict

SCRIPT_DIR = Path(__file__).parent


def fetch_retroarch_versions():
  """
  Fetch available RetroArch stable versions from buildbot.

  Returns:
    List of version strings (e.g., ["1.19.1", "1.18.0", ...])
  """
  print("Fetching RetroArch stable versions...")

  # Fetch and parse versions using grep
  result = subprocess.run(
    "wget -qO - https://buildbot.libretro.com/stable/ | grep -Eio '[0-9]+\\.[0-9]+\\.[0-9]+' | sort -u",
    shell=True,
    capture_output=True,
    text=True
  )

  if result.returncode != 0:
    print(f"Error fetching RetroArch versions", file=sys.stderr)
    return []

  # Split output into version list
  versions = [v.strip() for v in result.stdout.strip().split('\n') if v.strip()]

  return versions


def get_latest_per_minor_version(versions, count=10):
  """
  Get the latest version from each minor version series.
  For example: 1.19.max, 1.18.max, 1.17.max, etc.

  Args:
    versions: List of version strings
    count: Number of minor versions to keep (default: 10)

  Returns:
    List of version strings for the latest patch version of each minor version
  """
  # Group versions by major.minor
  version_groups = defaultdict(list)

  for version in versions:
    match = re.match(r'(\d+)\.(\d+)\.(\d+)', version)
    if match:
      major = int(match.group(1))
      minor = int(match.group(2))
      patch = int(match.group(3))
      minor_key = f"{major}.{minor}"
      version_groups[minor_key].append((patch, version))

  # Get the latest (highest patch version) for each minor version
  latest_per_minor = {}
  for minor_key, version_list in version_groups.items():
    version_list.sort(key=lambda x: x[0])
    latest_per_minor[minor_key] = version_list[-1][1]

  # Sort minor versions in descending order and take the first N
  def version_sort_key(v):
    parts = v.split('.')
    return (int(parts[0]), int(parts[1]))

  sorted_minors = sorted(latest_per_minor.keys(), key=version_sort_key, reverse=True)
  result = [latest_per_minor[minor] for minor in sorted_minors[:count]]

  return result


def download_and_extract_retroarch(version, build_dir):
  """
  Download and extract a specific RetroArch version.

  Args:
    version: Version string (e.g., "1.19.1")
    build_dir: Build directory

  Returns:
    Path to extracted retroarch directory or None if failed
  """
  print(f"\n=== Processing RetroArch {version} ===")

  url_retroarch = f"https://buildbot.libretro.com/stable/{version}/linux/x86_64/RetroArch.7z"

  # Create version-specific directory
  version_dir = build_dir / f"retroarch-{version}"
  version_dir.mkdir(exist_ok=True)

  archive_path = version_dir / "RetroArch.7z"

  # Download
  print(f"Downloading: {url_retroarch}")
  result = subprocess.run(
    ["wget", "--progress=dot:mega", "-O", str(archive_path), url_retroarch],
    capture_output=False
  )

  if result.returncode != 0:
    print(f"Error downloading RetroArch {version}", file=sys.stderr)
    return None

  # Extract 7z
  print(f"Extracting RetroArch.7z...")
  result = subprocess.run(
    ["7z", "x", str(archive_path)],
    cwd=version_dir,
    capture_output=True
  )

  if result.returncode != 0:
    print(f"Error extracting archive: {result.stderr.decode()}", file=sys.stderr)
    return None

  # Remove 7z file
  archive_path.unlink()

  # Create retroarch directory
  retroarch_dir = version_dir / "retroarch"
  retroarch_dir.mkdir(exist_ok=True)

  # Move AppImage
  extracted_dir = version_dir / "RetroArch-Linux-x86_64"
  appimage_path = extracted_dir / "RetroArch-Linux-x86_64.AppImage"
  appimage_dest = version_dir / "RetroArch-Linux-x86_64.AppImage"

  if not appimage_path.exists():
    print(f"Error: AppImage not found at {appimage_path}", file=sys.stderr)
    return None

  shutil.move(str(appimage_path), str(appimage_dest))

  # Move assets to retroarch config
  config_src = extracted_dir / "RetroArch-Linux-x86_64.AppImage.home" / ".config"
  config_dest = retroarch_dir / "config"

  if config_src.exists():
    shutil.move(str(config_src), str(config_dest))

  # Remove extracted folder
  shutil.rmtree(extracted_dir)

  # Make executable
  appimage_dest.chmod(0o755)

  # Extract AppImage
  print(f"Extracting AppImage...")
  result = subprocess.run(
    [str(appimage_dest), "--appimage-extract"],
    cwd=version_dir,
    capture_output=True
  )

  if result.returncode != 0:
    print(f"Error extracting AppImage: {result.stderr.decode()}", file=sys.stderr)
    return None

  # Remove AppImage
  appimage_dest.unlink()

  # Move extracted directory
  squashfs_root = version_dir / "squashfs-root"
  usr_dir = squashfs_root / "usr"
  data_dest = retroarch_dir / "data"

  if usr_dir.exists():
    shutil.move(str(usr_dir), str(data_dest))
  else:
    print(f"Error: usr directory not found in {squashfs_root}", file=sys.stderr)
    return None

  # Remove squashfs-root
  shutil.rmtree(squashfs_root)

  return retroarch_dir


def build_layer(image_path, retroarch_dir, version):
  """
  Build a RetroArch layer.

  Args:
    image_path: Path to the flatimage
    retroarch_dir: Path to the retroarch directory
    version: Version string

  Returns:
    Path to created layer file or None if failed
  """
  print(f"Building layer for version: {version}")

  # Copy boot script
  boot_script = SCRIPT_DIR / "boot.sh"
  boot_dest = retroarch_dir / "boot"
  shutil.copy(boot_script, boot_dest)

  # Create layer directories
  root_dir = Path("root")
  opt_dir = root_dir / "opt"
  home_dir = root_dir / "home" / "gameimage"

  opt_dir.mkdir(parents=True, exist_ok=True)
  home_dir.mkdir(parents=True, exist_ok=True)

  # Move retroarch config to gameimage home
  config_src = retroarch_dir / "config"
  config_dest = home_dir / ".config"

  if config_src.exists():
    shutil.move(str(config_src), str(config_dest))

  # Move retroarch to layer directory
  layer_retroarch_dir = opt_dir / "retroarch"
  shutil.move(str(retroarch_dir), str(layer_retroarch_dir))

  # Create layer with distribution=main and channel=stable
  layer_name = f"retroarch--libretro--stable--main--stable--{version}.layer"
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


def package_retroarch(image_path, count=10):
  """
  Package RetroArch distributions.

  Args:
    image_path: Path to the flatimage
    count: Number of minor versions to build (default: 10)
  """
  print("\n=== Fetching RetroArch versions ===")

  # Fetch all available versions
  all_versions = fetch_retroarch_versions()
  if not all_versions:
    print("No versions found for RetroArch, exiting...")
    return

  # Get latest from each minor version (1.19.max, 1.18.max, 1.17.max, etc.)
  selected_versions = get_latest_per_minor_version(all_versions, count=count)
  print(f"Found {len(selected_versions)} versions to build")
  print(f"Selected versions: {', '.join(selected_versions)}")

  build_dir = SCRIPT_DIR / "build"

  # Process each version
  for version in selected_versions:
    # Download and extract
    retroarch_dir = download_and_extract_retroarch(version, build_dir)
    if not retroarch_dir:
      continue

    # Build layer
    layer_path = build_layer(image_path, retroarch_dir, version)
    if not layer_path:
      print(f"Failed to build layer for {version}", file=sys.stderr)
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

  # Build RetroArch distributions
  package_retroarch(image_path, count=10)

  # Create SHA256 checksums and move to dist
  print("\n=== Creating SHA256 checksums ===")
  for layer_file in Path.cwd().glob("**/*.layer"):
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
