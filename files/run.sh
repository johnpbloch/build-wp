#!/usr/bin/env bash

##############################################################
# Build Trunk                                                #
##############################################################
function build_trunk() {
  clean
  archive="https://github.com/WordPress/WordPress/archive/master.tar.gz"
  get_download $archive 1 || exit_on_error "Something went wrong downloading trunk" 3
  get_vcs master
  update_repo
  add_provide dev-master
  set_php_requirement /tmp/wp-fork '5.6.20'
  if nothing_to_commit ; then
    return 2
  fi
  commit_changes
  push_ref master
}

##############################################################
# Build Branch                                               #
# Takes 1 argument: branch name                              #
##############################################################
function build_branch() {
  branch=$1
  branch_archive="https://github.com/WordPress/WordPress/archive/${branch}-branch.tar.gz"
  archive_status=$(curl -ILs -o /dev/null -w "%{http_code}\n" $branch_archive)
  if [ "200" != "$archive_status" ]; then
    echo "Archive $branch does not exist yet!"
    return 1
  fi
  clean
  get_download $branch_archive 1 || exit_on_error "Something went wrong downloading $branch" 3
  get_vcs $branch
  update_repo
  add_provide "$branch.x-dev"
  if is_version_greater_than $branch '5.1.999999'; then
    set_php_requirement /tmp/wp-fork '5.6.20'
  fi
  if nothing_to_commit ; then
    return 2
  fi
  commit_changes
  push_ref $branch
  branch_status=$(curl -ILs -o /dev/null -w "%{http_code}\n" https://api.github.com/repos/johnpbloch/wordpress/branches/$branch)
  if [ "200" == "$branch_status" ]; then
    return 0
  fi
  get_meta_vcs
  pushd /tmp/wp-fork-meta > /dev/null 2>&1
  git checkout -b $branch
  cat composer.json | jq '.require."johnpbloch/wordpress-core" = "'$branch'.x-dev"' > temp && mv temp composer.json
  if is_version_greater_than $branch '5.1.999999'; then
    set_php_requirement /tmp/wp-fork-meta '5.6.20'
  fi
  git add composer.json
  git commit -m "Add $branch branch"
  git push origin $branch
  popd > /dev/null 2>&1
}

##############################################################
# Build Tag                                                  #
# Takes one argument: tag name                               #
#                                                            #
# Tag name is normalized to always include 3 version         #
# numbers. By default, WordPress does not include .0 at the  #
# end of the first tagged release in a major version's       #
# lifecycle. This function expects those tags to have the .0 #
# added to the end of the tag before invocation.             #
##############################################################
function build_tag() {
  tag=$1
  short_tag=$(echo $tag | sed -E 's=^([0-9]+\.[0-9]+)\.0$=\1=')
  tag_archive="https://wordpress.org/wordpress-$short_tag.tar.gz"
  tag_status=$(curl -Is -o /dev/null -w "%{http_code}\n" $tag_archive)
  if [ "200" != "$tag_status" ]; then
    echo "Tag $tag does not have an archive yet!"
    return 1
  fi
  clean
  get_download $tag_archive || exit_on_error "Something went wrong downloading $tag" 3
  get_vcs clean
  update_repo
  add_provide $tag
  if is_version_greater_than $tag '5.1.999999'; then
    set_php_requirement /tmp/wp-fork '5.6.20'
  elif is_version_greater_than '5.2' $tag; then
    set_php_requirement /tmp/wp-fork '5.3.2'
  fi
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
  if is_version_greater_than $tag '5.1.999999'; then
    set_php_requirement /tmp/wp-fork '5.6.20'
  elif is_version_greater_than '5.2' $tag; then
    set_php_requirement /tmp/wp-fork '5.3.2'
  fi
  git add composer.json
  git commit -m "Add $tag tag"
  git tag "$tag"
  git push origin $tag
  popd > /dev/null 2>&1
}

##############################################################
# Check Environment                                          #
# Makes sure we have the necessary environment variables set #
# to push these changes up to the remote.                    #
##############################################################
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

##############################################################
# Clean up the filesystem before attempting to build         #
##############################################################
function clean() {
  if [ -e './wordpress.tar.gz' ]; then
    rm -f ./wordpress.tar.gz
  fi
  if [ -e './wordpress' ]; then
    rm -rf ./wordpress
  fi
  if [ -e '/tmp/wp' ]; then
    rm -rf /tmp/wp
  fi
}

##############################################################
# Download WordPress and extract it                          #
# This takes 1 to 2 arguments:                               #
#   - The archive URL                                        #
#   - An optional flag to identify this archive as coming    #
#     from github (and therefore needing special handling    #
# The mere presence of a second argument will trigger the    #
# github handling. If an archive is flagged as a github file #
# it will be extracted with strip-components set to one to   #
# make sure the file is extracted into the correct location. #
##############################################################
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

##############################################################
# Update the Local repo with the latest code from upstream   #
##############################################################
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

##############################################################
# Ensure the local vcs repo is in the correct state          #
# This takes one argument: the branch to switch to           #
# If the branch is "clean", rather than a branch, it will    #
# check out commit 6ecbe57 in a detached head state and stay #
# there.                                                     #
##############################################################
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
    if [ "clean" != "$branch" ]; then
      git checkout -b $branch > /dev/null 2>&1
    fi
  fi
  popd > /dev/null 2>&1
}

