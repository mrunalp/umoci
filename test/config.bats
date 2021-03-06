#!/usr/bin/env bats -t
# umoci: Umoci Modifies Open Containers' Images
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

load helpers

function setup() {
	setup_image
}

function teardown() {
	teardown_image
}

@test "umoci config" {
	BUNDLE_A="$(setup_bundle)"
	BUNDLE_B="$(setup_bundle)"

	image-verify "${IMAGE}"

	# Unpack the image.
	umoci unpack --image "${IMAGE}:${TAG}" "$BUNDLE_A"
	[ "$status" -eq 0 ]
	bundle-verify "$BUNDLE_A"

	# We need to make sure the config exists.
	[ -f "$BUNDLE_A/config.json" ]

	# Modify none of the configuration.
	umoci config --image "${IMAGE}:${TAG}" --tag "${TAG}-new"
	[ "$status" -eq 0 ]
	image-verify "${IMAGE}"

	# Unpack the image again.
	umoci unpack --image "${IMAGE}:${TAG}-new" "$BUNDLE_B"
	[ "$status" -eq 0 ]
	bundle-verify "$BUNDLE_B"

	# Make sure that the config was unchanged.
	# First clean the config.
	jq -SM '.' "$BUNDLE_A/config.json" >"$BATS_TMPDIR/a-config.json"
	jq -SM '.' "$BUNDLE_B/config.json" >"$BATS_TMPDIR/b-config.json"
	sane_run diff -u "$BATS_TMPDIR/a-config.json" "$BATS_TMPDIR/b-config.json"
	[ "$status" -eq 0 ]
	[ -z "$output" ]

	# Make sure that the history was modified.
	umoci stat --image "${IMAGE}:${TAG}" --json
	[ "$status" -eq 0 ]
	numLinesA="$(echo "$output" | jq -SM '.history | length')"

	umoci stat --image "${IMAGE}:${TAG}-new" --json
	[ "$status" -eq 0 ]
	numLinesB="$(echo "$output" | jq -SM '.history | length')"

	# Number of lines should be greater.
	[ "$numLinesB" -gt "$numLinesA" ]
	# The final layer should be an empty_layer now.
	[[ "$(echo "$output" | jq -SM '.history[-1].empty_layer')" == "true" ]]

	image-verify "${IMAGE}"
}

@test "umoci config [missing args]" {
	umoci config
	[ "$status" -ne 0 ]
}

@test "umoci config --config.user 'user'" {
	BUNDLE_A="$(setup_bundle)"
	BUNDLE_B="$(setup_bundle)"

	image-verify "${IMAGE}"

	# Unpack the image.
	umoci unpack --image "${IMAGE}:${TAG}" "$BUNDLE_A"
	[ "$status" -eq 0 ]
	bundle-verify "$BUNDLE_A"

	# Modify /etc/passwd and /etc/group.
	echo "testuser:x:1337:8888:test user:/my home dir :/bin/sh" >> "$BUNDLE_A/rootfs/etc/passwd"
	echo "testgroup:x:2581:root,testuser" >> "$BUNDLE_A/rootfs/etc/group"
	echo "group:x:9001:testuser" >> "$BUNDLE_A/rootfs/etc/group"

	# Repack the image.
	umoci repack --image "${IMAGE}:${TAG}" "$BUNDLE_A"
	[ "$status" -eq 0 ]
	image-verify "${IMAGE}"

	# Modify the user.
	umoci config --image "${IMAGE}:${TAG}" --config.user="testuser"
	[ "$status" -eq 0 ]
	image-verify "${IMAGE}"

	# Unpack the image.
	umoci unpack --image "${IMAGE}:${TAG}" "$BUNDLE_B"
	[ "$status" -eq 0 ]
	bundle-verify "$BUNDLE_B"

	# Make sure numeric config was actually set.
	sane_run jq -SM '.process.user.uid' "$BUNDLE_B/config.json"
	[ "$status" -eq 0 ]
	[ "$output" -eq 1337 ]

	# Make sure numeric config was actually set.
	sane_run jq -SM '.process.user.gid' "$BUNDLE_B/config.json"
	[ "$status" -eq 0 ]
	[ "$output" -eq 8888 ]

	# Make sure additionalGids were set.
	sane_run jq -SMr '.process.user.additionalGids[]' "$BUNDLE_B/config.json"
	[ "$status" -eq 0 ]
	[ "${#lines[@]}" -eq 2 ]

	# Check mounts.
	printf -- '%s\n' "${lines[*]}" | grep '^9001$'
	printf -- '%s\n' "${lines[*]}" | grep '^2581$'

	# Check that HOME is set.
	sane_run jq -SMr '.process.env[]' "$BUNDLE_B/config.json"
	[ "$status" -eq 0 ]
	export $output
	[[ "$HOME" == "/my home dir " ]]

	image-verify "${IMAGE}"
}

