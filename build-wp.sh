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
    if [ "branch" == $type ]; then
        archive="https://github.com/WordPress/WordPress/archive/${branch}-branch.tar.gz"
    else
        archive="https://github.com/WordPress/WordPress/archive/master.tar.gz"
    fi
    archive_status=$(curl -ILs -o /dev/null -w "%{http_code}\n" $archive)
    if [ "200" != $archive_status ]; then
        exit_on_error "Archive $2 does not exist yet!" 5
    fi
    curl -sSL $archive > /tmp/wordpress.tar.gz
    pushd /tmp
    mkdir -p wordpress
    tar -xzf wordpress.tar.gz --strip-components=1 -C wordpress/
    mkdir -p wp/build
    mv wordpress/* wp/build/
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
        provide="dev-master"
        ;;
    branch)
        provide="$branch.x-dev"
        ;;
esac

if [ -n $provide ]; then
    cat composer.json | jq '.provide."wordpress/core-implementation" = "'$provide'"' > temp && mv temp composer.json
fi

if [ $(git status -s | wc -l) -lt 1 ]; then
    exit_on_error "No changes to be committed." 9
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

ensure_branch_on_meta_repo(){
    repo="johnpbloch/wordpress"
    tmpbranch=${1}
    branch_status=$(curl -ILs -o /dev/null -w "%{http_code}\n" https://api.github.com/repos/$repo/branches/$tmpbranch)
    if [ "404" == $branch_status ]; then
        echo "Adding $tmpbranch branch to the meta repo"
        if [ -d /tmp/wp-git-meta ]; then
            cd /tmp/wp-git-meta
            git checkout master
            git reset --hard origin/master
        else
            cd /tmp
            git clone "https://$GITHUB_AUTH_USER:$GITHUB_AUTH_PW@github.com/$repo.git" /tmp/wp-git-meta > /dev/null 2>&1
            cd wp-git-meta
        fi
        git checkout -b $tmpbranch
        cat composer.json | jq '.require."johnpbloch/wordpress-core" = "'$tmpbranch'.x-dev"' > temp && mv temp composer.json
        git add composer.json
        git commit -m "Add $tmpbranch branch"
        git push origin $tmpbranch
    fi
}

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
        ensure_branch_on_meta_repo $branch
        ;;
esac
