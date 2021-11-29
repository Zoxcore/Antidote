#!/bin/bash -e

#
# package-ipa.sh
#
# Bundles an iOS app correctly, using the same directory structure that Xcode does when using the export functionality.
#

xcarchive="$1"
output_ipa="$2"
build_dir=$(mktemp -d '/tmp/package-ipa.XXXXXX')
echo "build_dir: $build_dir"

if [ ! -d "${xcarchive}" ]; then
	echo "Usage: package-ipa.sh /path/to/app.xcarchive /path/to/ouput.ipa"
	exit 1
fi

echo "Packaging ${xcarchive} into ${output_ipa}"

if [ -f "${output_ipa}" ]; then
	rm "${output_ipa}"
fi

# if [ -d "${build_dir}" ]; then
# 	rm -rf "${build_dir}"
# fi

echo "Preparing folder tree for IPA"
mkdir -p "${build_dir}/Payload"

# Copy .app into Payload dir
pushd "${xcarchive}/Products/Applications" > /dev/null
ls -l
cp -Rp ./*.app "${build_dir}/Payload"
popd > /dev/null

# Check for and copy swift libraries
#if [ -d "${xcarchive}/SwiftSupport" ]; then
#	echo "Adding Swift support dylibs"
#	cp -Rp "${xcarchive}/SwiftSupport" "${build_dir}/"
#fi

# Check for and copy WatchKit file
#if [ -d "${xcarchive}/WatchKitSupport" ]; then
#	echo "Adding WatchKit support file"
#	cp -Rp "${xcarchive}/WatchKitSupport" "${build_dir}/"
#fi

echo "Zipping"
pushd "${build_dir}" > /dev/null
zip --symlinks --verbose --recurse-paths "${output_ipa}" .
popd > /dev/null

rm -rf "${build_dir}"
echo "Created ${output_ipa}"
