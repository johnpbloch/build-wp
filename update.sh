#!/bin/bash

if [ -z ${GH_PW+x} ]; then
    echo -n "Github access token: "
    read -s GH_PW
fi
SVN_REPO="https://develop.svn.wordpress.org"
LIVE_BRANCHES=$(curl "$SVN_REPO/branches/" 2>/dev/null | sed -r 's/.+>([0-9]+(\.[0-9]+)+)\/<.+/\1/;tx;d;:x' | grep -Pv '^(1|2|3\.[0-6])' | sort -rV)
LIVE_TAGS=$(curl "$SVN_REPO/tags/" 2>/dev/null | sed -r 's/.+>([0-9]+(\.[0-9]+)+)\/<.+/\1/;tx;d;:x' | grep -Pv '^(1|2|3\.[0-6])' | sort -rV)

mkdir -p cached/branches
mkdir -p cached/tags

docker pull johnpbloch/build-wp:latest

latest_rev=$(svn info "$SVN_REPO/trunk/" | grep 'Last Changed Rev' | sed 's/Last Changed Rev: //')
update_trunk="y"
if [ -e "cached/trunk" ]; then
    local_rev=$(cat "cached/trunk")
    if [ "$local_rev" == "$latest_rev" ]; then
        echo "No changes to trunk, skipping"
        update_trunk="n"
    fi
fi
if [ "$update_trunk" == "y" ]; then
    echo "Processing trunk"
    docker run -e GITHUB_AUTH_USER="johnpbloch-bot" -e GITHUB_AUTH_PW="$GH_PW" --rm johnpbloch/build-wp:latest && \
    echo -n $latest_rev > "cached/trunk"
fi

for branch in $LIVE_BRANCHES; do
    latest_rev=$(svn info "$SVN_REPO/branches/$branch/" | grep 'Last Changed Rev' | sed 's/Last Changed Rev: //')
    if [ -e "cached/branches/$branch" ]; then
        local_rev=$(cat "cached/branches/$branch")
        if [ "$local_rev" == "$latest_rev" ]; then
            echo "No changes to branch $branch, skipping"
            continue
        fi
    fi
    echo "Processing branch $branch"
    docker run -e GITHUB_AUTH_USER="johnpbloch-bot" -e GITHUB_AUTH_PW="$GH_PW" --rm johnpbloch/build-wp:latest branch $branch && \
    echo -n $latest_rev > "cached/branches/$branch"
done

for tag in $LIVE_TAGS; do
    if [ -e "cached/tags/$tag" ]; then
        echo "No changes to tag $tag, skipping"
        continue
    fi
    echo "Processing tag $tag"
    docker run -e GITHUB_AUTH_USER="johnpbloch-bot" -e GITHUB_AUTH_PW="$GH_PW" --rm johnpbloch/build-wp:latest tag $tag && \
    echo -n $latest_rev > "cached/tags/$tag"
done
