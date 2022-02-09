#!/bin/sh
# License: GNU GPLv3

### OPTIONS AND VARIABLES ###

while getopts ":a:r:b:p:w:f:h" o; do case "${o}" in
	h) printf "Optional arguments for custom use:\\n  -r: Dotfiles repository (local file or url)\\n  -p: Dependencies and programs csv (local file or url)\\n  -a: AUR helper (must have pacman-like syntax)\\n  -w: grub/lightdm background (local file or url)\\n  -f: lightdm user icon \\n  -h: Show this message\\n" && exit 1 ;;
	r) dotfilesrepo=${OPTARG} && git ls-remote "$dotfilesrepo" || exit 1 ;;
	b) repobranch=${OPTARG} ;;
	p) progsfile=${OPTARG} ;;
	a) aurhelper=${OPTARG} ;;
	w) lightdmwall=${OPTARG} ;;
	f) face=${OPTARG} ;;
	*) printf "Invalid option: -%s\\n" "$OPTARG" && exit 1 ;;
esac done

[ -z "$dotfilesrepo" ] && dotfilesrepo="https://gitlab.com/aeth_/dotfiles"
[ -z "$progsfile" ] && progsfile="https://gitlab.com/aeth_/arch-autoconf/-/raw/master/progs.csv"
[ -z "$aurhelper" ] && aurhelper="paru"
[ -z "$repobranch" ] && repobranch="master"
[ -z "$lightdmwall" ] && lightdmwall="https://gitlab.com/aeth_/dotfiles/-/raw/master/.local/share/backgrounds/bierstadt_1-a_storm_in_the_rocky_mountains.jpg"
[ -z "$face" ] && face="https://gitlab.com/aeth_/dotfiles/-/raw/master/.local/share/icons/face.png"

notint_re='[^0-9]+'
### FUNCTIONS ###

installpkg(){ pacman --noconfirm --needed -S "$1" >/dev/null 2>&1 ;}

error() { printf "%s\n" "$1" >&2; exit 1; }

welcomemsg() {
	printf "%b\n" "\033[1m"WELCOME"\033[0m"
	printf "This script will automatically install a fully-featured Linux desktop, which I use as my main machine.\n"
	printf "%b\n" "\033[1m"Important:"\033[0m"
	printf "Be sure the computer you are using has current pacman updates and refreshed Arch keyrings.\\nIf it does not, the installation of some programs might fail.\n"
}

getuserandpass() {
	printf "Enter a name for the user account: "; read -r name;
	while ! echo "$name" | grep "^[a-z][a-z0-9_-]*$" >/dev/null 2>&1; do
		printf "Invalid username. Must begin with lowercase letter, followed by lowercase letters, - or _: "; read -r name;
	done
	printf "Enter a password for %s: " "$name"; read -rs pass1; echo;
	printf "Re-enter the password: "; read -rs pass2; echo;
	while ! [ "$pass1" = "$pass2" ]; do
		printf "Passwords did not match. Enter a password for %s: " "$name"; read -rs pass1; echo;
		printf "Re-enter the password: "; read -rs pass2; echo;
	done
}

usercheck() {
	! { id -u "$name" >/dev/null 2>&1; } || (
	printf "\n%b\n" "\033[1m"WARNING!"\033[0m"
	printf "The user \`$name\` already exists on this system.\n"
	printf "The script can install for a user already existing, but it will %b any conflicting settings/dotfiles on the user account.\\n\\nThe script will %b overwrite your user files, documents, videos, etc...\n" "\033[1m"overwrite"\033[0m" "\033[1m"not"\033[0m"
	printf "Note also that the script will change $name's password to the one you just gave.\\n\\nType %b to continue:"  "\033[1m"[y/n]"\033[0m"
	read -r reply; echo;
	while [ -z "$(echo $reply | grep -E '^[YyNn]$')" ]; do
		# unset reply
		printf "type [y/n]:"; read -r reply; echo;
	done
	[ $reply =~ ^[Yy]$ ] || (clear; exit 1;))
}

