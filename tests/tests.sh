#!/bin/bash

base="$(dirname "$(readlink -f -- $0)")/.."
cd $base

#Usage: fail <file> <message> [ignore string]
fail() {
	if [ -z "$3" ] || ! grep -qF "$3" "$1";then
		echo "F: $1: $2"
		touch fail
	else
		echo "W: $1: $2"
	fi
}

#Keep knownKeys
rm -f tests/priorities fail
touch tests/priorities tests/knownKeys
find -name AndroidManifest.xml |while read manifest;do
	folder="$(dirname "$manifest")"
	#Ensure this overlay doesn't override blacklist-ed properties
	for b in $(cat tests/blacklist);do
		if grep -qRF "$b" $folder;then
			fail $folder "Overlay $folder is defining $b which is forbidden"
		fi
	done

	#Everything after that is specifically for static overlays, targetting framework-res
	isStatic="$(xmlstarlet sel -t -m '//overlay' -v @android:isStatic -n $manifest)"
	[ "$isStatic" != "true" ] && continue

	#Ensure priorities unique-ness
	priority="$(xmlstarlet sel -t -m '//overlay' -v @android:priority -n $manifest)"
	if grep -qE '^'$priority'$' tests/priorities;then
		fail $manifest "priority $priority conflicts with another manifest"
	fi
	echo $priority >> tests/priorities

	systemPropertyName="$(xmlstarlet sel -t -m '//overlay' -v @android:requiredSystemPropertyName -n $manifest)"
	if [ "$systemPropertyName" == "ro.vendor.product.name" -o "$systemPropertyName" == "ro.vendor.product.device" ];then
		fail "$manifest" "ro.vendor.product.* is deprecated. Please use ro.vendor.build.fingerprint" \
			'TESTS: Ignore ro.vendor.product.'
	fi

	#Ensure the overloaded properties exist in AOSP
	find "$folder" -name \*.xml |while read xml;do
		keys="$(xmlstarlet sel -t -m '//resources/*' -v @name -n $xml)"
		for key in $keys;do
			grep -qE '^'$key'$' tests/knownKeys && continue
			#Run the ag only on phh's machine. Assume that knownKeys is full enough.
			#If it's enough, ask phh to update it
			if [ -d /build/AOSP-9.0 ] && \
				(ag '"'$key'"' /build/AOSP-9.0/frameworks/base/core/res/res || \
				ag '"'$key'"' /build/AOSP-8.1/frameworks/base/core/res/res)> /dev/null ;then
				echo $key >> tests/knownKeys
			else
				fail "$xml" "defines a non-existing attribute $key"
			fi
		done
	done
done
rm -f tests/priorities

find -name \*.xml |xargs dos2unix -ic |while read f;do
	fail $f "File is DOS type"
done

if [ -f fail ];then exit 1; fi
