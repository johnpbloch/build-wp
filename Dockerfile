FROM ubuntu:18.04

ENV VCS_AUTH_USER=""
ENV VCS_AUTH_PW=""

COPY files/ /tmp/files/

RUN apt-get update && \
    apt-get install --no-install-recommends -y git curl jq ca-certificates && \
    mv /tmp/files/run.sh /bin/run-wp-build && \
    mv /tmp/files/composer.json /var/composer.json && \
    rm -rf /tmp/files && \
    chmod +x /bin/run-wp-build && \
    rm -rf /var/lib/apt/lists/*

ENTRYPOINT ["/bin/run-wp-build"]