##############################################################
# Add a "provide" section to the composer.json file          #
# This takes 1 argument: the version constraint provided     #
##############################################################
function add_provide() {
  cat /tmp/wp-fork/composer.json | jq '.provide."wordpress/core-implementation" = "'$1'"' > /tmp/temp.json && \
    mv /tmp/temp.json /tmp/wp-fork/composer.json
}

##############################################################
# Check if one version is greater than another               #
##############################################################
function is_version_greater_than() {
  test "$(printf '%s\n' "$@" | sort -V | head -n 1)" != "$1"
}

##############################################################
# Set the minimum php version in a composer.json file        #
# This function expects 2 arguments:                         #
#   - The directory in which to find composer.json           #
#   - The minimum php version to use                         #
##############################################################
function set_php_requirement() {
  dir=$1
  ver=$2
  cat $dir/composer.json | jq '.require.php = ">='$ver'"' > /tmp/temp.json && \
    mv /tmp/temp.json $dir/composer.json
}

##############################################################
# Check if the working tree is clean for the local repo      #
##############################################################
function nothing_to_commit() {
  pushd /tmp/wp-fork > /dev/null 2>&1
  change_count=$(git status -s | wc -l)
  popd > /dev/null 2>&1
  if [ "$change_count" -ge  1 ]; then
    return 1
  fi
  return 0
}

##############################################################
# Commit the changes currently in the local repo             #
##############################################################
function commit_changes() {
  pushd /tmp/wp-fork > /dev/null 2>&1
  git add -A . > /dev/null 2>&1
  git commit -m "Update from upstream" > /dev/null 2>&1
  popd > /dev/null 2>&1
}

##############################################################
# Create a git tag                                           #
##############################################################
function create_git_tag() {
  pushd /tmp/wp-fork > /dev/null 2>&1
  git tag $1 > /dev/null 2>&1
  popd > /dev/null 2>&1
}

##############################################################
# Push a ref to origin                                       #
# This takes 1 argument: the refspec to push                 #
# The refspec could be either a branch or a tag              #
##############################################################
function push_ref() {
  ref=$1
  pushd /tmp/wp-fork > /dev/null 2>&1
  git push origin $ref > /dev/null 2>&1
  popd > /dev/null 2>&1
}

##############################################################
# Ensure the meta repository exists                          #
##############################################################
function get_meta_vcs() {
  if [ ! -d "/tmp/wp-fork-meta" ]; then
    git clone "https://$GITHUB_AUTH_USER:$GITHUB_AUTH_PW@github.com/johnpbloch/wordpress.git" /tmp/wp-fork-meta > /dev/null 2>&1
  fi
}

##############################################################
# Run the update process                                     #
#                                                            #
# Before updating the fork repos, this checks out the build  #
# repo to track changes necessary. Hashes are stored for     #
# branches and if the hash hasn't changed, there's really no #
# reason to update it.                                       #
#                                                            #
# First, this loops through the branches and builds them     #
# accordingly. Next, it computes the tags that exist in the  #
# upstream repository but not in the local repo and adds     #
# the missing tags.                                          #
##############################################################
function run(){
  checkenv
  git clone "https://$GITHUB_AUTH_USER:$GITHUB_AUTH_PW@github.com/johnpbloch/wordpress.git" /tmp/wp-build > /dev/null 2>&1
  cd /tmp/wp-build
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
    cd /tmp/wp-build
    branch=$(echo $ref | cut -d, -f2 | sed 's=refs/heads/\(.*\)-branch=\1=')
    hash=$(echo $ref | cut -d, -f1)
    if [ "refs/heads/master" == "$branch" ] && [ "$hash" != "$(cat branches/master)" ]; then
      echo "Building trunk..."
      build_trunk && (echo $hash > branches/master)
    elif [ "$hash" != "$(cat branches/$branch)" ]; then
      echo "Building branch $branch..."
      build_branch $branch && (echo $hash > branches/$branch)
    fi
  done

  for tag in $TAGS_TO_BUILD ; do
    cd /tmp/wp-build
    echo "Building release $tag..."
    build_tag $tag
  done

  cd /tmp/wp-build
  git add branches && git commit -m "Update hashes" && git push
}

run