adjustmakeflags() {
	printf "Enter the number of cores to use in compilation (from 1 to %d):" "$(nproc)"
	read nproc
	while [ -n "$(echo $nproc | grep -E "$notint_re")" ] || [ $nproc -lt 1 ] || [ $nproc -gt $(nproc) ]; do 
		printf "Invalid argument. It must be a number betweem 1 and %d:" "$(nproc)"
		read nproc
	done
	sed -i "s/-j2/-j$nproc/;s/^#MAKEFLAGS/MAKEFLAGS/" /etc/makepkg.conf
}

preinstallmsg() {
	printf "\nThe rest of the installation will now be totally automated and it will take some time to complete.\n"
	printf "Now just press %b and the system will begin installation:" "\033[1m"Enter"\033[0m"
	read enter
}

adduserandpass() {
	printf "Creating user %s\\n" "$name"
	useradd -m -g wheel -s /bin/zsh "$name" >/dev/null 2>&1 ||
	usermod -a -G wheel "$name" && mkdir -p /home/"$name" && chown "$name":wheel /home/"$name"
	export repodir="/home/$name/.local/src"; mkdir -p "$repodir"; chown -R "$name":wheel "$(dirname "$repodir")"
	echo "$name:$pass1" | chpasswd
	unset pass1 pass2 ;
}

installessentials() {
	printf "Installing essential packages\\n"
	for pkg in "$@"; do
		installpkg "$pkg"
	done
}

colorizepacman() {
	grep -q "ILoveCandy" /etc/pacman.conf || sed -i "/#VerbosePkgLists/a ILoveCandy" /etc/pacman.conf
	sed -i "/^#ParallelDownloads.*/ s//ParallelDownloads = 5/;s/^#Color$/Color/" /etc/pacman.conf
}

refreshkeys() {
	case "$(readlink -f /sbin/init)" in
		*systemd* )
			printf "Refreshing Arch Keyring...\n"
			pacman --noconfirm -S archlinux-keyring >/dev/null 2>&1
			;;
		*)
			printf "Enabling Arch Repositories...\n"
			pacman --noconfirm --needed -S artix-keyring artix-archlinux-support >/dev/null 2>&1
			for repo in extra community; do
				grep -q "^[$repo]" /etc/pacman.conf ||
					echo "[$repo]
Include = /etc/pacman.d/mirrorlist-arch" >> /etc/pacman.conf
			done
			pacman-key --populate archlinux
			;;
	esac ;
	printf "Updating system...\n"
	pacman --noconfirm -Syu >/dev/null 2>&1

}

newperms() { # Set special sudoers settings for install (or after).
	sed -i "/#a-ac/d" /etc/sudoers
	echo "$* #a-ac" >> /etc/sudoers ;
}

manualinstall() { # Installs $1 manually. Used only for AUR helper here.
	# Should be run after repodir is created and var is set.
	printf "Installing '%s'...\n" "$1"
	sudo -u "$name" mkdir -p "$repodir/$1"
	sudo -u "$name" git clone --depth 1 "https://aur.archlinux.org/$1.git" "$repodir/$1" >/dev/null 2>&1 ||
		{ cd "$repodir/$1" || return 1 ; sudo -u "$name" git pull --force origin master;}
	cd "$repodir/$1"
	sudo -u "$name" makepkg --noconfirm -si >/dev/null 2>&1 || return 1
}

maininstall() {
	printf "Installing '%s' (%s of %s), %s\\n" "$1" "$n" "$total" "$2"
	installpkg "$1"
}

gitmakeinstall() {
	progname="$(basename "$1" .git)"
	dir="$repodir/$progname"
	printf "Installing '%s' (%s of %s) via 'git' and 'make'. %s\\n" "$progname" "$n" "$total" "$2"
	sudo -u "$name" git clone --depth 1 "$1" "$dir" >/dev/null 2>&1 || { cd "$dir" || return 1 ; sudo -u "$name" git pull --force origin master;}
	cd "$dir" || exit 1
	make >/dev/null 2>&1
	make install >/dev/null 2>&1
	cd /tmp || return 1 ;
}

