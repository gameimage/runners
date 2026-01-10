#!/usr/bin/env python3

######################################################################
# @author      : Ruan E. Formigoni (ruanformigoni@gmail.com)
# @file        : build-arch
# @description : Build wine distribution layers
######################################################################

import json
import subprocess
import sys
import shutil
import re
from pathlib import Path
from collections import defaultdict

SCRIPT_DIR = Path(__file__).parent


def get_latest_per_major_version(urls, count=10):
  """
  Get the latest version from each of the last N major versions.

  Args:
    urls: List of download URLs
    count: Number of major versions to keep (default: 10)

  Returns:
    List of URLs for the latest version of each major version
  """
  # Group URLs by major version
  versions = defaultdict(list)

  for url in urls:
    filename = Path(url).name
    # Try to extract version pattern (e.g., wine-9.0, soda-9.0)
    match = re.search(r'[_-](\d+)\.(\d+)', filename)
    if match:
      major = int(match.group(1))
      minor = int(match.group(2))
      versions[major].append((minor, url))

  # Get the latest (highest minor version) for each major version
  latest_per_major = {}
  for major, version_list in versions.items():
    # Sort by minor version and take the last (highest)
    version_list.sort(key=lambda x: x[0])
    latest_per_major[major] = version_list[-1][1]

  # Sort major versions in descending order and take the last N
  sorted_majors = sorted(latest_per_major.keys(), reverse=True)
  result = [latest_per_major[major] for major in sorted_majors[:count]]

  return result


def fetch_wine_urls(dist_name):
  """
  Fetch download URLs for a wine distribution.

  Args:
    dist_name: Name of the wine distribution (caffe, vaniglia, soda, staging, tkg)

  Returns:
    List of download URLs
  """
  if dist_name in ["caffe", "vaniglia", "soda"]:
    # Fetch from bottlesdevs/wine
    result = subprocess.run(
      ["gh", "api", "--paginate", "repos/bottlesdevs/wine/releases"],
      capture_output=True,
      text=True
    )

    if result.returncode != 0:
      print(f"Error fetching {dist_name} releases: {result.stderr}", file=sys.stderr)
      return []

    try:
      releases = json.loads(result.stdout)
      urls = []
      for release in releases:
        for asset in release.get("assets", []):
          url = asset.get("browser_download_url", "")
          # Filter out experimental and cx/vaniglia variants
          if "experimental" not in url and "cx/vaniglia" not in url and dist_name in url:
            urls.append(url)
      return urls
    except json.JSONDecodeError as e:
      print(f"Error parsing JSON for {dist_name}: {e}", file=sys.stderr)
      return []

  elif dist_name in ["staging", "tkg"]:
    # Fetch from Kron4ek/Wine-Builds
    result = subprocess.run(
      ["gh", "api", "--paginate", "repos/Kron4ek/Wine-Builds/releases"],
      capture_output=True,
      text=True
    )

    if result.returncode != 0:
      print(f"Error fetching {dist_name} releases: {result.stderr}", file=sys.stderr)
      return []

    try:
      releases = json.loads(result.stdout)
      urls = []
      pattern = f".*{dist_name}-amd64.tar.*"
      for release in releases:
        for asset in release.get("assets", []):
          url = asset.get("browser_download_url", "")
          if re.search(pattern, url):
            urls.append(url)
      return urls
    except json.JSONDecodeError as e:
      print(f"Error parsing JSON for {dist_name}: {e}", file=sys.stderr)
      return []

  return []


def download(url, dest_dir):
  """
  Download and extract a wine tarball.

  Args:
    url: Download URL
    dest_dir: Destination directory for extraction

  Returns:
    Path to the downloaded tarball or None if failed
  """
  filename = Path(url).name

  print(f"link_wine: {url}")
  print(f"file_name: {filename}")

  # Download if not already present
  if not Path(filename).exists():
    result = subprocess.run(
      ["wget", "--progress=dot:mega", url],
      capture_output=False
    )
    if result.returncode != 0:
      print(f"Error downloading {url}", file=sys.stderr)
      return None

  return Path(filename)