@test "umoci config --config.user 'user:group'" {
	BUNDLE_A="$(setup_bundle)"
	BUNDLE_B="$(setup_bundle)"

	image-verify "${IMAGE}"

	# Unpack the image.
	umoci unpack --image "${IMAGE}:${TAG}" "$BUNDLE_A"
	[ "$status" -eq 0 ]
	bundle-verify "$BUNDLE_A"

	# Modify /etc/passwd and /etc/group.
	echo "testuser:x:1337:8888:test user:/my home dir :/bin/sh" >> "$BUNDLE_A/rootfs/etc/passwd"
	echo "testgroup:x:2581:root,testuser" >> "$BUNDLE_A/rootfs/etc/group"
	echo "group:x:9001:testuser" >> "$BUNDLE_A/rootfs/etc/group"
	echo "emptygroup:x:2222:" >> "$BUNDLE_A/rootfs/etc/group"

	# Repack the image.
	umoci repack --image "${IMAGE}:${TAG}" "$BUNDLE_A"
	[ "$status" -eq 0 ]
	image-verify "${IMAGE}"

	# Modify the user.
	umoci config --image "${IMAGE}:${TAG}" --config.user="testuser:emptygroup"
	[ "$status" -eq 0 ]
	image-verify "${IMAGE}"

	# Unpack the image.
	umoci unpack --image "${IMAGE}:${TAG}" "$BUNDLE_B"
	[ "$status" -eq 0 ]
	bundle-verify "$BUNDLE_B"

	# Make sure numeric config was actually set.
	sane_run jq -SM '.process.user.uid' "$BUNDLE_B/config.json"
	[ "$status" -eq 0 ]
	[ "$output" -eq 1337 ]

	# Make sure numeric config was actually set.
	sane_run jq -SM '.process.user.gid' "$BUNDLE_B/config.json"
	[ "$status" -eq 0 ]
	[ "$output" -eq 2222 ]

	# Make sure additionalGids were not set.
	sane_run jq -SMr '.process.user.additionalGids' "$BUNDLE_B/config.json"
	[ "$status" -eq 0 ]
	[[ "$output" == "null" ]]

	# Check that HOME is set.
	sane_run jq -SMr '.process.env[]' "$BUNDLE_B/config.json"
	[ "$status" -eq 0 ]
	export $output
	[[ "$HOME" == "/my home dir " ]]

	image-verify "${IMAGE}"
}

