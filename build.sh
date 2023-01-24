#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause

set -ex

if debian-distro-info --all | grep -q "$DEB_DISTRO"; then
  DISTRIBUTION=debian
elif ubuntu-distro-info --all | grep -q "$DEB_DISTRO"; then
  DISTRIBUTION=ubuntu
else
  echo "Unknown DEB_DISTRO: $DEB_DISTRO"
  exit 1
fi

case $ROS_DISTRO in
  debian)
    ;;
  boxturtle|cturtle|diamondback|electric|fuerte|groovy|hydro|indigo|jade|kinetic|lunar)
    echo "Unsupported ROS 1 version: $ROS_DISTRO"
    exit 1
    ;;
  melodic|noetic)
    BLOOM=ros
    ROS_DEB="$ROS_DISTRO-"
    curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key -o /home/runner/ros-archive-keyring.gpg
    set -- --extra-repository="deb http://packages.ros.org/ros/ubuntu $DEB_DISTRO main" --extra-repository-key=/home/runner/ros-archive-keyring.gpg "$@"
    ;;
  *)
    # assume ROS 2 so we don't have to list versions
    BLOOM=ros
    ROS_DEB="$ROS_DISTRO-"
    curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key -o /home/runner/ros-archive-keyring.gpg
    set -- --extra-repository="deb http://packages.ros.org/ros2/ubuntu $DEB_DISTRO main" --extra-repository-key=/home/runner/ros-archive-keyring.gpg "$@"
    ;;
esac

# make output directory
mkdir /home/runner/build_repo

echo "Add unreleased packages to rosdep"

for PKG in $(catkin_topological_order --only-names); do
  printf "%s:\n  %s:\n  - %s\n" "$PKG" "$DISTRIBUTION" "ros-$ROS_DEB$(printf '%s' "$PKG" | tr '_' '-')" >> /home/runner/build_repo/local.yaml
done
echo "yaml file:///home/runner/build_repo/local.yaml $ROS_DISTRO" | sudo tee /etc/ros/rosdep/sources.list.d/1-local.list
printf "%s" "$ROSDEP_SOURCE" | sudo tee /etc/ros/rosdep/sources.list.d/2-remote.list

rosdep update

echo "Run sbuild"

# Don't build tests
export DEB_BUILD_OPTIONS=nocheck

TOTAL="$(catkin_topological_order --only-names | wc -l)"
COUNT=1

# TODO: use colcon list -tp in future
for PKG_PATH in $(catkin_topological_order --only-folders); do
  echo "::group::Building $COUNT/$TOTAL: $PKG_PATH"
  test -f "$PKG_PATH/CATKIN_IGNORE" && echo "Skipped" && continue
  test -f "$PKG_PATH/COLCON_IGNORE" && echo "Skipped" && continue
  (
  cd "$PKG_PATH"

  bloom-generate "${BLOOM}debian" --os-name="$DISTRIBUTION" --os-version="$DEB_DISTRO" --ros-distro="$ROS_DISTRO"

  # Set the version
  sed -i "1 s/([^)]*)/($(git describe --tag || echo 0)-$(date +%Y%m%d~r4d+%H.%M))/" debian/changelog
  
  # Get the PKG_NAME
  PKG_NAME="`cat debian/changelog | head -n1 | sed -e 's/\s.*$//'`"
  PKG_VERSION="`head -n1 debian/changelog | awk -F'[()]' '{print $2}'`"
  PACKAGE=$PKG_NAME'_'$PKG_VERSION
  UPSTREAM_NAME=`cat debian/changelog | head -n1 | sed -e 's/\s.*$//'| sed -e 's/^ros-//' | sed -e 's/-/_/'`
  UPSTREAM_VERSION="`git describe --tags`"
  PACKAGE_ORIG_VERSION=$PKG_NAME'_'$UPSTREAM_VERSION
  
  # https://github.com/ros-infrastructure/bloom/pull/643
  echo 11 > debian/compat
  
  # Generate orig.tar.bz2
  tar cvfj ../$PACKAGE_ORIG_VERSION.orig.tar.bz2 --exclude .git --exclude debian ../$UPSTREAM_NAME
  
  # dpkg-source-opts: no need for upstream.tar.gz
  sbuild --chroot-mode=unshare --no-clean-source --no-run-lintian \
    --dpkg-source-opts="-Zgzip -z1 --format=1.0 -sn" --build-dir=/home/runner/build_repo \
    --extra-package=/home/runner/build_repo "$@"
   
  # pushing to the repo
  cd ..
  reprepro --basedir /home/runner/apt_repo -C main include $DEB_DISTRO $PACKAGE.changes
  cd "$PKG_PATH"
  )
  COUNT=$((COUNT+1))
  echo "::endgroup::"
done

ccache -sv
