#!/usr/bin/env python3

######################################################################
# @author      : Ruan E. Formigoni (ruanformigoni@gmail.com)
# @file        : fetch
# @description : Generate fetch JSON from dist directory
######################################################################

import json
import sys
from pathlib import Path
from collections import defaultdict

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

  # Parse layer files from dist directory
  # Structure: platforms[platform][repo][dist_or_stability] = [versions]
  platforms = defaultdict(lambda: defaultdict(lambda: defaultdict(list)))

  for layer_file in dist_dir.glob("*.layer"):
    filename = layer_file.stem
    parts = filename.split("--")

    if len(parts) != 5:
      print(f"Warning: Unexpected layer format: {filename}", file=sys.stderr)
      continue

    platform, owner, repo, dist_or_stability, version_str = parts
    repo_key = f"{owner}--{repo}"
    platforms[platform][repo_key][dist_or_stability].append(version_str)

  # Build JSON structure
  result = {
    "version": version.replace("gameimage-", "").replace(".x", "")
  }

  # Add each platform with nested structure
  for platform in ["linux", "pcsx2", "rpcs3", "wine", "retroarch"]:
    if platform in platforms:
      # Convert nested defaultdicts to regular dicts
      layer_data = {}
      for repo, dists in platforms[platform].items():
        layer_data[repo] = dict(dists)

      result[platform] = {
        "layer": layer_data
      }

  # Add retroarch cores from existing file if available
  if "retroarch" in result:
    fetch_file = script_dir / "fetch" / "gameimage-1.6.x.json"
    if fetch_file.exists():
      with open(fetch_file) as f:
        old_data = json.load(f)
        if "retroarch" in old_data and "core" in old_data["retroarch"]:
          result["retroarch"]["core"] = old_data["retroarch"]["core"]

  # Print JSON with proper formatting
  print(json.dumps(result, indent=2))

if __name__ == "__main__":
  main()
