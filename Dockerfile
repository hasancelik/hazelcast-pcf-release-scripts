FROM cfplatformeng/tile-generator:v12.0.9

RUN apk add --update \
    gcc \
    musl-dev \
    python-dev \
    curl
RUN pip install --upgrade ruamel.yaml==0.15.85 PyGithub==1.43.4 awscli==1.15.5

RUN wget -O /tmp/pivnet-linux-amd64-0.0.55 https://github.com/pivotal-cf/pivnet-cli/releases/download/v0.0.55/pivnet-linux-amd64-0.0.55
RUN mv /tmp/pivnet-linux-amd64-0.0.55 /usr/local/bin/pivnet
RUN chmod 755 /usr/local/bin/pivnet

RUN rm -rf /var/cache/apk/*

RUN addgroup -g 1031 jenkins
RUN adduser -D -h /home/jenkins -s /bin/bash -u 1030 -G jenkins jenkins