@test "umoci config --config.user 'user:group' [parsed from rootfs]" {
	BUNDLE_A="$(setup_bundle)"
	BUNDLE_B="$(setup_bundle)"
	BUNDLE_C="$(setup_bundle)"

	image-verify "${IMAGE}"

	# Unpack the image.
	umoci unpack --image "${IMAGE}:${TAG}" "$BUNDLE_A"
	[ "$status" -eq 0 ]
	bundle-verify "$BUNDLE_A"

	# Modify /etc/passwd and /etc/group.
	echo "testuser:x:1337:8888:test user:/my home dir :/bin/sh" >> "$BUNDLE_A/rootfs/etc/passwd"
	echo "testgroup:x:2581:root,testuser" >> "$BUNDLE_A/rootfs/etc/group"
	echo "group:x:9001:testuser" >> "$BUNDLE_A/rootfs/etc/group"
	echo "emptygroup:x:2222:" >> "$BUNDLE_A/rootfs/etc/group"

	# Repack the image.
	umoci repack --image "${IMAGE}:${TAG}" "$BUNDLE_A"
	[ "$status" -eq 0 ]
	image-verify "${IMAGE}"

	# Modify the user.
	umoci config --image "${IMAGE}:${TAG}" --config.user="testuser:emptygroup"
	[ "$status" -eq 0 ]
	image-verify "${IMAGE}"

	# Unpack the image.
	umoci unpack --image "${IMAGE}:${TAG}" "$BUNDLE_B"
	[ "$status" -eq 0 ]
	bundle-verify "$BUNDLE_B"

	# Make sure numeric config was actually set.
	sane_run jq -SM '.process.user.uid' "$BUNDLE_B/config.json"
	[ "$status" -eq 0 ]
	[ "$output" -eq 1337 ]

	# Make sure numeric config was actually set.
	sane_run jq -SM '.process.user.gid' "$BUNDLE_B/config.json"
	[ "$status" -eq 0 ]
	[ "$output" -eq 2222 ]

	# Check that HOME is set.
	sane_run jq -SMr '.process.env[]' "$BUNDLE_B/config.json"
	[ "$status" -eq 0 ]
	export $output
	[[ "$HOME" == "/my home dir " ]]

	# Modify /etc/passwd and /etc/group.
	sed -i -e 's|^testuser:x:1337:8888:test user:/my home dir :|testuser:x:3333:2321:a:/another  home:|' "$BUNDLE_B/rootfs/etc/passwd"
	sed -i -e 's|^emptygroup:x:2222:|emptygroup:x:4444:|' "$BUNDLE_B/rootfs/etc/group"

	# Repack the image.
	umoci repack --image "${IMAGE}:${TAG}" "$BUNDLE_B"
	[ "$status" -eq 0 ]
	image-verify "${IMAGE}"

	# Unpack the image.
	umoci unpack --image "${IMAGE}:${TAG}" "$BUNDLE_C"
	[ "$status" -eq 0 ]
	bundle-verify "$BUNDLE_C"

	# Make sure numeric config was actually set.
	sane_run jq -SM '.process.user.uid' "$BUNDLE_C/config.json"
	[ "$status" -eq 0 ]
	[ "$output" -eq 3333 ]

	# Make sure numeric config was actually set.
	sane_run jq -SM '.process.user.gid' "$BUNDLE_C/config.json"
	[ "$status" -eq 0 ]
	[ "$output" -eq 4444 ]

	# Check that HOME is set.
	sane_run jq -SMr '.process.env[]' "$BUNDLE_C/config.json"
	[ "$status" -eq 0 ]
	export $output
	[[ "$HOME" == "/another  home" ]]

	image-verify "${IMAGE}"
}

@test "umoci config --config.user 'user:group' [non-existent user]" {
	BUNDLE="$(setup_bundle)"

	# Modify the user.
	umoci config --image "${IMAGE}:${TAG}" --config.user="testuser:emptygroup"
	[ "$status" -eq 0 ]
	image-verify "${IMAGE}"

	# Unpack the image.
	umoci unpack --image "${IMAGE}:${TAG}" "$BUNDLE"
	[ "$status" -ne 0 ]

	image-verify "${IMAGE}"
}

@test "umoci config --config.user [numeric]" {
	BUNDLE="$(setup_bundle)"

	# Modify none of the configuration.
	umoci config --image "${IMAGE}:${TAG}" --tag "${TAG}-new" --config.user="1337:8888"
	[ "$status" -eq 0 ]
	image-verify "${IMAGE}"

	# Unpack the image again.
	umoci unpack --image "${IMAGE}:${TAG}-new" "$BUNDLE"
	[ "$status" -eq 0 ]
	bundle-verify "$BUNDLE"

	# Make sure numeric config was actually set.
	sane_run jq -SM '.process.user.uid' "$BUNDLE/config.json"
	[ "$status" -eq 0 ]
	[ "$output" -eq 1337 ]

	# Make sure numeric config was actually set.
	sane_run jq -SM '.process.user.gid' "$BUNDLE/config.json"
	[ "$status" -eq 0 ]
	[ "$output" -eq 8888 ]

	image-verify "${IMAGE}"
}

@test "umoci config --config.workingdir" {
	BUNDLE="$(setup_bundle)"

	# Modify none of the configuration.
	umoci config --image "${IMAGE}:${TAG}" --tag "${TAG}-new" --config.workingdir "/a/fake/directory"
	[ "$status" -eq 0 ]
	image-verify "${IMAGE}"

	# Unpack the image again.
	umoci unpack --image "${IMAGE}:${TAG}-new" "$BUNDLE"
	[ "$status" -eq 0 ]
	bundle-verify "$BUNDLE"

	# Make sure numeric config was actually set.
	sane_run jq -SM '.process.cwd' "$BUNDLE/config.json"
	[ "$status" -eq 0 ]
	[ "$output" = '"/a/fake/directory"' ]

	image-verify "${IMAGE}"
}

