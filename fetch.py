#!/usr/bin/env python3

######################################################################
# @author      : Ruan E. Formigoni (ruanformigoni@gmail.com)
# @file        : fetch
# @description : Generate fetch JSON from dist directory
######################################################################

import json
import sys
import re
from pathlib import Path
from collections import defaultdict
from urllib.request import urlopen
from urllib.error import URLError

def fetch_retroarch_cores():
  """Fetch the list of RetroArch cores from buildbot."""
  url = "http://buildbot.libretro.com/nightly/linux/x86_64/latest/"

  try:
    with urlopen(url) as response:
      html = response.read().decode('utf-8')

    # Extract .so.zip files using regex
    # Pattern matches: href=".*?latest/(.*?\.so.zip)"
    pattern = r'href=".*?latest/(.*?\.so\.zip)"'
    matches = re.findall(pattern, html, re.IGNORECASE)

    # Remove duplicates and sort
    core_files = sorted(set(matches))

    return {
      "url": url,
      "files": core_files
    }
  except URLError as e:
    print(f"Warning: Failed to fetch RetroArch cores from {url}: {e}", file=sys.stderr)
    return None

def main():
  if len(sys.argv) != 2:
    print("Usage: fetch.sh <version>")
    print("Example: fetch.sh gameimage-2.0.x")
    sys.exit(1)

  version = sys.argv[1]
  script_dir = Path(__file__).parent
  dist_dir = script_dir / "dist"

  if not dist_dir.exists():
    print(f"Error: dist directory not found at {dist_dir}")
    sys.exit(1)

  result = {}

  # Parse layer files from dist directory
  # Structure: platforms[platform][owner][repo][dist_or_stability] = [versions]
  platforms = defaultdict(lambda: defaultdict(lambda: defaultdict(lambda: defaultdict(list))))

  for layer_file in dist_dir.glob("*.layer"):
    filename = layer_file.stem
    parts = filename.split("--")

    if len(parts) != 5:
      print(f"Warning: Unexpected layer format: {filename}", file=sys.stderr)
      continue

    platform, owner, repo, dist_or_stability, version_str = parts
    platforms[platform][owner][repo][dist_or_stability].append(version_str)

  # Build JSON structure
  result["version"] = version.replace("gameimage-", "").replace(".x", "")

  # Create containers entry
  result["containers"] = {
    "arch": "arch.flatimage"
  }

  # Add each platform with nested structure
  for platform in ["linux", "pcsx2", "rpcs3", "wine", "retroarch"]:
    if platform in platforms:
      # Convert nested defaultdicts to regular dicts
      layer_data = {}
      for owner, repos in platforms[platform].items():
        layer_data[owner] = {}
        for repo, dists in repos.items():
          layer_data[owner][repo] = dict(dists)

      result[platform] = {
        "layer": layer_data
      }

  # Fetch retroarch cores from buildbot
  if "retroarch" in result:
    cores = fetch_retroarch_cores()
    if cores:
      result["retroarch"]["core"] = cores

  # Print JSON with proper formatting
  print(json.dumps(result, indent=2))

if __name__ == "__main__":
  main()
