#! /bin/bash
echo "Converting buildroot into a bare sdk for downloading"
cd /opt/hachdev/sdk/r1702/buildroot
rm -rf fs arch board boot configs dl docs linux package support system toolchain utils
rm *
cd /opt/hachdev/sdk/r1702/buildroot/output
rm -rf build images staging target
echo "Conversion to sdk is complete"


