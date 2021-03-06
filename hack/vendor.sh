#!/bin/bash
# Copyright (C) 2013-2016 Docker, Inc.
# Copyright (C) 2016 SUSE LLC.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -e

export PROJECT="github.com/cyphar/umoci"

# Clean cleans the vendor directory of any directories which are not required
# by imports in the current project. It is adapted from hack/.vendor-helpers.sh
# in Docker (which is also Apache-2.0 licensed).
clean() {
	local packages=(
		"${PROJECT}/cmd/umoci" # main umoci package
	)

	# Important because different buildtags and platforms can have different
	# import sets. It's very important to make sure this is kept up to date.
	local platforms=( "linux/amd64" )
	local buildtagcombos=( "" )

	# Generate the import graph so we can delete things outside of it.
	echo -n "collecting import graph, "
	local IFS=$'\n'
	local imports=( $(
		for platform in "${platforms[@]}"; do
			export GOOS="${platform%/*}";
			export GOARCH="${platform##*/}";
			for tags in "${buildtagcombos[@]}"; do
				# Include dependencies (for packages and package tests).
				go list -e -tags "$tags" -f '{{join .Deps "\n"}}' "${packages[@]}"
				go list -e -tags "$tags" -f '{{join .TestImports "\n"}}' "${packages[@]}"
			done
		done | grep -vP "^${PROJECT}/(?!vendor)" | sort -u
	) )
	# Remove non-standard imports from the set of dependencies detected.
	imports=( $(go list -e -f '{{if not .Standard}}{{.ImportPath}}{{end}}' "${imports[@]}") )
	unset IFS

	# We use find to prune any directory that was not included above. So we
	# have to generate the (-path A -or -path B ...) commandline.
	echo -n "pruning unused packages, "
	local findargs=( )

	# Add vendored imports that are used to the list. Note that packages in
	# vendor/ act weirdly (they are prefixed by ${PROJECT}/vendor).
	for import in "${imports[@]}"; do
		[ "${#findargs[@]}" -eq 0 ] || findargs+=( -or )
		findargs+=( -path "vendor/$(echo "$import" | sed "s:^${PROJECT}/vendor/::")" )
	done

	# Find all of the vendored directories that are not in the set of used imports.
	local IFS=$'\n'
	local prune=( $(find vendor -depth -type d -not '(' "${findargs[@]}" ')') )
	unset IFS

	# Files we don't want to delete from *any* directory.
	local importantfiles=( -name 'LICENSE*' -or -name 'COPYING*' -or -name 'NOTICE*' )

	# Delete all top-level files which are not LICENSE or COPYING related, as
	# well as deleting the actual directory if it's empty.
	for dir in "${prune[@]}"; do
		find "$dir" -maxdepth 1 -not -type d -not '(' "${importantfiles[@]}" ')' -exec rm -v -f '{}' ';'
		rmdir "$dir" 2>/dev/null || true
	done

	# Remove non-top-level vendors.
	echo -n "remove library vendors,"
	find vendor/* -type d '(' -name 'vendor' -or -name 'Godeps' ')' -print0 | xargs -r0 -- rm -rfv

	# Remove any extra files that we know we don't care about.
	echo -n "pruning unused files, "
	find vendor -type f -name '*_test.go' -exec rm -v '{}' ';'
	find vendor -regextype posix-extended -type f -not '(' -regex '.*\.(c|h|go)' -or '(' "${importantfiles[@]}" ')' ')' -exec rm -v '{}' ';'

	# Remove self from vendor.
	echo -n "pruning self from vendor, "
	rm -rf vendor/${PROJECT}

	echo "done"
}

clone() {
	local importPath="$1"
	local commit="$2"
	local cloneURL="${3:-https://$1.git}"
	local vendorPath="vendor/$importPath"

	if [ -z "$3" ]; then
		echo "clone $importPath @ $commit"
	else
		echo "clone $cloneURL -> $importPath @ $commit"
	fi

	set -e
	(
		rm -rf "$vendorPath" && mkdir -p "$vendorPath"
		git clone "$cloneURL" "$vendorPath" &>/dev/null
		cd "$vendorPath"
		git checkout --detach "$commit" &>/dev/null
	)
}

# Update everything.
# TODO: Put this in a vendor.conf file or something like that (to be compatible
#       with LK4D4/vndr). This setup is a bit unwieldy.
clone github.com/opencontainers/image-spec 409e1a51e86f8cb749576453be8e37742c4ba721 # v1.0.0-rc3+37
clone github.com/opencontainers/runtime-spec v1.0.0-rc2
clone github.com/opencontainers/image-tools 421458f7e467ac86175408693a07da6d29817bf7
clone github.com/opencontainers/runtime-tools b61b44a71dafb8472bbc1e5eb0d68ed9ce8ba6ac
clone github.com/syndtr/gocapability 2c00daeb6c3b45114c80ac44119e7b8801fdd852
clone golang.org/x/crypto  01be46f62051d02cb6a36c9b47b37b24e5758c81 https://github.com/golang/crypto
clone golang.org/x/sys d75a52659825e75fff6158388dddc6a5b04f9ba5 https://github.com/golang/sys
clone github.com/docker/go-units v0.3.1
clone github.com/pkg/errors v0.8.0
clone github.com/Sirupsen/logrus v0.11.0
clone github.com/urfave/cli v1.18.1
clone github.com/vbatts/go-mtree 0dc720e861ecc198ef262fe1ec2d33b293512aaf
clone golang.org/x/net 45e771701b814666a7eb299e6c7a57d0b1799e91 https://github.com/golang/net

# Clean up the vendor directory.
clean
