#!/bin/sh

if [ $# -lt 1 ]; then
	echo "You must provide a tag!"
	exit 1
fi

tag=$1
alias="latest"

docker build -t "johnpbloch/build-wp:$tag" .

docker tag "johnpbloch/build-wp:$tag" "johnpbloch/build-wp:$alias"

docker push johnpbloch/build-wp

