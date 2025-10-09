#!/bin/bash

# Check if concourse-web service is running
if ! systemctl is-active --quiet concourse-web; then
  echo "ERROR: concourse-web service is not running. Concourse is not running."
  exit 1
fi

# Log in to Concourse with fly CLI
echo "Logging in to Concourse..."
fly -t ci login -c http://concourse.elasticsky.cloud:8080 -u admin -p VMware123!

# Remove all pipelines from Concourse using fly CLI
echo "Listing pipelines..."
pipelines=$(fly -t ci pipelines --json | jq -r '.[].name')

for pipeline in $pipelines; do
  echo "Destroying pipeline: $pipeline"
  fly -t ci destroy-pipeline -p "$pipeline" -n
done

echo "Listing worker volumes..."
live_volumes_dir="/opt/concourse/worker/volumes/live"
dead_volumes_dir="/opt/concourse/worker/volumes/dead"

# Find and unmount busy volumes, then remove all volumes
echo "Cleaning up live worker volumes..."
for vol in $(sudo find "$live_volumes_dir" -mindepth 1 -maxdepth 1 -type d); do
  if mountpoint -q "$vol/volume"; then
    echo "Unmounting busy volume: $vol/volume"
    sudo umount "$vol/volume"
  fi
  echo "Removing volume directory: $vol"
  sudo rm -rf "$vol"
done

echo "Cleaning up dead worker volumes..."
for vol in $(sudo find "$dead_volumes_dir" -mindepth 1 -maxdepth 1 -type d); do
  if mountpoint -q "$vol/volume"; then
    echo "Unmounting busy volume: $vol/volume"
    sudo umount "$vol/volume"
  fi
  echo "Removing volume directory: $vol"
  sudo rm -rf "$vol"
done

echo "Cleanup complete."