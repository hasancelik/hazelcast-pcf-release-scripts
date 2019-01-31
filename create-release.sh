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
    -t|--release-type)
    RELEASE_TYPE="$2"
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
    --deploy-OSDF-manually)
    DEPLOY_OSDF_MANUALLY="YES"
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
# Minor Release, Major Release, Release Candidate
echo RELEASE TYPE = "${RELEASE_TYPE}"
echo HAZELCAST VERSION = "${HZ_VERSION}"
echo GITHUB TOKEN = "${GITHUB_TOKEN}"
echo GITHUB EMAIL = "${GITHUB_EMAIL}"
echo REFRESH TOKEN = "${REFRESH_TOKEN}"
echo AWS S3 ACCESS KEY = "${AWS_S3_ACCESS_KEY}"
echo AWS S3 SECRET KEY = "${AWS_S3_SECRET_KEY}"
echo DEPLOYMENT DISABLED = "${DEPLOYMENT_DISABLED}"
echo DEPLOY OSDF MANUALLY = "${DEPLOY_OSDF_MANUALLY}"

PRODUCT_SLUG_NAME="hazelcast-pcf"
EULA_SLUG_NAME="hazelcast-eula"
DOCS_URL="https://github.com/pivotal-cf/docs-hazelcast"

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

        # if [[ ! -v DEPLOYMENT_DISABLED ]]; then
        #     echo "Pushing changes to master..."
        #     git push origin master
        #     git tag v${RELEASE_VERSION}
        #     git push --tags
        #     echo "v${RELEASE_VERSION} pushed to master"

        #     echo "Creating release at hazelcast/hazelcast-boshrelease repo"
        #     python ../create_release_upload_asset.py -r hazelcast/hazelcast-boshrelease -t ${GITHUB_TOKEN} -v ${RELEASE_VERSION} -hzv ${HZ_VERSION} -a ../hazelcast-boshrelease-${RELEASE_VERSION}.tgz
        #     echo "${RELEASE_VERSION} created and its assets are uploaded"
        # fi
    popd

    pushd ./hazelcast-pcf-tile
        pivnet login --api-token=${REFRESH_TOKEN} || { echo 'Could not login to piv-net.Check REFRESH TOKEN!' ; exit 1; }
        echo "Downloading On Demand Services Broker 0.25.0 BOSH release..."
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

        echo "Creating .pivotal file..."
        if tile build ${RELEASE_VERSION}; then
            echo "hazelcast-pcf-" + ${RELEASE_VERSION} + ".pivotal created succesfully"
        else
            echo "Error creating hazelcast-pcf-${RELEASE_VERSION}.pivotal!"
            exit 1;
        fi

        git add . && git commit -m "upgraded hazelcast and mancenter to ${HZ_VERSION} for ${RELEASE_VERSION} release"

        if [[ ! -v DEPLOYMENT_DISABLED ]]; then
            # echo "Pushing changes to master..."
            # git push origin master
            # git tag v${RELEASE_VERSION}
            # git push --tags
            # echo "v${RELEASE_VERSION} pushed to master"

            # echo "Creating release at hazelcast/hazelcast-boshrelease repo"
            # python ../create_release_upload_asset.py -r hazelcast/hazelcast-pcf-tile -t ${GITHUB_TOKEN} -v ${RELEASE_VERSION} -hzv ${HZ_VERSION} -a ./product/hazelcast-pcf-${RELEASE_VERSION}.pivotal
            # echo "${RELEASE_VERSION} created and its assets are uploaded"

            PIVNET_ACCESS_TOKEN=`curl -s https://network.pivotal.io/api/v2/authentication/access_tokens -d "{\"refresh_token\":\"${REFRESH_TOKEN}\"}" | jq -r '.access_token'`
            if [ -z "${PIVNET_ACCESS_TOKEN}" ] || [ "${PIVNET_ACCESS_TOKEN}" = "null" ]
                then
                    echo "Error getting PivNet access token!"
                    exit 1
            fi

            IFS=',' read AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN s3Bucket s3Region < <(curl -s https://network.pivotal.io/api/v2/federation_token -d "{\"product_id\": \"${PRODUCT_SLUG_NAME}\"}"  -H "Authorization: Bearer ${PIVNET_ACCESS_TOKEN}" | jq -r '[.access_key_id, .secret_access_key, .session_token, .bucket, .region] | @csv' | sed 's/"//g')
            export AWS_ACCESS_KEY_ID
            export AWS_SECRET_ACCESS_KEY
            export AWS_SESSION_TOKEN
            if [ -z "${AWS_ACCESS_KEY_ID}" ] || [ "${AWS_ACCESS_KEY_ID}" = "null" ] || [ -z "${AWS_SECRET_ACCESS_KEY}" ] || [ "${AWS_SECRET_ACCESS_KEY}" = "null" ] || [ -z "${AWS_SESSION_TOKEN}" ] || [ "${AWS_SESSION_TOKEN}" = "null" ]
                then
                    echo "Error getting PivNet AWS credentials!"
                    exit 1
            fi

            echo "Uploading .pivotal file to PivNet's S3 bucket..."
            aws s3 cp ./product/hazelcast-pcf-${RELEASE_VERSION}.pivotal s3://$s3Bucket/partner-product-files/hazelcast-pcf-${RELEASE_VERSION}-test.pivotal --region $s3Region || { echo 'Could not upload .pivotal file to S3 Bucket!' ; exit 1; }

            FILE_SHA256=`sha256sum ./product/hazelcast-pcf-${RELEASE_VERSION}.pivotal | cut -f1 -d ' '`
            FILE_MD5=`md5sum ./product/hazelcast-pcf-${RELEASE_VERSION}.pivotal | cut -f1 -d ' '`

            echo "Adding .pivotal file to PivNet..."
            TILE_PRODUCT_FILE_ID=`pivnet --format=json create-product-file --product-slug="hazelcast-pcf" --name="Hazelcast IMDG for PCF ${RELEASE_VERSION}" --aws-object-key="partner-product-files/hazelcast-pcf-${RELEASE_VERSION}-test.pivotal" --file-type='Software' --file-version=${RELEASE_VERSION} --sha256=${FILE_SHA256} --md5=${FILE_MD5} --docs-url=${DOCS_URL} | jq '.product_file.id'`
            if [ -z "$TILE_PRODUCT_FILE_ID" ]
            then
	            echo "Error adding product file"
                exit 1
            else
                echo "Added file hazelcast-pcf-${RELEASE_VERSION}.pivotal. Product file ID: ${TILE_PRODUCT_FILE_ID}"
            fi

            if [[ ! -v DEPLOY_OSDF_MANUALLY ]]; then
                LATEST_RELEASE_VERSION=`pivnet --format json releases -p hazelcast-pcf | jq .[0].version | sed 's/"//g'`
                LATEST_OSDF_FILE_ID=`pivnet --format json product-files -p ${PRODUCT_SLUG_NAME} -r ${LATEST_RELEASE_VERSION} | jq '.[] | select(.file_type=="Open Source License") | .id'`

                echo "Downloading latest OSDF file from PivNet..."
                if pivnet download-product-files -p ${PRODUCT_SLUG_NAME} -r ${LATEST_RELEASE_VERSION} -i ${LATEST_OSDF_FILE_ID}; then
	                echo "Latest OSDF file(${LATEST_RELEASE_VERSION} - ${LATEST_OSDF_FILE_ID}) downloaded succesfully."
                else
	                echo "Latest OSDF file(${LATEST_RELEASE_VERSION}) download failed!"
	                exit 1
                fi

                sed -i -e "s/${LATEST_RELEASE_VERSION}.txt/${RELEASE_VERSION}.txt/g" open_source_disclosures_Hazelcast_for_PCF-${LATEST_RELEASE_VERSION}.txt
                mv open_source_disclosures_Hazelcast_for_PCF-${LATEST_RELEASE_VERSION}.txt ./open_source_disclosures_Hazelcast_for_PCF-${RELEASE_VERSION}.txt

                echo "Uploading .pivotal file to PivNet's S3 bucket..."
                aws s3 cp ./open_source_disclosures_Hazelcast_for_PCF-${RELEASE_VERSION}.txt s3://$s3Bucket/partner-product-files/open_source_disclosures_Hazelcast_for_PCF-${RELEASE_VERSION}-test.txt --region $s3Region

                echo "Adding OSDF file to PivNet..."
                OSDF_PRODUCT_FILE_ID=`pivnet --format=json create-product-file --product-slug="hazelcast-pcf" --name="Open Source Disclosures Hazelcast for PCF ${RELEASE_VERSION}" --aws-object-key="partner-product-files/open_source_disclosures_Hazelcast_for_PCF-${RELEASE_VERSION}-test.txt" --file-type='Open Source License' --file-version=${RELEASE_VERSION} | jq '.product_file.id'`
                if [ -z "$OSDF_PRODUCT_FILE_ID" ]
                then
                    echo "Error adding product file"
                    exit 1
                else
                    echo "Added file open_source_disclosures_Hazelcast_for_PCF-${RELEASE_VERSION}.txt. Product file ID: ${OSDF_PRODUCT_FILE_ID}"
                fi
            fi
            #RELEASE_ID=`pivnet --format=json create-release -p ${PRODUCT_SLUG_NAME} -r ${RELEASE_VERSION} -t ${RELEASE_TYPE} -e ${EULA_SLUG_NAME} | jq -r '.id'`
        fi
    popd
popd