aurinstall() { 
	printf "Installing '%s' (%s of %s) from the AUR. %s\\n" "$1" "$n" "$total" "$2"
	echo "$aurinstalled" | grep -q "^$1$" && return 1
	sudo -u "$name" $aurhelper -S --noconfirm "$1" >/dev/null 2>&1
}

pipinstall() { 
	printf "Installing '%s' (%s of %s) via pip. %s\\n" "$1" "$n" "$total" "$2"
	[ -x "$(command -v "pip")" ] || installpkg python-pip >/dev/null 2>&1
	yes | pip install "$1"
}

installationloop() { 
	printf "Beginning installation of softwares specified in %s\\n" "$progsfile"
	([ -f "$progsfile" ] && cp "$progsfile" /tmp/progs.csv) || curl -Ls "$progsfile" | sed '/^\s*$/d' | sed '/^#/d' > /tmp/progs.csv
	total=$(wc -l < /tmp/progs.csv)
	aurinstalled=$(pacman -Qqm)
	while IFS=, read -r tag program comment; do
		n=$((n+1))
		echo "$comment" | grep -q "^\".*\"$" && comment="$(echo "$comment" | sed "s/\(^\"\|\"$\)//g")"
		case "$tag" in
			"A") aurinstall "$program" "$comment" ;;
			"G") gitmakeinstall "$program" "$comment" ;;
			"P") pipinstall "$program" "$comment" ;;
			*) maininstall "$program" "$comment" ;;
		esac
	done < /tmp/progs.csv ;
}

putgitrepo() { # Downloads a gitrepo $1 and places the files in $2 only overwriting conflicts
	printf "Downloading and installing config files..."
	[ -z "$3" ] && branch="master" || branch="$repobranch"
	dir=$(mktemp -d)
	[ ! -d "$2" ] && mkdir -p "$2"
	chown "$name":wheel "$dir" "$2"
	sudo -u "$name" git clone --recursive -b "$branch" --depth 1 --recurse-submodules "$1" "$dir" >/dev/null 2>&1
	sudo -u "$name" cp -rfT "$dir" "$2"
}

installdotfiles() {
	putgitrepo "$dotfilesrepo" "/home/$name" "$repobranch"
	rm -f "/home/$name/README.md" "/home/$name/LICENSE"
	# git update-index --assume-unchanged "/home/$name/README.md" "/home/$name/LICENSE"
}

xorgconf() {
	[ ! -f /etc/X11/xorg.conf.d/90-custom-kbd.conf ] && printf 'Section "InputClass"
    	Identifier "system-keyboard"
	    MatchIsKeyboard "on"
		Option "XkbLayout" "it"
    	Option "XKbOptions" "caps:escape"
	EndSection' > /etc/X11/xorg.conf.d/90-custom-kbd.conf

	[ ! -f /etc/X11/xorg.conf.d/40-libinput.conf ] && printf 'Section "InputClass"
    	Identifier "libinput touchpad catchall"
        MatchIsTouchpad "on"
	    MatchDevicePath "/dev/input/event*"
	    Driver "libinput"
		# Enable left mouse button by tapping
		Option "Tapping" "on"
	EndSection' > /etc/X11/xorg.conf.d/40-libinput.conf
}

systembeepoff() { 
	printf "Getting rid of that retarded error beep sound..."
	rmmod pcspkr
	printf "blacklist pcspkr" > /etc/modprobe.d/nobeep.conf ;
}

loginconf() {
	([ -f "$lightdmwall" ] && cp "$lightdmwall" /usr/share/pixmaps/lightdm-bg.jpg) || curl -Ls "$lightdmwall" > /usr/share/pixmaps/lightdm-bg.jpg
	([ -f "$face" ] && cp "$face" /usr/share/pixmaps/face.png) || curl -Ls "$face" > /usr/share/pixmaps/face.png
	printf "# a-ac
	theme-name = Gruvbox-Material-Dark
	icon-theme-name = Papirus-Dark
	background = /usr/share/pixmaps/lightdm-bg.jpg
	screensaver-timeout = 15
	font-name = IBM Plex Mono Semi-Bold 11
	cursor-theme-name = capitaine-cursors-light
	default-user-image = /usr/share/pixmaps/face.png
	xft-antialias = true" >> /etc/lightdm/lightdm-gtk-greeter.conf
	case "$(readlink -f /sbin/init)" in
		*systemd* )
			systemctl enable lightdm 
			;;
		*)
			# TODO
			;;
	esac ;
}