@test "umoci config --clear=config.env" {
	BUNDLE="$(setup_bundle)"

	# Modify none of the configuration.
	umoci config --image "${IMAGE}:${TAG}" --tag "${TAG}-new" --clear=config.env
	[ "$status" -eq 0 ]
	image-verify "${IMAGE}"

	# Unpack the image again.
	umoci unpack --image "${IMAGE}:${TAG}-new" "$BUNDLE"
	[ "$status" -eq 0 ]
	bundle-verify "$BUNDLE"

	# Make sure that only $HOME was set.
	sane_run jq -SMr '.process.env[]' "$BUNDLE/config.json"
	[ "$status" -eq 0 ]
	[[ "${lines[0]}" == *"HOME="* ]]
	[ "${#lines[@]}" -eq 1 ]

	image-verify "${IMAGE}"
}

@test "umoci config --config.env" {
	BUNDLE="$(setup_bundle)"

	# Modify env.
	umoci config --image "${IMAGE}:${TAG}" --tag "${TAG}-new" --config.env "VARIABLE1=unused"
	[ "$status" -eq 0 ]
	image-verify "${IMAGE}"

	# Modify the env again.
	umoci config --image "${IMAGE}:${TAG}-new" --config.env "VARIABLE1=test" --config.env "VARIABLE2=what"
	[ "$status" -eq 0 ]
	image-verify "${IMAGE}"

	# Unpack the image again.
	umoci unpack --image "${IMAGE}:${TAG}-new" "$BUNDLE"
	[ "$status" -eq 0 ]
	bundle-verify "$BUNDLE"

	# Make sure environment was set.
	sane_run jq -SMr '.process.env[]' "$BUNDLE/config.json"
	[ "$status" -eq 0 ]

	# Make sure that they are all unique.
	numDefs="${#lines[@]}"
	numVars="$(echo "$output" | cut -d= -f1 | sort -u | wc -l)"
	[ "$numDefs" -eq "$numVars" ]

	# Set the variables.
	export $output
	[[ "$VARIABLE1" == "test" ]]
	[[ "$VARIABLE2" == "what" ]]

	image-verify "${IMAGE}"
}

@test "umoci config --config.cmd" {
	BUNDLE="$(setup_bundle)"

	# Modify none of the configuration.
	umoci config --image "${IMAGE}:${TAG}" --config.cmd "cat" --config.cmd "/this is a file with spaces" --config.cmd "-v"
	[ "$status" -eq 0 ]
	image-verify "${IMAGE}"

	# Unpack the image again.
	umoci unpack --image "${IMAGE}:${TAG}" "$BUNDLE"
	[ "$status" -eq 0 ]
	bundle-verify "$BUNDLE"

	# Ensure that the final args is entrypoint+cmd.
	sane_run jq -SMr 'reduce .process.args[] as $arg (""; . + $arg + ";")' "$BUNDLE/config.json"
	[ "$status" -eq 0 ]
	[[ "$output" == "cat;/this is a file with spaces;-v;" ]]

	image-verify "${IMAGE}"
}

@test "umoci config --config.[entrypoint+cmd]" {
	BUNDLE="$(setup_bundle)"

	# Modify none of the configuration.
	umoci config --image "${IMAGE}:${TAG}" --config.entrypoint "sh" --config.cmd "-c" --config.cmd "ls -la"
	[ "$status" -eq 0 ]
	image-verify "${IMAGE}"

	# Unpack the image again.
	umoci unpack --image "${IMAGE}:${TAG}" "$BUNDLE"
	[ "$status" -eq 0 ]
	bundle-verify "$BUNDLE"

	# Ensure that the final args is entrypoint+cmd.
	sane_run jq -SMr 'reduce .process.args[] as $arg (""; . + $arg + ";")' "$BUNDLE/config.json"
	[ "$status" -eq 0 ]
	[[ "$output" == "sh;-c;ls -la;" ]]

	image-verify "${IMAGE}"
}

