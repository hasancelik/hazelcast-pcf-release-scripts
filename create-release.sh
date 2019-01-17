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
    RELEASE_VERSION="$2"
    shift
    shift
    ;;
    -gt|--github-token)
    GITHUB_TOKEN="$2"
    shift
    shift
    ;;
    -ge|--github-email)
    GITHUB_EMAIL="$2"
    shift
    shift
    ;;
    -prt|--pivnet-refresh-token)
    REFRESH_TOKEN="$2"
    shift
    shift
    ;;
    -s3a|--aws-s3-access-key)
    AWS_S3_ACCESS_KEY="$2"
    shift
    shift
    ;;
    -s3k|--aws-s3-secret-key)
    AWS_S3_SECRET_KEY="$2"
    shift
    shift
    ;;
    --disable-deployment)
    DEPLOYMENT_DISABLED="YES"
    shift
    ;;
    *)
    POSITIONAL+=("$1")
    shift
    ;;
esac
done
set -- "${POSITIONAL[@]}"

echo RELEASE VERSION = "${RELEASE_VERSION}"
echo HAZELCAST VERSION = "${HZ_VERSION}"
echo GITHUB TOKEN = "${GITHUB_TOKEN}"
echo GITHUB EMAIL = "${GITHUB_EMAIL}"
echo REFRESH_TOKEN = "${REFRESH_TOKEN}"
echo AWS S3 ACCESS KEY = "${AWS_S3_ACCESS_KEY}"
echo AWS S3 SECRET KEY = "${AWS_S3_SECRET_KEY}"
echo DEPLOYMENT DISABLED = "${DEPLOYMENT_DISABLED}"

HZ_EE_JAR_URL=https://repository-hazelcast-l337.forge.cloudbees.com/release/com/hazelcast/hazelcast-enterprise/${HZ_VERSION}/hazelcast-enterprise-${HZ_VERSION}.jar
MC_WAR_URL=https://download.hazelcast.com/management-center/hazelcast-management-center-${HZ_VERSION}.zip

ROUTING_RELEASE_URL=https://github.com/cloudfoundry/routing-release/releases/download/0.174.0/routing-0.174.0.tgz

echo "Configuring e-mail for github..."
git config --global user.email "${GITHUB_EMAIL}"

pushd $WORKSPACE
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

        if [[ ! -v DEPLOYMENT_DISABLED ]]; then
            echo "Pushing changes to master..."
            git push origin master
            git tag v${RELEASE_VERSION}
            git push --tags
            echo "v${RELEASE_VERSION} pushed to master"

            echo "Creating release at hazelcast/hazelcast-boshrelease repo"
            python ../create_release_upload_asset.py -r hazelcast/hazelcast-boshrelease -t ${GITHUB_TOKEN} -v ${RELEASE_VERSION} -hzv ${HZ_VERSION} -a ../hazelcast-boshrelease-${RELEASE_VERSION}.tgz
            echo "${RELEASE_VERSION} created and its assets are uploaded"
        fi
    popd

    pushd ./hazelcast-pcf-tile
        echo "Downloading On Demand Services Broker 0.25.0 BOSH release..."
        pivnet login --api-token=${REFRESH_TOKEN}
        pivnet download-product-files -p on-demand-services-sdk -r 0.25.0 -i 270128 -d ./resources

        echo "Downloading Routing 0.174.0 BOSH release..."
        if wget -O ./resources/routing-0.174.0.tgz -q "$ROUTING_RELEASE_URL"; then
            echo "Routing 0.174.0 downloaded succesfully"
        else
            echo "Routing download FAILED!"
            exit 1;
        fi

        echo "Copying hazelcast-bosh-release file to tile repo..."
        cp ../hazelcast-boshrelease-${RELEASE_VERSION}.tgz ./resources

        echo "Modifying tile.yml..."
        python ../modify_tile_yml.py -v ${RELEASE_VERSION} -f ./tile.yml

        tile build ${RELEASE_VERSION}
    popd
popd

