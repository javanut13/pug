#!/bin/bash

set -e
shopt -s nullglob

export PUG_DIR="$HOME/.pug"
export INSTALLERS_DIR="$PUG_DIR/installers"
export SOURCE_DIR="$PUG_DIR/source"

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
  read confirm
  if [ "$confirm" = "y" ]; then
    local flags=-r
    if [ "$1" = '-f' ]; then
      flags=-rf
    fi
    rm "$flags" "$SOURCE_DIR"
    echo "Removed"
  fi
}


defhelp help 'Show this help'
cmd.help() {
  for str in "${help_text[@]}"; do
    echo "$str"
  done
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

defhelp get 'Clone a dependency'
cmd.get() {
  local type="${1?}"
  if [ -e "$INSTALLERS_DIR/${type}-install.sh" ]; then
    local url="$2"
    local name="$3"
    if [ -z "$name" ]; then
      name="${url##*/}"
      name="${name%.git}"
    fi
    if clone_or_pull "$url" "$name" "$SOURCE_DIR/$type"; then
      "$INSTALLERS_DIR/${type}-install.sh" "$name"
    else
      echo "Failed to install $name"
    fi
  else
    echo "Installer for $type doesn't exist"
    echo "Expected to find in $INSTALLERS_DIR/${type}-install.sh"
    return 1
  fi
}

defhelp remove 'Remove a dependency'
cmd.remove() {
  echo "Not implemented"
  exit 1
}

defhelp update 'Pull all plugins'
cmd.update() {
  for pugfile in "$SOURCE_DIR"/*/pug; do
    echo '' > "$pugfile"
  done
  local count=0
  for module in "$SOURCE_DIR"/*/*; do
    if [ -d "$module" ]; then
      echo '-------------------------------------'
      local name="${module##*/}"
      echo "Updating $name"
      git -C "$module" pull
      local type
      type="$(dirname "$module")"
      type="${type##*/}"
      "$INSTALLERS_DIR/${type}-install" "$name"
      (( count+=1 ))
    fi
  done
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
  cd /tmp
  git clone 'https://github.com/javanut13/pug.git'
  cd pug
  echo "Installing pug"
  if [ "$1" != -l ]; then
    echo 'Password may be required to copy pug to /usr/local/bin/pug'
    if ! sudo cp src/pug.sh /usr/local/bin/pug; then
      echo 'Could not copy to /usr/local/bin (Did sudo work?)'
      echo 'To use pug copy this file into your PATH as "pug":'
      echo "$(realpath src/pug.sh)"
    fi
  fi

  echo 'Copying installers to ~/.pug/installers'
  mkdir -p ~/.pug/installers
  cp src/installers/* ~/.pug/installers
}

dependency() {
  local installer="$1"
  local url
  case "$2" in
    from:)
      url="$3" ;;
    github:)
      url="https://github.com/$3.git" ;;
    gitlab:)
      url="https://gitlab.com/$3.git" ;;
    *)
      echo "Unknown arg $2"
      return 1 ;;
  esac
  cmd.get "$installer" "$url"
}

defhelp load 'Used for loading config files'
cmd.load() {
  local file="$1"
  if [ ! -f "$file" ]; then
    echo "$file does not exist or is not a file"
    return 1
  fi

  local type_name
  for installer in "$INSTALLERS_DIR/"*-install; do
    type_name="${installer##*/}"
    type_name="${type_name%-install}"
    eval "function ${type_name} { dependency '$type_name' \"\$@\"; }"
  done

  source "$file"
}

cmd="$1"
if shift && type "cmd.$cmd" > /dev/null 2>&1; then
  init
  "cmd.$cmd" "$@"
else
  echo "Unknown command $cmd"
  cmd.help
fi
