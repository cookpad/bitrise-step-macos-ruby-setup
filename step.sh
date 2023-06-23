#!/usr/bin/env bash
set -e

if ! which asdf &> /dev/null; then
  echo "asdf is required" >&2
  exit 1
fi

if [ -f ".ruby-version" ]; then
  version_wanted=$(cat .ruby-version)
else
  echo "The Ruby version to use should be specified with a .ruby-version file" >&2
  echo "in the current directory." >&2
  exit 1
fi

# We want asdf to look at `.ruby-version` files.
echo "legacy_version_file = yes" > "$HOME/.asdfrc"

asdf_root="$HOME/.asdf"
asdf_ruby_installs="$asdf_root/installs/ruby"

latest_matching_version_installed() {
  asdf list ruby "$1" | sed 's/^ *\**//' | grep "^[0-9.]\+$" | sort -rV | head -1
}

latest_matching_version_installable() {
  asdf list all ruby "$1" | grep "^[0-9.]\+$" | sort -rV | head -1
}

update_ruby_build() {
  brew update
  brew outdated ruby-build || brew upgrade ruby-build
}

matching_version=""

# Latest matching version of Ruby available.
if [ "$require_latest" = "1" ] || [ "$require_latest" = "true" ] || [ "$require_latest" = "yes" ]; then
  # We were asked for the latest so first update ruby-build to be sure the list is up-to-date.
  update_ruby_build
  matching_version=$(latest_matching_version_installable "$version_wanted")
  if [ -z "$matching_version" ]; then
    echo "Could not find what Ruby version matching \"$version_wanted\" to install" >&2
    exit 1
  fi

# Do we really need to do something?
elif ! ruby -v &> /dev/null; then
  matching_version=$(latest_matching_version_installed "$version_wanted")
  if [ -z "$matching_version" ]; then
    matching_version=$(latest_matching_version_installable "$version_wanted")
    if [ -z "$matching_version" ]; then
      # The version wanted might require a more recent version of ruby-build.
      update_ruby_build
      matching_version=$(latest_matching_version_installable "$version_wanted")
      if [ -z "$matching_version" ]; then
        echo "Could not find what Ruby version matching \"$version_wanted\" to install" >&2
        exit 1
      fi
    fi
  fi
fi

if [ -n "$matching_version" ]; then
  echo "Using Ruby $matching_version"
  asdf install ruby "$matching_version"
  if [ "$version_wanted" != "$matching_version" ]; then
    ln -snf "$matching_version" "$asdf_ruby_installs/$version_wanted"
    asdf reshim ruby "$version_wanted"
  fi
else
  echo "Using Ruby $version_wanted"
fi

# Make sure everything worked.
ruby -v > /dev/null

pushd "$asdf_ruby_installs/$version_wanted" > /dev/null
# `pwd -P` resolves symbolic links.
ruby_path=$(pwd -P)
popd > /dev/null

# Make sure the version of Bundler used by the project is installed.
if [ -f Gemfile.lock ]; then
  bundler_version_used=$(grep -A1 "^BUNDLED WITH" Gemfile.lock | tail -1 | sed -e "s/^[[:space:]]*//g")
  gem install --conservative --no-doc --version "$bundler_version_used" bundler
fi

# Even if we use a version of Ruby from the VM image, we want to keep the Gems
# installed, and we do not want a script too complicated, so cache the whole
# Ruby installation.
if [ -z "$BITRISE_CACHE_INCLUDE_PATHS" ]; then
  BITRISE_CACHE_INCLUDE_PATHS="$ruby_path"
else
  # It's a mess how "\n" is handled differently in scripts and on the command
  # line, so use a real new line in the string.
  BITRISE_CACHE_INCLUDE_PATHS="$BITRISE_CACHE_INCLUDE_PATHS
$ruby_path"
fi

if [ -f Gemfile ]; then
  bundle check || bundle install
fi

envman add --key "BITRISE_CACHE_INCLUDE_PATHS" --value "$BITRISE_CACHE_INCLUDE_PATHS"
