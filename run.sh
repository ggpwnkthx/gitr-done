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
			packages="apt-transport-https ca-certificates sudo git"
            ;;
        *)
            packages="sudo git"
            ;;
	esac
    do_install $packages
}

do_install() {
    # Run setup for each distro accordingly
	case "$lsb_dist" in
        ubuntu|debian|raspbian)
			(
				$sh_c "apt-get update -qq"
				$sh_c "DEBIAN_FRONTEND=noninteractive apt-get install -y -qq $@"
			)
            ;;
        centos|fedora)
            if [ "$lsb_dist" = "fedora" ]; then
				pkg_manager="dnf"
				config_manager="dnf config-manager"
				enable_channel_flag="--set-enabled"
				disable_channel_flag="--set-disabled"
				pkg_suffix="fc$dist_version"
			else
				pkg_manager="yum"
				config_manager="yum-config-manager"
				enable_channel_flag="--enable"
				disable_channel_flag="--disable"
				pkg_suffix="el"
			fi
			(
				$sh_c "$pkg_manager install -y -q $@"
			)
            ;;
        alpine)
			(
				$sh_c "apk update"
				$sh_c "apk add $@"
			)
            ;;
        *)
			echo
			echo "ERROR: Unsupported distribution '$lsb_dist'"
			echo
			exit 1
			;;
	esac
}

gitr_done() {
    if [ -n "$1" ]; then
        tmp_dir=$(mktemp -d)
        git clone $1 $tmp_dir
        chmod +x $tmp_dir/$2
        args=$(echo $@ | awk '{$1="";$2="";print $0}')
        $tmp_dir/$2 $args
    fi
}

sudo_me() {
    if [ "$user" != 'root' ]; then
        case "$lsb_dist" in
            ubuntu|debian|raspbian)
                (
                    $sh_c "addgroup -S sudo"
                    $sh_c "sed -i '/^# %sudo/s/^# //' /etc/sudoers"
                    $sh_c "adduser $user sudo"
                )
                ;;
            centos|fedora)
                (
                    $sh_c "groupadd -r sudo"
                    $sh_c "echo '%sudo ALL=(ALL) ALL' > /etc/sudoers"
                    $sh_c "useradd -G sudo $user"
                )
                ;;
        esac
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