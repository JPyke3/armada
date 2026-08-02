#!/bin/bash
set -euxo pipefail

KWIN_VERSION=6.7.3
KWIN_RELEASE=1.fc44
KWIN_SRPM="kwin-${KWIN_VERSION}-${KWIN_RELEASE}.src.rpm"
KWIN_SRPM_URL="https://kojipkgs.fedoraproject.org/packages/kwin/${KWIN_VERSION}/${KWIN_RELEASE}/src/${KWIN_SRPM}"
PATCH_NAME=kwin-input-panel-output.patch

work=/tmp/armada-kwin-build
topdir="${work}/rpmbuild"
rm -rf "${work}"
mkdir -p "${work}" "${topdir}"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}

dnf5 -y install --setopt=install_weak_deps=False \
    dnf5-plugins \
    patch \
    rpm-build

curl --retry 3 -fsSL -o "${work}/${KWIN_SRPM}" "${KWIN_SRPM_URL}"
rpm --define "_topdir ${topdir}" -ivh "${work}/${KWIN_SRPM}"

cp "/ctx/docs/${PATCH_NAME}" "${topdir}/SOURCES/"

spec="${topdir}/SPECS/kwin.spec"
grep -Fq "${PATCH_NAME}" "${spec}" || \
    sed -i "/^Source0:/a Patch1000: ${PATCH_NAME}" "${spec}"
sed -i 's/^Release:[[:space:]]*\(.*\)$/Release: \1.armada.1/' "${spec}"

dnf5 -y builddep "${spec}"
rpmbuild --define "_topdir ${topdir}" -ba --nocheck "${spec}"

dnf5 -y install --setopt=install_weak_deps=False \
    "${topdir}"/RPMS/aarch64/kwin-[0-9]*.rpm \
    "${topdir}"/RPMS/aarch64/kwin-common-[0-9]*.rpm \
    "${topdir}"/RPMS/aarch64/kwin-libs-[0-9]*.rpm

mapfile -t mesa_devel_packages < <(rpm -qa 'mesa-*-devel')
if ((${#mesa_devel_packages[@]})); then
    dnf5 -y remove "${mesa_devel_packages[@]}"
fi

rm -rf "${work}"
