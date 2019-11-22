#!/usr/bin/env bash
set -e -u -o pipefail

declare -r SCRIPT_NAME=$(basename "$0")
declare -r SCRIPT_DIR=$(cd $(dirname "$0") && pwd)

log() {
    local level=$1; shift
    echo -e "$level: $@"
}


err() {
    log "ERROR" "$@" >&2
}

info() {
    log "INFO" "$@"
}

die() {
    local code=$1; shift
    local msg="$@"; shift
    err $msg
    exit $code
}

usage() {
  local msg="$1"
  cat <<-EOF
Error: $msg

USAGE:
    $SCRIPT_NAME CATALOG_VERSION DEST_DIR VERSION

Example:
  $SCRIPT_NAME release-v0.7 deploy/resources/v0.7.0 0.7.0
EOF
  exit 1
}

#declare -r CATALOG_VERSION="release-v0.7"

declare -r TEKTON_CATALOG="https://raw.githubusercontent.com/openshift/tektoncd-catalog"
declare -r TEKTON_CATALOG_TASKS=(
  s2i
  openshift-client
  buildah
)

declare -r OPENSHIFT_CATALOG="https://raw.githubusercontent.com/openshift/pipelines-catalog"
declare -r OPENSHIFT_CATALOG_TASKS=(
  s2i-go
  s2i-java-8
  s2i-java-11
  s2i-python-3
  s2i-nodejs
)


download_task() {
  local task_path="$1"; shift
  local task_url="$1"; shift

  info "downloading ... $t from $task_url"
  # validate url
  curl --output /dev/null --silent --head --fail "$task_url" || return 1


  cat <<-EOF > "$task_path"
# auto generated by script/update-tasks.sh
# DO NOT EDIT: use the script instead
# source: $task_url
#
---
$(curl -sLf "$task_url" | sed -e 's|^kind: Task|kind: ClusterTask|g' )
EOF


}

get_tasks() {
  local dest_dir="$1"; shift
  local version="${1//./-}"; shift

  local catalog="$1"; shift
  local catalog_version="$1"; shift

  # NOTE: receives array by its name
  local catalog_tasks_ref="$1[@]"; shift
  local tasks=("${!catalog_tasks_ref}")



  info "Downloading tasks from catalog $catalog to $dest_dir directory"
  for t in ${tasks[@]} ; do
    # task filenames do not follow a naming convention,
    # some are taskname.yaml while others are taskname-task.yaml
    # so, try both before failing
    local task_url="$catalog/$catalog_version/$t/${t}-task.yaml"
    local task_alt_url="$catalog/$catalog_version/$t/${t}.yaml"

    mkdir -p "$dest_dir/$t/"
    local task_path="$dest_dir/$t/$t-task.yaml"

    download_task  "$task_path" "$task_url"  ||
      download_task "$task_path" "$task_alt_url"  ||
      die 1 "Failed to download $t"

    create_version "$task_path" "$t" "$version"  ||
      die 1  "failed to convert $t to $t-$version"
  done
}


create_version() {
  local task_path="$1"; shift
  local task="$1"; shift
  local version="$1"; shift
  local task_version_path="$(dirname $task_path)/$task-$version-task.yaml"

  sed -e "s|^\(\s\+name:\)\s\+\($task\)|\1 \2-$version|g"  $task_path  > "$task_version_path"
}



main() {


  local catalog_version=${1:-''}
  [[ -z "$catalog_version"  ]] && usage "missing catalog_version"
  shift

  local dest_dir=${1:-''}
  [[ -z "$dest_dir"  ]] && usage "missing destination directory"
  shift

  local version=${1:-''}
  [[ -z "$version"  ]] && usage "missing task_version"
  shift

  mkdir -p "$dest_dir" || die 1 "failed to create ${dest_dir}"

  dest_dir="$dest_dir/02-clustertasks"
  mkdir -p "$dest_dir" || die 1 "failed to create catalog dir ${catalog_dir}"

  #create_version s2i "$dest_dir" "$version"  \
    #"$TEKTON_CATALOG"   "$catalog_version"  TEKTON_CATALOG_TASKS

  get_tasks "$dest_dir" "$version"  \
    "$TEKTON_CATALOG"   "$catalog_version"  TEKTON_CATALOG_TASKS
  get_tasks "$dest_dir" "$version"  \
    "$OPENSHIFT_CATALOG"   "$catalog_version"  OPENSHIFT_CATALOG_TASKS

  return $?
}

main "$@"
