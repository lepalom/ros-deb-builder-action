#!/bin/sh
# SPDX-License-Identifier: BSD-3-Clause

set -ex

vcs export src --exact-with-tags > /home/runner/apt_repo/sources.repos

cd /home/runner/apt_repo

REPOSITORY="$(printf "%s" "$GITHUB_REPOSITORY" | tr / _)"
REPOSITORY_NAME=`echo "$GITHUB_REPOSITORY" | sed "s/$GITHUB_REPOSITORY_OWNER\///g"`

echo '#$REPOSITORY_NAME' > README.md
echo '' >> README.md
echo 'If you have gitpages activated' >> README.md
echo '```bash' >> README.md
echo "echo \"deb [trusted=yes arch=amd64] https://lepalom.github.io/$REPOSITORY_NAME $DEB_DISTRO  main | sudo tee /etc/apt/sources.list.d/$REPOSITORY.list" >> README.md
echo '```' >> README.md
echo 'if not' >> README.md
echo '```bash' >> README.md
echo "echo \"deb [trusted=yes] https://raw.githubusercontent.com/$GITHUB_REPOSITORY/$DEB_DISTRO-$ROS_DISTRO/ ./\" | sudo tee /etc/apt/sources.list.d/$REPOSITORY.list" >> README.md
echo '```' >> README.md
echo 'also, add the yaml contents' >> README.md
echo '```bash' >> README.md
echo "echo \"yaml https://raw.githubusercontent.com/$GITHUB_REPOSITORY/$DEB_DISTRO-$ROS_DISTRO/local.yaml $ROS_DISTRO\" | sudo tee /etc/ros/rosdep/sources.list.d/1-$REPOSITORY.list" >> README.md
echo '```' >> README.md
echo '' >> README.md
echo '##Packages in the repository' >> README.md
for PKG_PATH in $(ls -d1 pool/main/r/*); do
   PKG=`echo $PKG_PATH | sed "s/pool\/main\/r\///g"`
   echo "[$PKG]($PKG_PATH)" >> README.md
done
