#!/bin/bash

if [ $# -lt 2 ]; then
    type="master"
    ref="trunk"
else
    case "$1" in
        branch)
            type="branch"
            ref="branches/$2"
            ;;
        tag)
            type="tag"
            ref="tags/$2"
            ;;
        *)
            echo "Invalid type"
            exit 1
            ;;
    esac
fi

if [ -d /tmp/wp ]; then
    rm -rf /tmp/wp
fi

svn export --ignore-externals "https://develop.svn.wordpress.org/$ref/" /tmp/wp/

cd /tmp/wp/

npm install