# XXX: This test is somewhat dodgy (since we don't actually set anything other than the destination for a volume).
@test "umoci config --config.volume" {
	BUNDLE_A="$(setup_bundle)"
	BUNDLE_B="$(setup_bundle)"
	BUNDLE_C="$(setup_bundle)"

	# Modify none of the configuration.
	umoci config --image "${IMAGE}:${TAG}" --config.volume /volume --config.volume "/some nutty/path name/ here"
	[ "$status" -eq 0 ]
	image-verify "${IMAGE}"

	# Unpack the image again.
	umoci unpack --image "${IMAGE}:${TAG}" "$BUNDLE_A"
	[ "$status" -eq 0 ]
	bundle-verify "$BUNDLE_A"

	# Get set of mounts
	sane_run jq -SMr '.mounts[] | .destination' "$BUNDLE_A/config.json"
	[ "$status" -eq 0 ]

	# Check mounts.
	printf -- '%s\n' "${lines[*]}" | grep '^/volume$'
	printf -- '%s\n' "${lines[*]}" | grep '^/some nutty/path name/ here$'

	# Make sure we're appending.
	umoci config --image "${IMAGE}:${TAG}" --config.volume "/another volume"
	[ "$status" -eq 0 ]
	image-verify "${IMAGE}"

	# Unpack the image again.
	umoci unpack --image "${IMAGE}:${TAG}" "$BUNDLE_B"
	[ "$status" -eq 0 ]
	bundle-verify "$BUNDLE_B"

	# Get set of mounts
	sane_run jq -SMr '.mounts[] | .destination' "$BUNDLE_B/config.json"
	[ "$status" -eq 0 ]

	# Check mounts.
	printf -- '%s\n' "${lines[*]}" | grep '^/volume$'
	printf -- '%s\n' "${lines[*]}" | grep '^/some nutty/path name/ here$'
	printf -- '%s\n' "${lines[*]}" | grep '^/another volume$'

	# Now clear the volumes
	umoci config --image "${IMAGE}:${TAG}" --clear=config.volume --config.volume "/..final_volume"
	[ "$status" -eq 0 ]
	image-verify "${IMAGE}"

	# Unpack the image again.
	umoci unpack --image "${IMAGE}:${TAG}" "$BUNDLE_C"
	[ "$status" -eq 0 ]
	bundle-verify "$BUNDLE_C"

	# Get set of mounts
	sane_run jq -SMr '.mounts[] | .destination' "$BUNDLE_C/config.json"
	[ "$status" -eq 0 ]

	# Check mounts.
	! ( printf -- '%s\n' "${lines[*]}" | grep '^/volume$' )
	! ( printf -- '%s\n' "${lines[*]}" | grep '^/some nutty/path name/ here$' )
	! ( printf -- '%s\n' "${lines[*]}" | grep '^/another volume$' )
	printf -- '%s\n' "${lines[*]}" | grep '^/\.\.final_volume$'

	image-verify "${IMAGE}"
}

@test "umoci config --[os+architecture]" {
	BUNDLE="$(setup_bundle)"

	# Modify none of the configuration.
	# XXX: We can't test anything other than --os=linux because our generator bails for non-Linux OSes.
	umoci config --image "${IMAGE}:${TAG}" --os "linux" --architecture "mips64"
	[ "$status" -eq 0 ]
	image-verify "${IMAGE}"

	# Unpack the image again.
	umoci unpack --image "${IMAGE}:${TAG}" "$BUNDLE"
	[ "$status" -eq 0 ]
	bundle-verify "$BUNDLE"

	# Check that OS was set properly.
	sane_run jq -SMr '.platform.os' "$BUNDLE/config.json"
	[ "$status" -eq 0 ]
	[[ "$output" == "linux" ]]

	# Check that arch was set properly.
	sane_run jq -SMr '.platform.arch' "$BUNDLE/config.json"
	[ "$status" -eq 0 ]
	[[ "$output" == "mips64" ]]

	image-verify "${IMAGE}"
}