alsaconfig()
{
	printf "Just choose the default sound card to use:"
	aplay -l | uniq
	printf "Enter card number:"
	read cardnum
	maxcardnum=$(aplay -l | uniq | grep card | tail -1 | awk '{print $2}' | sed 's/:*$//')
	while [ -n "$(echo $cardnum | grep -E "$notint_re")" ] || [ $cardnum -lt 0 ] || [ $cardnum -gt $maxcardnum ]; do
		printf "Invalid argument. It must be a number betweem 0 and %d:" "$maxcardnum"
		read cardnum
	done

	[ ! -f /etc/asound.conf ] && printf "defaults.pcm.card %d
	defaults.ctl.card %d" "$cardnum" "$cardnum" > /etc/asound.conf
}

finalize(){ \
	printf "\n"
	printf "%b" "\033[1m"All Done!"\033[0m"
	printf "\nProvided there were no hidden errors, the script completed successfully and all the programs and configuration files should be in place.\\n\\nTo run the new graphical environment, log out and log back in as your new user, then run the command \"startx\" to start the graphical environment (it will start automatically in tty1).\n"
}

### THE ACTUAL SCRIPT ###

# Welcome user and pick dotfiles.
welcomemsg || error "User exited."

# Get and verify username and password.
getuserandpass || error "User exited."

# Give warning if user already exists.
usercheck || error "User exited."

# Use more cores for compilation.
adjustmakeflags || error "Error setting makeflags"

# Last chance for user to back out before install.
preinstallmsg || error "User exited."

# Refresh Arch keyrings.
refreshkeys || error "Error automatically refreshing Arch keyring. Consider doing so manually."

# Add essentials for program installation.
installessentials curl base-devel git ntp

# Create or update user.
adduserandpass || error "Error adding username and/or password."

[ -f /etc/sudoers.pacnew ] && cp /etc/sudoers.pacnew /etc/sudoers # Just in case

# Temporary allows the user to run sudo without password. 
newperms "%wheel ALL=(ALL) NOPASSWD: ALL"

# Make pacman colorful, concurrent downloads and Pacman eye-candy.
colorizepacman || error "Error colorizing pacman"

# install AUR helper
manualinstall $aurhelper || error "Error installing $aurhepler"

# The command that does all the installing.
installationloop || error

# Install the dotfiles in the user's home directory
installdotfiles || error "Error installing dotfiles"

# Get rid of the beep
systembeepoff || error "Error removing system beep"

# Make zsh the default shell for the user.
chsh -s /bin/zsh "$name" >/dev/null 2>&1
sudo -u "$name" mkdir -p "/home/$name/.cache/zsh/"

# Tap to click && caps:swapescape
xorgconf || error "Error configuring xorg"

# Set up lightdm (if installed)
([ -x "$(command -v "lightdm")" ] && [ -x "$(command -v "lightdm-gtk-greeter")" ]) && (loginconf || error "Error setting up lightdm")

# select default audio card (if more than one is present)
[ $(aplay -l | uniq | grep card | tail -1 | awk '{print $2}' | sed 's/:*$//') != 0 ] &&
	(printf "\n%b" "\033[1m"ALMOST DONE"\033[0m" &&
	alsaconfig || error "Error configuring ALSA")

# This line, overwriting the `newperms` command above will allow the user to run
# serveral important commands, `shutdown`, `reboot`, updating, etc. without a password.
newperms "%wheel ALL=(ALL) ALL #a-ac
%wheel ALL=(ALL) NOPASSWD: /usr/bin/shutdown,/usr/bin/reboot,/usr/bin/systemctl suspend,/usr/bin/wifi-menu,/usr/bin/mount,/usr/bin/umount,/usr/bin/systemctl restart NetworkManager,/usr/bin/rc-service NetworkManager restart,/usr/bin/loadkeys,/usr/bin/paru"

# the end
finalize
