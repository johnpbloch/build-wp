FROM alpine:3.3

RUN apk add --no-cache \
    git \
    subversion \
    bash \
    python \
    make \
    g++ \
    nodejs \
    php-cli

RUN npm set progress=false \
    && npm install -g grunt yarn phantomjs

RUN svn export --ignore-externals https://develop.svn.wordpress.org/trunk/ /var/wptrunk \
    && pushd /var/wptrunk \
    && yarn install  --ignore-optional --no-lockfile \
    && mv node_modules .. \
    && popd \
    && rm -rf /var/wptrunk

COPY build-wp.sh /bin/build-wp

RUN chmod +x /bin/build-wp

COPY files/composer.json /var/composer.json

ENV GITHUB_AUTH_USER=""
ENV GITHUB_AUTH_PW=""

ENTRYPOINT ["/bin/build-wp"]