# XXX: This doesn't do any actual testing of the results of any of these flags.
# This needs to be fixed after we implement raw-cat or something like that.
@test "umoci config --[author+created]" {
	# Modify everything.
	umoci config --image "${IMAGE}:${TAG}" --tag "${TAG}-new" --author="Aleksa Sarai <asarai@suse.com>" --created="2016-03-25T12:34:02.655002+11:00"
	[ "$status" -eq 0 ]
	image-verify "${IMAGE}"

	# Make sure that --created doesn't work with a random string.
	umoci config --image "${IMAGE}:${TAG}" --created="not a date"
	[ "$status" -ne 0 ]
	image-verify "${IMAGE}"
	umoci config --image "${IMAGE}:${TAG}" --created="Jan 04 2004"
	[ "$status" -ne 0 ]
	image-verify "${IMAGE}"

	# Make sure that the history was modified and the author is now me.
	umoci stat --image "${IMAGE}:${TAG}" --json
	[ "$status" -eq 0 ]
	numLinesA="$(echo "$output" | jq -SMr '.history | length')"

	umoci stat --image "${IMAGE}:${TAG}-new" --json
	[ "$status" -eq 0 ]
	numLinesB="$(echo "$output" | jq -SMr '.history | length')"

	# Number of lines should be greater.
	[ "$numLinesB" -gt "$numLinesA" ]
	# The final layer should be an empty_layer now.
	[[ "$(echo "$output" | jq -SMr '.history[-1].empty_layer')" == "true" ]]
	# The author should've changed.
	[[ "$(echo "$output" | jq -SMr '.history[-1].author')" == "Aleksa Sarai <asarai@suse.com>" ]]

	image-verify "${IMAGE}"
}

# XXX: We don't do any testing of --author and that the config is changed properly.
@test "umoci config --history.*" {
	# Modify something and set the history values.
	umoci config --image "${IMAGE}:${TAG}" --tag "${TAG}-new" \
		--history.author="Not Aleksa <someone@else.com>" \
		--history.comment="/* Not a real comment. */" \
		--history.created_by="-- <bats> integration test --" \
		--history.created="2016-12-09T04:45:40+11:00" \
		--author="Aleksa Sarai <asarai@suse.com>"
	[ "$status" -eq 0 ]
	image-verify "${IMAGE}"

	# Make sure that the history was modified.
	umoci stat --image "${IMAGE}:${TAG}" --json
	[ "$status" -eq 0 ]
	numLinesA="$(echo "$output" | jq -SMr '.history | length')"

	umoci stat --image "${IMAGE}:${TAG}-new" --json
	[ "$status" -eq 0 ]
	numLinesB="$(echo "$output" | jq -SMr '.history | length')"

	# Number of lines should be greater.
	[ "$numLinesB" -gt "$numLinesA" ]
	# The final layer should be an empty_layer now.
	[[ "$(echo "$output" | jq -SMr '.history[-1].empty_layer')" == "true" ]]
	# The author should've changed to --history.author.
	[[ "$(echo "$output" | jq -SMr '.history[-1].author')" == "Not Aleksa <someone@else.com>" ]]
	# The comment should be added.
	[[ "$(echo "$output" | jq -SMr '.history[-1].comment')" == "/* Not a real comment. */" ]]
	# The created_by should be set.
	[[ "$(echo "$output" | jq -SMr '.history[-1].created_by')" == "-- <bats> integration test --" ]]
	# The created should be set.
	[[ "$(echo "$output" | jq -SMr '.history[-1].created')" == "2016-12-09T04:45:40+11:00" ]]

	image-verify "${IMAGE}"
}

@test "umoci config --config.label" {
	BUNDLE="$(setup_bundle)"

	# Modify none of the configuration.
	umoci config --image "${IMAGE}:${TAG}" --tag "${TAG}-new" \
		--clear=config.labels --clear=manifest.annotations \
		--config.label="com.cyphar.test=1" --config.label="com.cyphar.empty="
	[ "$status" -eq 0 ]
	image-verify "${IMAGE}"

	# Unpack the image again.
	umoci unpack --image "${IMAGE}:${TAG}-new" "$BUNDLE"
	[ "$status" -eq 0 ]
	bundle-verify "$BUNDLE"

	sane_run jq -SMr '.annotations["com.cyphar.test"]' "$BUNDLE/config.json"
	[ "$status" -eq 0 ]
	[[ "$output" == "1" ]]

	sane_run jq -SMr '.annotations["com.cyphar.empty"]' "$BUNDLE/config.json"
	[ "$status" -eq 0 ]
	[[ "$output" == "" ]]

	image-verify "${IMAGE}"
}

