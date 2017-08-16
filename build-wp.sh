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
        master)
            type="master"
            branch="master"
            ref="trunk"
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

exit_on_error(){
    echo "$1"
    if [ $# -gt 2 ]; then
        echo 'Output from command:'
        echo "$3"
    fi
    exit $2
}

echo "Grabbing WordPress source for $ref"
revision=$(svn info "https://develop.svn.wordpress.org/$ref/" | grep 'Last Changed Rev' | sed 's/Last Changed Rev: //')
if [ "tag" == $type ]; then
    tag_archive="https://wordpress.org/wordpress-$2.tar.gz"
    tag_status=$(curl -Is -o /dev/null -w "%{http_code}\n" $tag_archive);
    if [ "200" != $tag_status ]; then
        exit_on_error "Tag $2 does not have an archive yet!" 5
    fi
    curl -sSL $tag_archive > /tmp/wordpress.tar.gz
    pushd /tmp
    tar -xzf wordpress.tar.gz
    mkdir -p wp/build
    mv wordpress/* wp/build/
else
    svn export --ignore-externals "https://develop.svn.wordpress.org/$ref/" /tmp/wp/ > /dev/null 2>&1

    pushd /tmp/wp/

    if [ -e "Gruntfile.js" ]; then
        echo "Installing npm dependencies..."
        sed -i -e 's/97c43554ff7a86e2ff414d34e66725b05118bf10/936144c11fdee00427c3ce3cb0f87ee5770149b7/' package.json
        sed -i -e 's/~/^/g' package.json
        cat package.json | jq '.devDependencies."grunt-sass" = if .devDependencies."grunt-sass" | test("\\^0\\.\\d+\\.\\d+") then "^1.0.0" else .devDependencies."grunt-sass" end' > package.nn.json && mv package.nn.json package.json
        cat package.json | jq '.devDependencies."grunt-contrib-imagemin" = if .devDependencies."grunt-contrib-imagemin" | test("\\^0\\.\\d+\\.\\d+") then "^1.0.0" else .devDependencies."grunt-contrib-imagemin" end' > package.nn.json && mv package.nn.json package.json
        output="$(npm update --dev 2>&1)" || exit_on_error 'NPM install failed' 3 "$output"
        echo 'Running grunt...'
        output="$(grunt)" || exit_on_error 'Grunt failed' 3 "$output"
    else
        mkdir build
        mv $(ls -A | grep -vE '^build$') build
    fi
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
chmod 644 ./composer.json

unset tag
unset provide
case $type in
    tag)
        tag="$2"
        if [[ `echo -n "$tag" | grep -E '^\s*\d+\.\d+\s*$'` ]]; then
            tag="$tag.0"
        fi
        provide="$tag"
        ;;
    master)
        tag=$(php -r 'include "wp-includes/version.php"; echo "$wp_version\n";')
        if [[ `echo "$tag" | grep -E "\-\d{8}\.\d{6}$"` ]]; then
            newversion="${tag:0: -15}$revision"
            sed -i -e "s/$tag/$newversion/" wp-includes/version.php
            unset tag
        elif [[ `git tag | grep -F "$tag"` ]]; then
            unset tag
        fi
        provide="dev-master"
        ;;
    branch)
        provide="$branch.x-dev"
        ;;
esac

if [ -n $provide ]; then
    cat composer.json | jq '.provide."wordpress/core-implementation" = "'$provide'"' > temp && mv temp composer.json
fi

echo "Committing changes..."
git add -A . > /dev/null 2>&1

git commit -m "Update from $ref

SVN r$revision" > /dev/null 2>&1

if [ -n $tag ]; then
    git tag "$tag"
fi

if [ "tag" == "$type" ]; then
    git rm composer.json > /dev/null 2>&1
    git commit -m "Hide tag branch from packagist" > /dev/null 2>&1
fi

if [ $tag ]; then
    echo "Pushing tag $tag"
fi
echo "Pushing $branch to origin"
output="$(git push --tags origin $branch 2>&1)" || exit_on_error 'Git push failed' 4 "$output"

case $type in
    tag)
        echo "Tagging $tag in the meta repo"
        git clone "https://$GITHUB_AUTH_USER:$GITHUB_AUTH_PW@github.com/johnpbloch/wordpress.git" /tmp/wp-git-meta > /dev/null 2>&1
        cd /tmp/wp-git-meta
        tag_branch="${tag%.*}"
        exists=$(curl -sS https://api.github.com/repos/johnpbloch/wordpress/branches | jq -r 'map(select(.name == "'$tag_branch'")) | .[0]?.name')
        git checkout -b $tag_branch
        if [ "$exists" == "$tag_branch" ]; then
            git fetch
            git reset --hard origin/$tag_branch
        fi
        cat composer.json | jq '.require."johnpbloch/wordpress-core" = "'$tag'"' > temp && mv temp composer.json
        git add composer.json
        git commit -m "Add $tag tag"
		git tag "$tag"
        cat composer.json | jq '.require."johnpbloch/wordpress-core" = "'$tag_branch'.x-dev"' > temp && mv temp composer.json
        git add composer.json
        git commit -m "Reset $tag_branch branch"
        git push --tags origin $tag_branch
        ;;
    branch)
        exists=$(curl -sS https://api.github.com/repos/johnpbloch/wordpress/branches | jq -r 'map(select(.name == "'$branch'")) | .[0]?.name')
        if [ "$exists" != "$branch" ]; then
            echo "Adding $branch branch to the meta repo"
            cd /tmp
            git clone "https://$GITHUB_AUTH_USER:$GITHUB_AUTH_PW@github.com/johnpbloch/wordpress.git" /tmp/wp-git-meta > /dev/null 2>&1
            cd wp-git-meta
            git checkout -b $branch
            cat composer.json | jq '.require."johnpbloch/wordpress-core" = "'$branch'.x-dev"' > temp && mv temp composer.json
            git add composer.json
            git commit -m "Add $branch branch"
            git push origin $branch
        fi
        ;;
esac
