#!/bin/bash

if [ -z "$GITHUB_AUTH_USER" ]; then
    echo 'You must define the GITHUB_AUTH_USER environment variable!'
    exit 2
elif [ -z "$GITHUB_AUTH_PW" ]; then
    echo 'You must define the GITHUB_AUTH_PW environment variable!'
    exit 2
fi

if [ $# -lt 2 ]; then
    type="master"
    branch="master"
    ref="trunk"
else
    case "$1" in
        branch)
            type="branch"
            branch="$2"
            ref="branches/$2"
            ;;
        tag)
            type="tag"
            branch="tag-$2"
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

echo "Grabbing WordPress source for $ref"
revision=$(svn info "https://develop.svn.wordpress.org/$ref/" | grep 'Last Changed Rev' | sed 's/Last Changed Rev: //')
svn export --ignore-externals "https://develop.svn.wordpress.org/$ref/" /tmp/wp/ > /dev/null 2>&1

pushd /tmp/wp/

if [ -e "Gruntfile.js" ]; then
    echo "Installing npm dependencies..."
    mv /var/node_modules /tmp/wp/node_modules
    sed -i -e 's/97c43554ff7a86e2ff414d34e66725b05118bf10/936144c11fdee00427c3ce3cb0f87ee5770149b7/' package.json
    npm install > /dev/null 2>&1 && \
        grunt

    if [ $? -ne 0 ]; then
        echo "Error installing npm or running grunt!"
        exit 3
    fi
else
    mkdir build
    mv $(ls -A | grep -vE '^build$') build
fi

echo "Cloning git repository..."
git clone "https://$GITHUB_AUTH_USER:$GITHUB_AUTH_PW@github.com/johnpbloch/wordpress-core.git" /tmp/wp-git > /dev/null 2>&1

pushd /tmp/wp-git

if [[ `git branch -a | grep -E "remotes/origin/$branch$"` ]]; then
    git checkout -b "$branch" "origin/$branch" > /dev/null 2>&1
else
    git checkout clean > /dev/null 2>&1
    git checkout -b $branch > /dev/null 2>&1
fi

if [ -e 'index.php' ]; then
    rm -r $(ls -1A | grep -vE '^\.git')
fi

git config --global user.email "johnpbloch+ghbot@gmail.com" > /dev/null 2>&1
git config --global user.name "John P Bot" > /dev/null 2>&1

mv /tmp/wp/build/* .

cp /var/composer.json .

echo "Committing changes"
git add -A . > /dev/null 2>&1

git commit -m "Update from $ref

SVN r$revision" > /dev/null 2>&1

case $type in
    tag)
        tag="$2"
        if [[ `echo -n "$tag" | grep -E '^\s*\d+\.\d+\s*$'` ]]; then
            tag="$tag.0"
        fi
        git tag "$tag"
        git rm composer.json > /dev/null 2>&1
        git commit -m "Hide tag branch from packagist" > /dev/null 2>&1
        ;;
    master)
        tag=$(php -r 'include "wp-includes/version.php"; echo "$wp_version\n";')
        if [[ `echo "$tag" | grep -vE "\-\d{8}\.\d{6}$"` ]]; then
            if [[ ! `git tag | grep -F "$tag"` ]]; then
                git tag "$tag"
            fi
        fi
        ;;
esac

if [ ${tag+x} ]; then
    echo "Pushing tag $tag"
fi
echo "Pushing $branch to origin"
git push --tags origin "$branch" > /dev/null 2>&1