@test "umoci config --manifest.annotation" {
	BUNDLE="$(setup_bundle)"

	# Modify none of the configuration.
	umoci config --image "${IMAGE}:${TAG}" --tag "${TAG}-new" \
		--clear=config.labels --clear=manifest.annotations \
		--manifest.annotation="com.cyphar.test=1" --manifest.annotation="com.cyphar.empty="
	[ "$status" -eq 0 ]
	image-verify "${IMAGE}"

	# Unpack the image again.
	umoci unpack --image "${IMAGE}:${TAG}-new" "$BUNDLE"
	[ "$status" -eq 0 ]
	bundle-verify "$BUNDLE"

	sane_run jq -SMr '.annotations["com.cyphar.test"]' "$BUNDLE/config.json"
	[ "$status" -eq 0 ]
	[[ "$output" == "1" ]]

	sane_run jq -SMr '.annotations["com.cyphar.empty"]' "$BUNDLE/config.json"
	[ "$status" -eq 0 ]
	[[ "$output" == "" ]]

	image-verify "${IMAGE}"
}

@test "umoci config --config.label --manifest.annotation" {
	BUNDLE="$(setup_bundle)"

	# Modify none of the configuration.
	umoci config --image "${IMAGE}:${TAG}" --tag "${TAG}-new" \
		--clear=config.labels --clear=manifest.annotations \
		--config.label="com.cyphar.label_test={another value}" --config.label="com.cyphar.label_empty=" \
		--manifest.annotation="com.cyphar.manifest_test= another valu=e  " --manifest.annotation="com.cyphar.manifest_empty="
	[ "$status" -eq 0 ]
	image-verify "${IMAGE}"

	# Unpack the image again.
	umoci unpack --image "${IMAGE}:${TAG}-new" "$BUNDLE"
	[ "$status" -eq 0 ]
	bundle-verify "$BUNDLE"

	sane_run jq -SMr '.annotations["com.cyphar.label_test"]' "$BUNDLE/config.json"
	[ "$status" -eq 0 ]
	[[ "$output" == "{another value}" ]]

	sane_run jq -SMr '.annotations["com.cyphar.label_empty"]' "$BUNDLE/config.json"
	[ "$status" -eq 0 ]
	[[ "$output" == "" ]]

	sane_run jq -SMr '.annotations["com.cyphar.manifest_test"]' "$BUNDLE/config.json"
	[ "$status" -eq 0 ]
	[[ "$output" == " another valu=e  " ]]

	sane_run jq -SMr '.annotations["com.cyphar.manifest_empty"]' "$BUNDLE/config.json"
	[ "$status" -eq 0 ]
	[[ "$output" == "" ]]

	image-verify "${IMAGE}"
}

# XXX: This is currently not in any spec. So we'll just test our own behaviour
#      here and we can fix it after opencontainers/image-spec#479 is fixed.
@test "umoci config --config.label --manifest.annotation [clobber]" {
	BUNDLE="$(setup_bundle)"

	# Modify none of the configuration.
	umoci config --image "${IMAGE}:${TAG}" --tag "${TAG}-new" \
		--clear=config.labels --clear=manifest.annotations \
		--config.label="com.cyphar.test= this_is SOEM VALUE" --config.label="com.cyphar.label_empty=" \
		--manifest.annotation="com.cyphar.test== __ --a completely different VALuE    " --manifest.annotation="com.cyphar.manifest_empty="
	[ "$status" -eq 0 ]
	image-verify "${IMAGE}"

	# Unpack the image again.
	umoci unpack --image "${IMAGE}:${TAG}-new" "$BUNDLE"
	[ "$status" -eq 0 ]
	bundle-verify "$BUNDLE"

	# Manifest beats config.
	sane_run jq -SMr '.annotations["com.cyphar.test"]' "$BUNDLE/config.json"
	[ "$status" -eq 0 ]
	[[ "$output" == "= __ --a completely different VALuE    " ]]

	sane_run jq -SMr '.annotations["com.cyphar.label_empty"]' "$BUNDLE/config.json"
	[ "$status" -eq 0 ]
	[[ "$output" == "" ]]

	sane_run jq -SMr '.annotations["com.cyphar.manifest_empty"]' "$BUNDLE/config.json"
	[ "$status" -eq 0 ]
	[[ "$output" == "" ]]

	image-verify "${IMAGE}"
}
