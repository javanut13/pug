#!/bin/bash

set -e
shopt -s nullglob

export PUG_DIR="$HOME/.pug"
export INSTALLERS_DIR="$PUG_DIR/installers"
export SOURCE_DIR="$PUG_DIR/source"
export PUG_VERSION=0.3.0

help_text=()

defhelp() {
  local command="${1?}"
  local text="${2?}"
  local help_str
  help_str="$(printf '   %-18s %s' "$command" "$text")"
  help_text+=("$help_str")
}

init() {
  mkdir -p "$PUG_DIR"
  mkdir -p "$INSTALLERS_DIR"
  mkdir -p "$SOURCE_DIR"
}

defhelp wipe 'Delete everything'
cmd.wipe() {
  echo -n 'Remove sources from pug? [y/n] '
  read -r confirm
  if [ "$confirm" = "y" ]; then
    local flags=-r
    if [ "$1" = '-f' ]; then
      flags=-rf
    fi
    rm "$flags" "$SOURCE_DIR"
    echo "Removed"
  fi
}

defhelp version 'Show the pug version'
cmd.version() {
  echo "Pug version $PUG_VERSION"
}

defhelp installers 'List available installers'
cmd.installers() {
  local type_name
  for installer in "$INSTALLERS_DIR/"*-install; do
    type_name="${installer##*/}"
    type_name="${type_name%-install}"
    echo "$1$type_name"
  done
}

defhelp help 'Show this help'
cmd.help() {
  echo 'Commands:'
  for str in "${help_text[@]}"; do
    echo "$str"
  done
  echo 'Installers:'
  cmd.installers '   '
}

# Update a module
clone_or_pull() {
  local url="$1"
  local name="$2"
  local source_dir="$3"

  if [ -d "$source_dir/$name/.git" ]; then
    git -C "$source_dir/$name" pull
  else
    git clone "$url" "$source_dir/$name"
  fi
}

# type name
run_installer() {
  if "$INSTALLERS_DIR/${1}-install" install "$2" \
    "$SOURCE_DIR/$type/${2}-pugfile"; then
    echo "Installed $2"
  else
    echo "Failed to install $2"
  fi
}

get_name_and_url() {
  case "$1" in
    github:)
      url="https://github.com/$2.git" ;;
    gitlab:)
      url="https://gitlab.com/$2.git" ;;
    *)
      url="$1"
      name="$2"
      if [ ! -z "$3" ]; then
        echo "Invalid url prefix: $*"
        exit 1
      fi
  esac
  if [ -z "$name" ]; then
    name="${url##*/}"
    name="${name%.git}"
  fi
}

defhelp get 'Clone a dependency'
cmd.get() {
  local type="${1?}"
  if [ -e "$INSTALLERS_DIR/${type}-install" ]; then
    local name
    local url
    get_name_and_url "$2" "$3" "$4"
    if clone_or_pull "$url" "$name" "$SOURCE_DIR/$type"; then
      run_installer "$type" "$name"
    else
      echo "Failed to install $name"
    fi
  else
    echo "Installer for $type doesn't exist"
    echo "Expected to find in $INSTALLERS_DIR/${type}-install"
    return 1
  fi
  cmd.rebuild
}

defhelp rebuild 'Recreate pugfile for type'
cmd.rebuild() {
  for folder in "$SOURCE_DIR/"*; do
    local found=false
    for _ in "$folder/"*-pugfile; do
      found=true
      break
    done
    if $found; then
      cat "$folder/"*-pugfile > "$folder/pug"
    else
      echo "No deps found, blanking $folder/pug"
      echo '' > "$folder/pug"
    fi
  done
}

defhelp remove 'Remove a dependency'
cmd.remove() {
  local dep="${1}"
  if [ -z "$dep" ]; then
    echo "Must provide dependency to remove"
    exit 1
  fi
  local flag=-r
  if [ "$2" = -f ]; then
    flag=-rf
  fi
  local found=false
  for folder in "$SOURCE_DIR/"*"/$dep"; do
    found=true
    echo "Removing: $folder"
    if ! rm "$flag" "$folder"; then
      echo "Could not remove $folder"
      return 1
    fi
    if ! rm "$flag" "${folder}-pugfile"; then
      echo "Could not remove ${folder}-pugfile"
    fi
  done
  cmd.rebuild
}

defhelp update 'Pull all plugins and re-write pugfiles'
cmd.update() {
  for pugfile in "$SOURCE_DIR"/*/pug; do
    echo -n '' > "$pugfile"
  done
  local count=0
  for module in "$SOURCE_DIR"/*/*; do
    if [ -d "$module" ]; then
      local name="${module##*/}"
      echo "Updating $name"
      git -C "$module" pull
      local type
      type="$(dirname "$module")"
      type="${type##*/}"
      run_installer "$type" "$name"
      (( count+=1 ))
      echo
      echo '-------------------------------------'
      echo
    fi
  done
  cmd.rebuild
  echo "$count modules updated"
}

defhelp list 'List installed modules'
cmd.list() {
  local count=0
  for module in "$SOURCE_DIR"/*/*; do
    if [ -d "$module" ]; then
      echo "${module##*/}"
      (( count+=1 ))
    fi
  done
  echo "$count modules installed"
}

defhelp upgrade 'Upgrade pug and installers'
cmd.upgrade() {
  echo 'Upgrading Pug...'
  dest="$(mktemp -d)"
  git clone 'https://github.com/willhbr/pug.git' "$dest"
  cd "$dest"
  if [ "$1" != -l ]; then
    echo 'Password may be required to copy pug to /usr/local/bin/pug'
    if ! sudo cp src/pug.sh /usr/local/bin/pug; then
      echo 'Could not copy to /usr/local/bin (Did sudo work?)'
      echo 'To use pug copy this file into your PATH as "pug":'
      realpath src/pug.sh
    fi
  fi

  echo 'Copying installers to ~/.pug/installers'
  mkdir -p ~/.pug/installers
  cp src/installers/* ~/.pug/installers
}

installer_type() {
  local type_name
  type_name="${1##*/}"
  type_name="${type_name%-install}"
  echo "$type_name"
}

cmd="$1"
if shift && type "cmd.$cmd" > /dev/null 2>&1; then
  init
  "cmd.$cmd" "$@"
else
  echo "Unknown command $cmd"
  cmd.help
fi
