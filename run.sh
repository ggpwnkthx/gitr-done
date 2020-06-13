#!/bin/sh

command_exists() {
	command -v "$@" > /dev/null 2>&1
}

check_environment() {
	# If running from stdin, download to file and rerun self
	if [ "$0" = "-s" ]; then
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

	# Get username
	user="$(id -un 2>/dev/null || true)"

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
		if command_exists su; then
			su -c "$0 $user $@"
		elif command_exists sudo; then
			sudo -E $0 $user $@
		else
			cat >&2 <<-'EOF'
			Error: this installer needs the ability to run commands as root.
			We are unable to find "su" available to make this happen.
			EOF
			exit 1
		fi
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
			if [ -z "$(grep '^@edgetesting ' /etc/apk/repositories)" ]; then
				(
					set -x
					echo @edgetesting http://nl.alpinelinux.org/alpine/edge/community >> /etc/apk/repositories
				)
			fi
		;;
	esac
}

install_prerequisites() {
	add_pkgmgr_repos
	# Run setup for each distro accordingly
	packages="sudo git curl jq fuse"
	case "$pkgmgr" in
		apk)
			packages="$packages"
		;;
		apt|apt-get)
			packages="apt-transport-https ca-certificates $packages"
		;;
		dnf|yum)
			packages="epel-release $packages"
		;;
		pacman)
			packages="$packages"
		;;
		zypper)
			packages="$packages"
		;;
	esac
	do_install $packages
	install_docker
}

install_docker() {
	if ! command_exists docker; then
		curl -fsSL https://get.docker.com -o - | sh - >/dev/null
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
					if $pkg -eq epel-release; then
						(
							set -x
							$pkgmgr update >/dev/null
						)
					fi
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
		repo=$(sudo git clone $2 2>&1 | awk -F "'" '{print $2}')
		chown -R $1:$1 /usr/src/$repo
		args=$(echo $@ | awk '{$1="";$2="";$3="";print $0}')
		(
			set -x
			cd /usr/src/$repo
			su $1 -c "git reset --hard HEAD"
			su $1 -c "git clean -f -d"
			su $1 -c "git pull"
			chmod +x $3
			su $1 -c "./$3 $args"
		)
	fi
}

wrapper() {
	check_environment
	run_privileged $@
	echo $0 $@
	exit
	install_prerequisites
	sudo_me $1
	gitr_done $@
}

# wrapped up in a function so that we have some protection against only getting half the file
echo $@
wrapper $@