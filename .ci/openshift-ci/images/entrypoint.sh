#!/bin/bash
#
# Copyright (c) 2020 Red Hat Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
# Synchronize the kata-containers installation with in the host filesystem.
#
set -e
set -o nounset

install_status=1

SRC="${PWD}/_out/build_install"

# Expect the host filesystem to be mounted in following path.
HOST_MOUNT=/host

function terminate()
{
	# Sending a termination message. Can be used by an orchestrator that
	# will look into this file to check the installation has finished
	# and is good.
	#
	echo "INFO: the installation status is $install_status"
	echo "$install_status" >> /tmp/kata_install_status

	# By using it in an openshift daemonset it should spin forever until an
	# orchestrator kills it.
	#
	echo "INFO: spinning until the orchestrator kill this process"
	tail -f /dev/null
}

if [ "$(id -u)" -ne 0 ]; then
	echo "ERROR: $0 must be executed by privileged user"
	terminate
fi

# Some files are copied over /usr which on Red Hat CoreOS (rhcos) is mounted
# read-only by default. So re-mount it as read-write, otherwise files won't
# get copied.
echo "INFO: re-mount ${HOST_MOUNT}/usr on rw mode"
mount -o remount,rw "${HOST_MOUNT}/usr"

# The host's '/opt' and '/usr/local' are symlinks to, respectively, '/var/opt'
# and '/var/usrlocal'. Adjust the installation files accordingly.
#
cd $SRC
if [ -d 'opt' ]; then
	mkdir -p var
	mv opt var
fi

if [ -d "usr/local" ]; then
	mkdir -p var
	mv usr/local var/usrlocal
fi

# Copy the installation over the host filesystem.
echo "INFO: copy the Kata Containers installation over $HOST_MOUNT"
rsync -O -a . "$HOST_MOUNT"

# Ensure the binaries are searcheable via PATH. Notice it expects that
# kata has been built with PREFIX=/opt/kata.
#
chroot "$HOST_MOUNT" sh -c 'for t in /opt/kata/bin/*; do ln -s "$t" /var/usrlocal/bin/; done'

# Check the installation is good (or not).
echo "INFO: run kata-check to check the installation is fine"
chroot "$HOST_MOUNT" /opt/kata/bin/kata-runtime kata-check
install_status=$?

terminate
