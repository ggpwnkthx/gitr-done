#!/bin/sh
command_exists() {
	command -v "$@" > /dev/null 2>&1
}

check_environment() {
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

set_sh_c() {
	sh_c='sh -c'
	if [ "$user" != 'root' ]; then
		if command_exists sudo; then
			sh_c='sudo -E sh -c'
		elif command_exists su; then
			sh_c='su -c'
		else
			cat >&2 <<-'EOF'
			Error: this installer needs the ability to run commands as root.
			We are unable to find either "sudo" or "su" available to make this happen.
			EOF
			exit 1
		fi
	fi
}

install_prerequisites() {
	# Run setup for each distro accordingly
	packages="sudo git"
	case "$pkgmgr" in
		apt|apt-get)
			packages="apt-transport-https ca-certificates $packages"
			;;
		dnf|yum)
			packages="epel-release $packages"
			;;
	esac
	do_install $packages
	install_snapd
}

install_snapd() {
	if ! command_exists snap; then
		case "$lsb_dist" in
			arch)
				$sh_c "git clone https://aur.archlinux.org/snapd.git && cd snapd && makepkg -si"
				$sh_c "systemctl enable --now snapd.socket"
				$sh_c "ln -s /var/lib/snapd/snap /snap"
				;;
			centos|fedora)
				do_install snapd
				$sh_c "systemctl enable --now snapd.socket"
				$sh_c "ln -s /var/lib/snapd/snap /snap"
				;;
			opensuse)
				$sh_c "zypper addrepo --refresh https://download.opensuse.org/repositories/system:/snappy/openSUSE_Leap_15.0 snappy"
				$sh_c "zypper --gpg-auto-import-keys refresh"
				$sh_d "zypper dup --from snappy"
				do_install snapd
				$sh_c "systemctl enable snapd"
				$sh_c "systemctl start snapd"
				$sh_c "systemctl enable snapd.apparmor"
				$sh_c "systemctl start snapd.apparmor"
				;;
			*)
				do_install snapd
				;;
		esac
	fi
}

do_install() {
	# Run setup for each distro accordingly
	case "$pkgmgr" in
		apk)
			$sh_c "$pkgmgr update"
			for pkg in $@; do 
				if ! $pkgmgr search -v $pkg; then
					$sh_c "$pkgmgr add $pkg"; 
				fi
			done
			;;
		apt|apt-get)
			if [ $(date +%s --date '-10 min') -gt $(stat -c %Y /var/cache/apt/) ]; then
				$sh_c "$pkgmgr update -qq"
			fi
			for pkg in $@; do 
				$sh_c "DEBIAN_FRONTEND=noninteractive $pkgmgr install -y $pkg"
			done
			;;
		dnf|yum)
			for pkg in $@; do
				if ! $pkgmgr list installed $pkg; then
					$sh_c "$pkgmgr install -y $pkg"
					if $pkg -eq epel-release; then
						$sh_c "$pkgmgr update"
					fi
				fi
			done
			;;
		pacman)
			for pkg in $@; do
				$sh_c "$pkgmgr -Sy $pkg"
			done
			;;
		zypper)
			for pkg in $@; do
				$sh_c "$pkgmgr --non-interactive --auto-agree-with-licenses install $pkg"
			done
			;;
		snap)
			for pkg in $@; do
				$sh_c "$pkgmgr install $pkg"
			done

		*)
			echo
			echo "ERROR: Unsupported distribution '$lsb_dist'"
			echo
			exit 1
			;;
	esac
}

sudo_me() {
	if [ "$user" != 'root' ]; then
		case "$fork_of" in
			alpine)
				$sh_c "addgroup -S sudo 2>/dev/null"
				$sh_c "sed -i '/^# %sudo/s/^# //' /etc/sudoers"
				$sh_c "adduser $user sudo"
				;;
			debian)
				$sh_c "addgroup --system sudo 2>/dev/null"
				$sh_c "sed -i '/^# %sudo/s/^# //' /etc/sudoers"
				$sh_c "usermod -a -G sudo $user"
				;;
			rhel)
				$sh_c "groupadd -r sudo 2>/dev/null"
				$sh_c "echo '%sudo ALL=(ALL) ALL' > /etc/sudoers"
				$sh_c "useradd -G sudo $user"
				;;
		esac
	fi
}

gitr_done() {
	if [ -n "$1" ]; then
		sudo mkdir -p /usr/src
		cd /usr/src
		repo=$(sudo git clone $1 2>&1 | awk -F "'" '{print $2}')
		sudo chown -R $(whoami):$(whoami) /usr/src/$repo
		chmod +x /usr/src/$repo/$2
		args=$(echo $@ | awk '{$1="";$2="";print $0}')
		/usr/src/$repo/$2 $args
	fi
}

wrapper() {
	check_environment
	set_sh_c
	install_prerequisites
	sudo_me
	gitr_done $@
}

# wrapped up in a function so that we have some protection against only getting
# half the file during "curl | sh"
wrapper $@