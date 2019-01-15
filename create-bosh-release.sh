#!/bin/bash

POSITIONAL=()
while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    -hzv|--hazelcast-version)
    HZ_VERSION="$2"
    shift
    shift
    ;;
    -v|--release-version)
    {RELEASE_VERSION}="$2"
    shift
    shift
    ;;
    -gt|--github-token)
    {GITHUB_TOKEN}="$2"
    shift
    shift
    ;;
    -s3a|--aws-s3-access-key)
    {AWS_S3_ACCESS_KEY}="$2"
    shift
    shift
    ;;
    -s3k|--aws-s3-secret-key)
    {AWS_S3_SECRET_KEY}="$2"
    shift
    shift
esac
done
set -- "${POSITIONAL[@]}"

echo RELEASE VERSION = "${RELEASE_VERSION}"
echo HAZELCAST VERSION = "${HZ_VERSION}"
echo GITHUB TOKEN = "${GITHUB_TOKEN}"
echo AWS_S3_ACCESS_KEY = "${AWS_S3_ACCESS_KEY}"
echo AWS_S3_SECRET_KEY = "${AWS_S3_SECRET_KEY}"

HZ_EE_JAR_URL=https://repository-hazelcast-l337.forge.cloudbees.com/release/com/hazelcast/hazelcast-enterprise/${HZ_VERSION}/hazelcast-enterprise-${HZ_VERSION}.jar
MC_WAR_URL=https://download.hazelcast.com/management-center/hazelcast-management-center-${HZ_VERSION}.zip

pushd $HOME
    echo "Clonning bosh-release repo"
    git config --global credential.helper cache
    git clone --recurse-submodules https://x-access-token:${GITHUB_TOKEN}@github.com/hazelcast/hazelcast-boshrelease.git || { echo "Check your GitHub Token!!" ; exit 1; }

    echo "Downloading jar/war(s)..."
    if wget -q "$HZ_EE_JAR_URL"; then
        echo "Hazelcast EE jar downloaded succesfully"
    else
        echo "Hazelcast EE jar download FAILED"
        exit 1;
    fi

    if wget -q "$MC_WAR_URL"; then
        unzip hazelcast-management-center-${HZ_VERSION}.zip
        mv hazelcast-management-center-${HZ_VERSION}/hazelcast-mancenter-${HZ_VERSION}.war ./
        rm hazelcast-management-center-${HZ_VERSION}.zip
        rm -r hazelcast-management-center-${HZ_VERSION}
        echo "Management Center war downloaded succesfully"
    else
        echo "Management Center war download FAILED"
        exit 1;
    fi

    # python libraries need gcc and python-dev to compile
    apk add gcc musl-dev python-dev
    pip install -r $HOME/requirements.txt

    pushd ./hazelcast-boshrelease
        echo "Updating hazelcast versions at packages' spec..."
        sed -i "s/hazelcast-enterprise-.*/hazelcast-enterprise-${HZ_VERSION}.jar/g" packages/hazelcast/spec
        sed -i "s/hazelcast-mancenter-.*/hazelcast-mancenter-${HZ_VERSION}.war/g" packages/mancenter/spec

        echo "Removing existing EE and MC blobs from yml file..."
        python ../clean_blobs_yml.py -f config/blobs.yml

        echo "Creating private.yml..."
        python ../create_modify_private_yml.py -a ${AWS_S3_ACCESS_KEY} -s ${AWS_S3_SECRET_KEY} -o config/private.yml

        if bosh sync-blobs; then
            echo "Non-hazelcast blobs downloded from S3 succesfully..."
        else
            echo "bosh-cli can not connect S3. Check your AWS credential or its permissions!!"
            exit 1;
        fi
        echo "Adding Hazelcast jar/war(s) as a blobs..."
        bosh add-blob ../hazelcast-enterprise-${HZ_VERSION}.jar hazelcast-enterprise/hazelcast-enterprise-${HZ_VERSION}.jar
        bosh add-blob ../hazelcast-mancenter-${HZ_VERSION}.war mancenter/hazelcast-mancenter-${HZ_VERSION}.war
        bosh upload-blobs

        git add . && git commit -m "upgraded hazelcast and mancenter to ${HZ_VERSION} for ${RELEASE_VERSION} release"

        echo "Creating hazelcast bosh-release tar.gz..."
        bosh create-release --version ${RELEASE_VERSION} --tarball ../hazelcast-boshrelease-${RELEASE_VERSION}.tgz

        echo "Pushing changes to master..."
        git push origin master
        git tag v${RELEASE_VERSION}
        git push --tags
        echo "v${RELEASE_VERSION} pushed to master"

        echo "Creating release at hazelcast/hazelcast-boshrelease repo"
        python ../create_release_upload_asset.py -r hazelcast/hazelcast-boshrelease -t ${GITHUB_TOKEN} -v ${RELEASE_VERSION} -hzv ${HZ_VERSION} -a ../hazelcast-boshrelease-${RELEASE_VERSION}.tgz
        echo "${RELEASE_VERSION} created and its assets are uploaded"
    popd
popd

