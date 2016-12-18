FROM alpine:3.4

RUN apk add --no-cache \
    git \
    subversion \
    bash \
    python \
    make \
    g++ \
    nodejs

RUN npm install -g grunt

CMD ["sh"]
