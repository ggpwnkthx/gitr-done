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
	
	lsb_dist="$(echo "$lsb_dist" | tr '[:upper:]' '[:lower:]')"
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
	case "$lsb_dist" in
		ubuntu|debian|raspbian)
			do_install apt-transport-https ca-certificates sudo git
			;;
		*)
			do_install sudo git
			;;
	esac
}

do_install() {
	# Run setup for each distro accordingly
	case "$lsb_dist" in
		ubuntu|debian|raspbian)
			if [ $(date +%s --date '-10 min') -gt $(stat -c %Y /var/cache/apt/) ]; then
				$sh_c "apt-get update -qq"
			fi
			for pkg in $@; do 
				if ! apt -qq list $pkg; then
					$sh_c "DEBIAN_FRONTEND=noninteractive apt-get install -y $pkg"
				fi
			done
			;;
		centos|fedora)
			if command_exists dnf; then
				for pkg in $@; do
					if ! dnf list installed $pkg; then
						$sh_c "dnf install -y $pkg"
					fi
				done
			else
				for pkg in $@; do
					if ! yum list installed $pkg; then
						$sh_c "yum install -y $pkg"
					fi
				done
			fi
			
			;;
		alpine)
			$sh_c "apk update"
			for pkg in $@; do 
				if ! apk search -v $pkg; then
					$sh_c "apk add $pkg"; 
				fi
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
	if [ "$user" != 'root' ]; then
		case "$lsb_dist" in
			ubuntu|debian|raspbian)
				$sh_c "addgroup --system sudo"
				$sh_c "sed -i '/^# %sudo/s/^# //' /etc/sudoers"
				$sh_c "usermod -a -G sudo $user"
				;;
			centos|fedora)
				$sh_c "groupadd -r sudo"
				$sh_c "echo '%sudo ALL=(ALL) ALL' > /etc/sudoers"
				$sh_c "useradd -G sudo $user"
				;;
			alpine)
				$sh_c "addgroup -S sudo"
				$sh_c "sed -i '/^# %sudo/s/^# //' /etc/sudoers"
				$sh_c "adduser $user sudo"
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