def build_layer(image_path, dist_name, tarball_path, owner, repo):
  """
  Build a wine layer from an extracted tarball.

  Args:
    image_path: Path to the flatimage
    dist_name: Wine distribution name
    tarball_path: Path to the wine tarball
    owner: Repository owner
    repo: Repository name

  Returns:
    True if successful, False otherwise
  """
  # First, extract wine to get the version
  root_dir = Path("root")
  temp_wine_dir = root_dir / "temp_wine"
  temp_wine_dir.mkdir(parents=True, exist_ok=True)

  # Extract wine
  print(f"Extracting {tarball_path}...")
  result = subprocess.run(
    ["tar", "-xf", str(tarball_path), "-C", str(temp_wine_dir), "--strip-components=1"],
    capture_output=True
  )

  if result.returncode != 0:
    print(f"Error extracting {tarball_path}: {result.stderr.decode()}", file=sys.stderr)
    return False

  # Remove tarball
  tarball_path.unlink()

  # Get wine version
  wine_bin = temp_wine_dir / "bin" / "wine"
  result = subprocess.run(
    [str(wine_bin.resolve()), "--version"],
    capture_output=True,
    text=True
  )

  if result.returncode != 0:
    print(f"Error getting wine version: {result.stderr}", file=sys.stderr)
    return False

  version_wine = result.stdout.strip().split()[0]
  print(f"wine version: {version_wine}")

  # Copy wine boot script before moving
  wine_script = SCRIPT_DIR / "wine.sh"
  shutil.copy(wine_script, temp_wine_dir / "bin" / "wine.sh")

  # Create layer directories with version
  # Structure: /opt/gameimage/runners/wine/{owner}/{repo}/{dist_name}/stable/{version}/
  layer_version_dir = root_dir / "opt" / "gameimage" / "runners" / "wine" / owner / repo / dist_name / "stable" / version_wine
  layer_version_dir.parent.mkdir(parents=True, exist_ok=True)

  # Move temp_wine_dir (which contains bin/wine) to version directory
  shutil.move(str(temp_wine_dir), str(layer_version_dir))

  # Create layer with platform--owner--repo--dist--channel--version format
  # All wine releases are considered stable (they don't use GitHub prerelease/draft)
  layer_name = f"wine--{owner}--{repo}--{dist_name}--stable--{version_wine}.layer"
  print(f"Creating layer: {layer_name}")

  result = subprocess.run(
    [str(image_path), "fim-layer", "create", str(root_dir), layer_name],
    capture_output=True,
    env={**subprocess.os.environ, "FIM_DEBUG": "1"}
  )

  if result.returncode != 0:
    print(f"Error creating layer: {result.stderr.decode()}", file=sys.stderr)
    return False

  # Remove temporary directory
  shutil.rmtree(root_dir)

  return True


def package_wine_dists(image_path):
  """
  Package all wine distributions.

  Args:
    image_path: Path to the flatimage
  """
  wine_dists = ["caffe", "vaniglia", "soda", "staging", "tkg"]

  for dist_name in wine_dists:
    print(f"\n=== Processing {dist_name} ===")

    # Determine repository based on distribution
    if dist_name in ["caffe", "vaniglia", "soda"]:
      owner = "bottlesdevs"
      repo = "wine"
    elif dist_name in ["staging", "tkg"]:
      owner = "Kron4ek"
      repo = "Wine-Builds"
    else:
      print(f"Unknown distribution: {dist_name}", file=sys.stderr)
      continue

    # Fetch all URLs
    all_urls = fetch_wine_urls(dist_name)
    if not all_urls:
      print(f"No URLs found for {dist_name}, skipping...")
      continue

    # Get latest from each of the last 6 major versions
    selected_urls = get_latest_per_major_version(all_urls, count=6)

    print(f"Found {len(selected_urls)} versions to build for {dist_name}")

    # Process each version
    for url in selected_urls:
      tarball_path = download(url, Path.cwd())
      if not tarball_path:
        continue

      if not build_layer(image_path, dist_name, tarball_path, owner, repo):
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

  # Create build and dist directories
  dist_dir = SCRIPT_DIR.parent / "dist"
  dist_dir.mkdir(exist_ok=True)

  build_dir = SCRIPT_DIR / "build"
  build_dir.mkdir(exist_ok=True)
  subprocess.os.chdir(build_dir)

  # Build wine distributions
  package_wine_dists(image_path)

  # Create SHA256 checksums
  print("\n=== Creating SHA256 checksums ===")
  for layer_file in Path.cwd().glob("*.layer"):
    checksum_file = dist_dir / f"{layer_file.name}.sha256sum"
    result = subprocess.run(
      ["sha256sum", str(layer_file)],
      capture_output=True,
      text=True
    )
    if result.returncode == 0:
      checksum_file.write_text(result.stdout)

  # Move layers to dist
  print("\n=== Moving layers to dist ===")
  for layer_file in Path.cwd().glob("*.layer"):
    shutil.copy(layer_file, dist_dir)
    print(f"Copied {layer_file.name} to dist/")


if __name__ == "__main__":
  main()
