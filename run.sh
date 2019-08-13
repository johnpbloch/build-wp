#!/usr/bin/env bash

function build_trunk() {
  clean
  archive="https://github.com/WordPress/WordPress/archive/master.tar.gz"
  get_download $archive 1 || exit_on_error "Something went wrong downloading trunk" 3
  get_vcs master
  update_repo
  add_provide dev-master
  if nothing_to_commit ; then
    return 2
  fi
  commit_changes
  push_ref master
}

function build_branch() {
  branch=$1
  branch_archive="https://github.com/WordPress/WordPress/archive/${branch}-branch.tar.gz"
  archive_status=$(curl -ILs -o /dev/null -w "%{http_code}\n" $branch_archive)
  if [ "200" != $archive_status ]; then
    echo "Archive $branch does not exist yet!"
    return 1
  fi
  clean
  get_download $branch_archive 1 || exit_on_error "Something went wrong downloading $branch" 3
  get_vcs $branch
  update_repo
  add_provide "$branch.x-dev"
  if nothing_to_commit ; then
    return 2
  fi
  commit_changes
  push_ref $branch
  branch_status=$(curl -ILs -o /dev/null -w "%{http_code}\n" https://api.github.com/repos/johnpbloch/wordpress/branches/$branch)
  if [ "200" == $branch_status ]; then
    return 0
  fi
  get_meta_vcs
  pushd /tmp/wp-fork-meta > /dev/null 2>&1
  git checkout -b $branch
  cat composer.json | jq '.require."johnpbloch/wordpress-core" = "'$branch'.x-dev"' > temp && mv temp composer.json
  git add composer.json
  git commit -m "Add $branch branch"
  git push origin $branch
  popd > /dev/null 2>&1
}

function build_tag() {
  tag=$1
  short_tag=$(echo $tag | sed -E 's=^([0-9]+\.[0-9]+)\.0$=\1=')
  tag_archive="https://wordpress.org/wordpress-$short_tag.tar.gz"
  tag_status=$(curl -Is -o /dev/null -w "%{http_code}\n" $tag_archive)
  if [ "200" != $tag_status ]; then
    echo "Tag $tag does not have an archive yet!"
    return 1
  fi
  clean
  get_download $tag_archive || exit_on_error "Something went wrong downloading $tag" 3
  get_vcs clean
  update_repo
  add_provide $tag
  if nothing_to_commit ; then
    return 2
  fi
  commit_changes
  create_git_tag $tag
  push_ref $tag
  get_meta_vcs
  pushd /tmp/wp-fork-meta > /dev/null 2>&1
  git reset --hard origin/master
  cat composer.json | jq '.require."johnpbloch/wordpress-core" = "'$tag'"' > temp && mv temp composer.json
  git add composer.json
  git commit -m "Add $tag tag"
  git tag "$tag"
  git push origin $tag
  popd > /dev/null 2>&1
}

function checkenv() {
  if [ -z "$GITHUB_AUTH_USER" ]; then
    echo 'You must define the GITHUB_AUTH_USER environment variable!'
    exit 2
  elif [ -z "$GITHUB_AUTH_PW" ]; then
    echo 'You must define the GITHUB_AUTH_PW environment variable!'
    exit 2
  fi
}

exit_on_error(){
    echo "$1"
    if [ $# -gt 2 ]; then
        echo 'Output from command:'
        echo "$3"
    fi
    exit $2
}

function clean() {
  if [ -e ./wordpress.tar.gz ]; then
    rm -f ./wordpress.tar.gz
  fi
  if [ -e ./wordpress ]; then
    rm -rf ./wordpress
  fi
  if [ -e /tmp/wp ]; then
    rm -rf /tmp/wp
  fi
}

function get_download() {
  archive=$1
  curl -sSL $archive > ./wordpress.tar.gz
  if [ $# -eq 1 ]; then
    tar -xzf ./wordpress.tar.gz
  else
    mkdir ./wordpress
    tar -xzf wordpress.tar.gz --strip-components=1 -C wordpress/
  fi
  mkdir -p /tmp/wp
  mv ./wordpress /tmp/wp/build
}

function update_repo() {
  pushd /tmp/wp-fork > /dev/null 2>&1
  if [ -e 'index.php' ]; then
    rm -rf $(ls -1A | grep -vE '^\.git')
  fi
  find /tmp/wp/build -type f | xargs chmod 644
  find /tmp/wp/build -type d | xargs chmod 755
  shopt -s dotglob
  mv /tmp/wp/build/* .
  cp /var/composer.json .
  chmod 644 ./composer.json
  shopt -u dotglob
  popd > /dev/null 2>&1
}

function get_vcs() {
  if [ ! -d "/tmp/wp-fork" ]; then
    git clone "https://$GITHUB_AUTH_USER:$GITHUB_AUTH_PW@github.com/johnpbloch/wordpress-core.git" /tmp/wp-fork > /dev/null 2>&1
    git config --global user.email "johnpbloch+ghbot@gmail.com" > /dev/null 2>&1
    git config --global user.name "John P Bot" > /dev/null 2>&1
  fi
  pushd /tmp/wp-fork > /dev/null 2>&1
  branch=$1
  if [[ `git branch -a | grep -E "remotes/origin/$branch$"` ]]; then
    git checkout -b "$branch" "origin/$branch" > /dev/null 2>&1
  else
    git checkout 6ecbe57 > /dev/null 2>&1
    if [ "clean" != $branch ]; then
      git checkout -b $branch > /dev/null 2>&1
    fi
  fi
  popd > /dev/null 2>&1
}

function add_provide() {
  cat /tmp/wp-fork/composer.json | jq '.provide."wordpress/core-implementation" = "'$1'"' > /tmp/temp.json && \
    mv /tmp/temp.json /tmp/wp-fork/composer.json
}

function nothing_to_commit() {
  pushd /tmp/wp-fork > /dev/null 2>&1
  change_count=$(git status -s | wc -l)
  popd > /dev/null 2>&1
  if [ $change_count -ge  1 ]; then
    return 1
  fi
  return 0
}

function commit_changes() {
  pushd /tmp/wp-fork > /dev/null 2>&1
  git add -A . > /dev/null 2>&1
  git commit -m "Update from upstream" > /dev/null 2>&1
  popd > /dev/null 2>&1
}

function create_git_tag() {
  pushd /tmp/wp-fork > /dev/null 2>&1
  git tag $1 > /dev/null 2>&1
  popd > /dev/null 2>&1
}

function push_ref() {
  ref=$1
  pushd /tmp/wp-fork > /dev/null 2>&1
  git push origin $ref > /dev/null 2>&1
  popd > /dev/null 2>&1
}

function get_meta_vcs() {
  if [ ! -d "/tmp/wp-fork-meta" ]; then
    git clone "https://$GITHUB_AUTH_USER:$GITHUB_AUTH_PW@github.com/johnpbloch/wordpress.git" /tmp/wp-fork-meta > /dev/null 2>&1
  fi
}

function run(){
  checkenv
  # Grab all branches from upstream
  ALL_BRANCHES=$(git ls-remote --heads https://github.com/wordpress/wordpress.git | awk '{print $1","$2}')
  # Grab all tags from upstream
  UPSTREAM_TAGS=$(git ls-remote --tags https://github.com/wordpress/wordpress.git | awk '{print $2}' | sed 's=refs/tags/==')
  # Add trailing zeroes to x.x releases to be consistent with local tagging convention
  UPSTREAM_TAGS=$(echo $UPSTREAM_TAGS | sed -E 's=^([0-9]+\.[0-9]+)$=\1.0=')
  # Get rid of 5.0.5. See https://github.com/johnpbloch/wordpress/issues/41
  UPSTREAM_TAGS=$(echo $UPSTREAM_TAGS | grep -Pv '^5\.0\.5$');
  # Get all tags already in the local repo
  LOCAL_TAGS=$(git ls-remote --tags https://github.com/johnpbloch/wordpress-core.git | awk '{print $2}' | sed 's=refs/tags/==')
  # Compute all tags in upstream, but not in local
  TAGS_TO_BUILD=$(comm -23 <(echo $UPSTREAM_TAGS) <(echo $LOCAL_TAGS) )

  for ref in $ALL_BRANCHES ; do
    branch=$(echo $ref | cut -d, -f2 | sed 's=refs/heads/\(.*\)-branch=\1=')
    hash=$(echo $ref | cut -d, -f1)
    if [ "refs/heads/master" == $branch ] && [ hash != $(cat branches/master) ]; then
      build_trunk && (echo $hash > branches/master)
    elif [ $hash != $(cat branches/$branch) ]; then
      build_branch $branch && (echo $hash > branches/$branch)
    fi
  done

  for tag in $TAGS_TO_BUILD ; do
    build_tag $tag
  done
}

run
