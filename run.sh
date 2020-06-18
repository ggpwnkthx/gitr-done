#!/bin/sh

command_exists() {
	command -v "$@" > /dev/null 2>&1
}

check_environment() {
	# Get username
	user="$(id -un 2>/dev/null || true)"

	# If running from stdin, download to file and rerun self
	if [ "$0" = "-s" ]; then
		if [ "$user" = "root" ]; then
			cat >&2 <<-'EOF'
			"With great power comes great responsibility." 
				~ Uncle Ben

			Do NOT execute scripts from the Internet directly as the root user.
			Yes, this script will ask to become root so that it can install required packages, 
			but it's an increadibly bad habbit to raw dog the Internet as a super user.

			The requested script will be run by the calling user after the prerequisites are installed.
			The script will NOT be rub as root. This is by design.
EOF
			exit 1
		fi
		if [ -L gitr-done ]; then rm gitr-done; fi
		url=https://raw.githubusercontent.com/ggpwnkthx/gitr-done/master/run.sh
		if command_exists curl; then 
			curl -sSL -o gitr-done $url;
		elif command_exists wget; then 
			wget $url -O gitr-done
		fi
		chmod +x gitr-done
		./gitr-done $@
		exit
	fi

	SELF_LOCATE=$( cd ${0%/*} && pwd -P )/$(basename $0)

	lsb_dist=""
	# Every system that we officially support has /etc/os-release
	if [ -r /etc/os-release ]; then
		lsb_dist="$(. /etc/os-release && echo "$ID")"
	fi
	# Returning an empty string here should be alright since the
	# case statements don't act unless you provide an actual value
	
	# Check distribution
	lsb_dist="$(echo "$lsb_dist" | tr '[:upper:]' '[:lower:]')"
	# Determin if forked
	case "$lsb_dist" in
		"elementary os"|neon|linuxmint|ubuntu|kubuntu|manjaro|raspian)
			fork_of="debian"
		;;
		arch|centos|fedora)
			fork_of="rhel"
		;;
		*)
			fork_of=$lsb_dist
		;;
	esac

	# Check which package manager should be used
	pkgmgrs="apt apt-get yum dnf apk pacman zypper"
	for mgr in $pkgmgrs; do
		if command_exists $mgr; then pkgmgr=$mgr; fi
	done
}

run_privileged() {
	if [ "$user" != 'root' ]; then
		echo "Not running as a privileged user. Attempting to restart with authority..."
		run="$0 $user $@"
		sudo_exit=1
		if command_exists sudo && [ ! -z "$(groups $(whoami) | tr " " "\n" | grep '^sudo$')" ]; then
			(
				set -x
				sudo $run
				sudo_exit=$?
			)
			if [ $sudo_exit -gt 0 ]; then
				echo "Seems like 'sudo' didn't work for some reason, retrying elevation with 'su'."
			fi
		fi
		if command_exists su && [ $sudo_exit -gt 0 ]; then
			(
				set -x
				su -c "$run" root
			)
		fi
		if ! command_exists sudo && ! command_exists su; then
			cat >&2 <<-'EOF'
			Error: this installer needs the ability to run commands as root.
			We are unable to find "sudo" or "su" available to make this happen.
			EOF
			exit 1
		fi

		args=$(echo $@ | awk '{$1="";$2="";print $0}')
		dir=$(readlink $SELF_LOCATE)
		echo "#----------------------------------------#"
		echo "Prerequisites installed."
		echo "Executing $dir/$2 "
 		echo "	from the $1 repo"
		echo "	as $(whoami)"
		echo "#----------------------------------------#"
		# This is a fix for system that recently had sudo installed,
		# so that a new session is not required.
		(
			set -x
			sg sudo -c "cd $dir; ./$2 $args"
			rm $SELF_LOCATE
		)
		exit
	fi
}

add_pkgmgr_repos() {
	case "$pkgmgr" in
		apk)
			if [ -z "$(grep '^@edge ' /etc/apk/repositories)" ]; then
				(
					set -x
					echo @edge http://nl.alpinelinux.org/alpine/edge/main >> /etc/apk/repositories
				)
			fi
			if [ -z "$(grep '^@edgetesting ' /etc/apk/repositories)" ]; then
				(
					set -x
					echo @edgetesting http://nl.alpinelinux.org/alpine/edge/testing >> /etc/apk/repositories
				)
			fi
			if [ -z "$(grep '^@edgecommunity ' /etc/apk/repositories)" ]; then
				(
					set -x
					echo @edgecommunity http://nl.alpinelinux.org/alpine/edge/community >> /etc/apk/repositories
				)
			fi
		;;
		dnf|yum)
			(
				set -x
				$pkgmgr install -y epel-release >/dev/null
			)
	esac
}

install_prerequisites() {
	add_pkgmgr_repos
	# Run setup for each distro accordingly
	packages="sudo git curl jq fuse"
	case "$pkgmgr" in
		apk)
			packages="shadow@edgecommunity $packages"
		;;
		apt|apt-get)
			packages="apt-transport-https ca-certificates $packages"
		;;
		dnf|yum)
			packages="containerd.io $packages"
		;;
		pacman)
			packages="$packages"
		;;
		zypper)
			packages="$packages"
		;;
	esac
	do_install $packages
}

install_docker() {
	if ! command_exists docker; then
		echo "Installing docker using official script..."
		sh -c "$(curl -fsSL https://get.docker.com -o -)"
	fi
	if ! command_exists docker; then
		case "$pkgmgr" in
			apk)
				do_install docker@edgecommunity
				(
					set -x
					rc-update add docker
					service docker start
				)
			;;
			dnf)
				(
					set -x
					dnf install -y docker-ce --nobest
					systemctl enable --now docker
				)
			;;
		esac
	fi
}

do_install() {
	# Run setup for each distro accordingly
	case "$pkgmgr" in
		# Alpine
		apk)
			(
				set -x
				$pkgmgr update
			)
			for pkg in $@; do 
				(
					set -x
					$pkgmgr add $pkg >/dev/null
				)
			done
		;;
		# Debian
		apt|apt-get)
			if [ $(date +%s --date '-10 min') -gt $(stat -c %Y /var/cache/apt/) ]; then
				(
					set -x
					$pkgmgr update -qq >/dev/null
				)
			fi
			for pkg in $@; do 
				(
					set -x
					DEBIAN_FRONTEND=noninteractive $pkgmgr install -y $pkg >/dev/null
				)
			done
		;;
		# RHEL
		dnf|yum)
			for pkg in $@; do
				if ! $pkgmgr list installed $pkg; then
					(
						set -x
						$pkgmgr install -y $pkg >/dev/null
					)
				fi
			done
		;;
		# Arch
		pacman)
			for pkg in $@; do
				(
					set -x
					$pkgmgr -Sy $pkg >/dev/null
				)
			done
		;;
		# openSUSE
		zypper)
			for pkg in $@; do
				(
					set -x
					$pkgmgr --non-interactive --auto-agree-with-licenses install $pkg >/dev/null
				)
			done
		;;
		*)
			echo
			echo "ERROR: Unsupported distribution '$lsb_dist'"
			echo
			exit 1
		;;
	esac
}

sudo_me() {
	case "$fork_of" in
		alpine)
			(
				set -x
				addgroup -S sudo 2>/dev/null
				adduser $1 sudo
			)
		;;
		debian)
			(
				set -x
				addgroup --system sudo 2>/dev/null
				usermod -a -G sudo $1
			)
		;;
		rhel)
			(
				set -x
				groupadd -r sudo 2>/dev/null
				useradd -G sudo $1
				gpasswd -M $1 sudo
			)
		;;
	esac
	
	sed -i '/^# %sudo/s/^# //' /etc/sudoers
	if [ -z "$(grep '^%sudo ALL=(ALL) ALL' /etc/sudoers)" ]; then
		(
			set -x
			echo '%sudo ALL=(ALL) ALL' > /etc/sudoers
		)
	fi
}

gitr_done() {
	if [ ! -z "$2" ]; then
		mkdir -p /usr/src
		cd /usr/src
		repo=$(echo $2 | awk -F/ '{print $NF}' | awk -F. '{print $1}')
		(
			set -x
			git clone $2
			cd /usr/src/$repo
			git reset --hard HEAD
			git clean -f -d
			git pull
			chmod +x $3
			chown -R $1:$1 /usr/src/$repo
			rm $SELF_LOCATE
			ln -s /usr/src/$repo $SELF_LOCATE
		)
	fi
}

wrapper() {
	check_environment $@
	run_privileged $@
	install_prerequisites
	sudo_me $1
	install_docker
	gitr_done $@
}

# wrapped up in a function so that we have some protection against only getting half the file
wrapper $@