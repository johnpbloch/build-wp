FROM ubuntu:18.04

COPY run.sh /bin/run-wp-build

COPY files/composer.json /var/composer.json

RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y git curl jq && \
    chmod +x /bin/run-wp-build

ENV GITHUB_AUTH_USER=""
ENV GITHUB_AUTH_PW=""

ENTRYPOINT ["/bin/run-wp-build"]
