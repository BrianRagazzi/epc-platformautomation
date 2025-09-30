#!/usr/bin/env bash

set -e

echo "Logging into Harbor..."
if ! docker login -u admin -p VMware123! harbor.tnz-field-epc.lvn.broadcom.net; then
  echo "ERROR: Docker login failed."
  exit 1
fi

echo "Downloading images..."
for url in \
  "https://fileshare.tnz-field-epc.lvn.broadcom.net/tools/platform-automation/vsphere-platform-automation-image-5.3.1.tar.gz" \
  "https://fileshare.tnz-field-epc.lvn.broadcom.net/tools/platform-automation/platauto-uaac-5.3.1.tar.gz" \
  "https://fileshare.tnz-field-epc.lvn.broadcom.net/tools/platform-automation/http-resource-1.0.0.tar.gz"
do
  filename=$(basename "$url")
  if wget "$url"; then
    echo "Downloaded $filename"
  else
    echo "ERROR: Failed to download $filename"
    exit 1
  fi
done

echo "Importing images into Docker..."
if ! docker import vsphere-platform-automation-image-5.3.1.tar.gz platform-automation:5.3.1; then
  echo "ERROR: Failed to import platform-automation image."
  exit 1
fi
if ! docker import platauto-uaac-5.3.1.tar.gz platauto-uaac:5.3.1; then
  echo "ERROR: Failed to import platauto-uaac image."
  exit 1
fi
if ! docker import http-resource-1.0.0.tar.gz jgriff/http-resource:latest; then
  echo "ERROR: Failed to import http-resource image."
  exit 1
fi

echo "Tagging images..."
docker tag platform-automation:5.3.1 harbor.tnz-field-epc.lvn.broadcom.net/library/platform-automation:5.3.1
docker tag platauto-uaac:5.3.1 harbor.tnz-field-epc.lvn.broadcom.net/library/platauto-uaac:5.3.1
docker tag jgriff/http-resource:latest harbor.tnz-field-epc.lvn.broadcom.net/library/jgriff/http-resource:latest

docker tag harbor.tnz-field-epc.lvn.broadcom.net/library/platform-automation:5.3.1 harbor.tnz-field-epc.lvn.broadcom.net/library/platform-automation:latest
docker tag harbor.tnz-field-epc.lvn.broadcom.net/library/platauto-uaac:5.3.1 harbor.tnz-field-epc.lvn.broadcom.net/library/platauto-uaac:latest

echo "Pushing images to Harbor..."
for image in \
  "harbor.tnz-field-epc.lvn.broadcom.net/library/platform-automation:5.3.1" \
  "harbor.tnz-field-epc.lvn.broadcom.net/library/platform-automation:latest" \
  "harbor.tnz-field-epc.lvn.broadcom.net/library/platauto-uaac:5.3.1" \
  "harbor.tnz-field-epc.lvn.broadcom.net/library/platauto-uaac:latest" \
  "harbor.tnz-field-epc.lvn.broadcom.net/library/jgriff/http-resource:latest"
do
  if docker push "$image"; then
    echo "Pushed $image"
  else
    echo "ERROR: Failed to push $image"
    exit 1
  fi
done

echo "Cleaning up downloaded tar.gz files..."
rm -f vsphere-platform-automation-image-5.3.1.tar.gz platauto-uaac-5.3.1.tar.gz http-resource-1.0.0.tar.gz

echo "All images processed and local files cleaned up successfully."
