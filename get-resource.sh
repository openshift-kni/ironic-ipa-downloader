#!/bin/bash -xe
#CACHEURL=http://172.22.0.1/images

# Which image should we use
SNAP=${1:-current-tripleo-rdo}

FILENAME=ironic-python-agent
FILENAME_EXT=.tar
FFILENAME=$FILENAME$FILENAME_EXT

mkdir -p /shared/html/images /shared/tmp
cd /shared/html/images

TMPDIR=$(mktemp -d -p /shared/tmp)

# Is this a RHEL based image? If so the IPA image is already here, so
# we don't need to download it
if [ -e /usr/share/rhosp-director-images/ironic-python-agent-latest.tar ] ; then
    VERSION=$(cat /usr/share/rhosp-director-images/version-latest.txt)
    if [ ! -e $FILENAME-$VERSION ] ; then
        cd $TMPDIR
        tar -xf /usr/share/rhosp-director-images/ironic-python-agent-latest.tar

        # Update netconfig to use MAC for DUID/IAID combo (same as RHCOS)
        # FIXME: we need an alternative of this packaged
        gzip -dc ironic-python-agent.initramfs > ironic-python-agent.data
        mkdir -p etc/NetworkManager/conf.d/ etc/NetworkManager/dispatcher.d
        echo -e '[main]\ndhcp=dhclient\n[connection]\nipv6.dhcp-duid=ll' > etc/NetworkManager/conf.d/clientid.conf
        echo -e '[[ "$DHCP6_FQDN_FQDN" =~ - ]] && hostname $DHCP6_FQDN_FQDN' > etc/NetworkManager/dispatcher.d/01-hostname
        chmod +x etc/NetworkManager/dispatcher.d/01-hostname
        echo -e  "./etc/NetworkManager/conf.d/clientid.conf\n./etc/NetworkManager/dispatcher.d/01-hostname" | cpio -H newc -o >> ironic-python-agent.data
        gzip -5 ironic-python-agent.data
        mv ironic-python-agent.data.gz ironic-python-agent.initramfs
        rm -rf etc

        chmod 755 $TMPDIR
        cd -
        mv $TMPDIR $FILENAME-$VERSION
    fi
    ln -sf $FILENAME-$VERSION/$FILENAME.initramfs $FILENAME.initramfs
    ln -sf $FILENAME-$VERSION/$FILENAME.kernel $FILENAME.kernel
    exit 0
fi

# If we have a CACHEURL and nothing has yet been downloaded
# get header info from the cache
ls -l
if [ -n "$CACHEURL" -a ! -e $FFILENAME.headers ] ; then
    curl --fail -O "$CACHEURL/$FFILENAME.headers" || true
fi

# Download the most recent version of IPA
if [ -e $FFILENAME.headers ] ; then
    ETAG=$(awk '/ETag:/ {print $2}' $FFILENAME.headers | tr -d "\r")
    cd $TMPDIR
    curl --dump-header $FFILENAME.headers -O https://images.rdoproject.org/stein/rdo_trunk/$SNAP/$FFILENAME --header "If-None-Match: $ETAG"
    # curl didn't download anything because we have the ETag already
    # but we don't have it in the images directory
    # Its in the cache, go get it
    ETAG=$(awk '/ETag:/ {print $2}' $FFILENAME.headers | tr -d "\"\r")
    if [ ! -s $FFILENAME -a ! -e /shared/html/images/$FILENAME-$ETAG/$FFILENAME ] ; then
        mv /shared/html/images/$FFILENAME.headers .
        curl -O "$CACHEURL/$FILENAME-$ETAG/$FFILENAME"
    fi
else
    cd $TMPDIR
    curl --dump-header $FFILENAME.headers -O https://images.rdoproject.org/stein/rdo_trunk/$SNAP/$FFILENAME
fi

if [ -s $FFILENAME ] ; then
    tar -xf $FFILENAME

    ETAG=$(awk '/ETag:/ {print $2}' $FFILENAME.headers | tr -d "\"\r")
    cd -
    chmod 755 $TMPDIR
    mv $TMPDIR $FILENAME-$ETAG
    ln -sf $FILENAME-$ETAG/$FFILENAME.headers $FFILENAME.headers
    ln -sf $FILENAME-$ETAG/$FILENAME.initramfs $FILENAME.initramfs
    ln -sf $FILENAME-$ETAG/$FILENAME.kernel $FILENAME.kernel
else
    rm -rf $TMPDIR
fi
