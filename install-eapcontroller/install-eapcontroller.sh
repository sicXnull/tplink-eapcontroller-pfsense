#!/bin/sh

# install-eap.sh
# Installs the EAP Controller software on a FreeBSD machine (presumably running pfSense).

# The latest version of EAPController:
EAP_SOFTWARE_FOLDER="Omada_Controller_v3.2.10_linux_x64"
EAP_SOFTWARE_URL="https://static.tp-link.com/2020/202004/20200420/"${EAP_SOFTWARE_FOLDER}".tar.gz"



# The rc script associated with this branch or fork:
#RC_SCRIPT_URL="https://raw.githubusercontent.com/gozoinks/unifi-pfsense/master/rc.d/unifi.sh"


# If pkg-ng is not yet installed, bootstrap it:
if ! /usr/sbin/pkg -N 2> /dev/null; then
  echo "FreeBSD pkgng not installed. Installing..."
  env ASSUME_ALWAYS_YES=YES /usr/sbin/pkg bootstrap
  echo " done."
fi

# If installation failed, exit:
if ! /usr/sbin/pkg -N 2> /dev/null; then
  echo "ERROR: pkgng installation failed. Exiting."
  exit 1
fi

# Determine this installation's Application Binary Interface
ABI=`/usr/sbin/pkg config abi`

# FreeBSD package source:
FREEBSD_PACKAGE_URL="https://pkg.freebsd.org/${ABI}/latest/All/"

# FreeBSD package list:
FREEBSD_PACKAGE_LIST_URL="https://pkg.freebsd.org/${ABI}/latest/packagesite.txz"

# Stop the controller if it's already running...
# First let's try the rc script if it exists:
if [ -f /usr/local/etc/rc.d/eapcontroller.sh ]; then
  echo -n "Stopping the EAP Controller service..."
  /usr/sbin/service eapcontroller.sh stop
  echo " done."
fi

# Then to be doubly sure, let's make sure ace.jar isn't running for some other reason:
if [ $(ps ax | grep -c "/opt/tplink/EAPController/lib/com.tp-link.eap.start-0.0.1-SNAPSHOT.jar start") -ne 0 ]; then
  echo -n "Killing ace.jar process..."
  /bin/kill -15 `ps ax | grep "/opt/tplink/EAPController/lib/com.tp-link.eap.start-0.0.1-SNAPSHOT.jar start" | awk '{ print $1 }'`
  echo " done."
fi

# And then make sure mongodb doesn't have the db file open:
if [ $(ps ax | grep -c "/opt/tplink/EAPController/data/[d]b") -ne 0 ]; then
  echo -n "Killing mongod process..."
  /bin/kill -15 `ps ax | grep "/opt/tplink/EAPController/data/[d]b" | awk '{ print $1 }'`
  echo " done."
fi

# If an installation exists, we'll need to back up configuration:
if [ -d /opt/tplink/EAPController/data ]; then
  echo "Backing up EAP Controller data..."
  BACKUPFILE=/var/backups/eap-`date +"%Y%m%d_%H%M%S"`.tgz
  /usr/bin/tar -vczf ${BACKUPFILE} /opt/tplink/EAPController/data
fi

# Add the fstab entries apparently required for OpenJDKse:
if [ $(grep -c fdesc /etc/fstab) -eq 0 ]; then
  echo -n "Adding fdesc filesystem to /etc/fstab..."
  echo -e "fdesc\t\t\t/dev/fd\t\tfdescfs\trw\t\t0\t0" >> /etc/fstab
  echo " done."
fi

if [ $(grep -c proc /etc/fstab) -eq 0 ]; then
  echo -n "Adding procfs filesystem to /etc/fstab..."
  echo -e "proc\t\t\t/proc\t\tprocfs\trw\t\t0\t0" >> /etc/fstab
  echo " done."
fi

# Run mount to mount the two new filesystems:
echo -n "Mounting new filesystems..."
/sbin/mount -a
echo " done."

# Install mongodb, OpenJDK, and unzip (required to unpack Ubiquiti's download):
# -F skips a package if it's already installed, without throwing an error.
echo "Installing required packages..."
tar xv -C / -f /usr/local/share/pfSense/base.txz ./usr/bin/install
#uncomment below for pfSense 2.2.x:
#env ASSUME_ALWAYS_YES=YES /usr/sbin/pkg install mongodb openjdk unzip pcre v8 snappy

fetch ${FREEBSD_PACKAGE_LIST_URL}
tar vfx packagesite.txz

AddPkg () {
	pkgname=$1
	pkginfo=`grep "\"name\":\"$pkgname\"" packagesite.yaml`
	pkgvers=`echo $pkginfo | pcregrep -o1 '"version":"(.*?)"' | head -1`
	env ASSUME_ALWAYS_YES=YES /usr/sbin/pkg add -f ${FREEBSD_PACKAGE_URL}${pkgname}-${pkgvers}.txz
}

AddPkg snappy
AddPkg python2
AddPkg v8
AddPkg mongodb
#AddPkg unzip
AddPkg pcre
#AddPkg alsa-lib
#AddPkg freetype2
#AddPkg fontconfig
#AddPkg xproto
#AddPkg kbproto
#AddPkg libXdmcp
#ddPkg libpthread-stubs
#AddPkg libXau
#AddPkg libxcb
#AddPkg libICE
#AddPkg libSM
AddPkg java-zoneinfo
#AddPkg fixesproto
#AddPkg xextproto
#AddPkg inputproto
#AddPkg libX11
#AddPkg libXfixes
#AddPkg libXext
#AddPkg libXi
#AddPkg libXt
#AddPkg libfontenc
#AddPkg mkfontscale
#AddPkg mkfontdir
AddPkg dejavu
#AddPkg recordproto
#AddPkg libXtst
#AddPkg renderproto
#AddPkg libXrender
AddPkg javavmwrapper
#AddPkg giflib
AddPkg openjdk8
AddPkg snappyjava

# Clean up downloaded package manifest:
rm packagesite.*

echo " done."

# Switch to a temp directory for the EAP Controller download:
cd `mktemp -d -t tplink`

# Download EAP Controller from TP-Link:
echo -n "Downloading the EAP Controller software..."
/usr/bin/fetch ${EAP_SOFTWARE_URL}
echo " done."

# Unpack the archive into the /usr/local directory:
# (the -o option overwrites the existing files without complaining)
echo -n "Installing EAP Controller in /opt/tplink/EAPController..."
mkdir /tmp/eapc
tar -xvzC /tmp/eapc -f ${EAP_SOFTWARE_FOLDER}.tar.gz
mkdir /opt
mkdir /opt/tplink
mv /tmp/eapc/${EAP_SOFTWARE_FOLDER}  /opt/tplink/EAPController
echo " done."

# Update EAP's symbolic link for mongod to point to the version we just installed:
echo -n "Updating mongod link..."
/bin/ln -sf /usr/local/bin/mongod /opt/tplink/EAPController/bin/mongod
echo " done."

# Update EAP's symbolic link for Java to point to the version we just installed:
echo -n "Updating Java link..."
/bin/ln -sf ${JAVA_HOME} /opt/tplink/EAPController/jre
echo " done."

return

# If partition size is < 4GB, add smallfiles option to mongodb
#echo -n "Checking partition size..."
#if [ `df -k | awk '$NF=="/"{print $2}'` -le 4194302 ]; then
#	echo -e "\nunifi.db.extraargs=--smallfiles\n" >> /opt/tplink/EAPController/data/system.properties
#fi
#echo " done."

# Replace snappy java library to support AP adoption with latest firmware:
#echo -n "Updating snappy java..."
#eapzipcontents=`zipinfo -1 UniFi.unix.zip`
#upstreamsnappyjavapattern='/(snappy-java-[^/]+\.jar)$'
# Make sure exactly one match is found
#if [ $(echo "${eapzipcontents}" | egrep -c ${upstreamsnappyjavapattern}) -eq 1 ]; then
#  upstreamsnappyjava="/opt/tplink/EAPController/lib/`echo \"${eapzipcontents}\" | pcregrep -o1 ${upstreamsnappyjavapattern}`"
#  mv "${upstreamsnappyjava}" "${upstreamsnappyjava}.backup"
#  cp /usr/local/share/java/classes/snappy-java.jar "${upstreamsnappyjava}"
#  echo " done."
#else
#  echo "ERROR: Could not locate UniFi's snappy java! AP adoption will most likely fail"
#fi

# Fetch the rc script from github:
echo -n "Installing rc script..."
#/usr/bin/fetch -o /usr/local/etc/rc.d/eapcontroller.sh ${RC_SCRIPT_URL}
echo " done."

# Fix permissions so it'll run
chmod +x /usr/local/etc/rc.d/eapcontroller.sh

# Add the startup variable to rc.conf.local.
# Eventually, this step will need to be folded into pfSense, which manages the main rc.conf.
# In the following comparison, we expect the 'or' operator to short-circuit, to make sure the file exists and avoid grep throwing an error.
if [ ! -f /etc/rc.conf.local ] || [ $(grep -c eapcontroller_enable /etc/rc.conf.local) -eq 0 ]; then
  echo -n "Enabling the EAP Controller service..."
  echo "eapcontroller_enable=YES" >> /etc/rc.conf.local
  echo " done."
fi

# Restore the backup:
if [ ! -z "${BACKUPFILE}" ] && [ -f ${BACKUPFILE} ]; then
  echo "Restoring EAP Controller data..."
  mv /opt/tplink/EAPController/data /opt/tplink/EAPController/data-`date +%Y%m%d-%H%M`
  /usr/bin/tar -vxzf ${BACKUPFILE} -C /
fi

# Start it up:
echo -n "Starting the EAP Controller service..."
/usr/sbin/service eapcontroller.sh start
echo " done."
