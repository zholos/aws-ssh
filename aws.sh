#!/bin/sh

# Copyright 2013 Andrey Zholos.
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be included
# in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
# CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
# TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

set -e

RC=~/.aws

usage () {
    cat <<USAGE
Usage: aws command [options]
Commands:
  init
  build name host template [options]
    Templates:
      linux [--yum packages]
      windows password [--cygwin packages]
      ssh user
  ssh name [command]
  rdesktop name [options]
  delete name
  list
USAGE
}

error () { echo "$@";  exit 1; }

set_ () { echo -n "$2" >"$ROOT"/$1; }
get_ () { cat "$ROOT"/$1; }

name_ () {
    NAME=${1:?name}; shift
    ROOT=$RC/base/$NAME
    [ -d "$ROOT" ] || error "doesn't exist: $NAME"
}


command_init () {
    mkdir "$RC"
    ssh-keygen -t rsa -C aws -N "" \
        -f "$RC"/aws >/dev/null
    ssh-keygen -t rsa -C aws-windows -N "" -m PEM \
        -f "$RC"/aws-windows >/dev/null
    mv -i "$RC"/aws-windows "$RC"/aws-windows.pem

    cat <<MSG
Import the following two keys into AWS EC2 console:

$RC/aws.pub
$RC/aws-windows.pub

Use the aws-windows key for Windows instances which require uploading the
corresponding private key to retrieve the password:

$RC/aws-windows.pem

MSG

    mkdir "$RC"/base
}


command_build () {
    NAME=${1:?name}; shift
    ROOT=$RC/base/$NAME
    rm -rf -- "$ROOT"
    mkdir "$ROOT"

    HOST=${1:?host}; shift
    set_ host "$HOST"

    case $1 in
        linux|windows|ssh) build_"$@" ;;
        *) error "unknown template: $1" ;;
    esac
}

build_linux_yum_ () {
    ssh_ -tt sudo yum -y upgrade
    package=
    packages=$1
    set --
    while [ "$package" != "$packages" ]; do
        package=${packages%%,*}
        packages=${packages#*,}
        case $package in
            group:*) ssh_ -tt sudo yum -y groupinstall "${package#group:}" ;;
            *) set -- "$@" "$package"
        esac
    done
    if [ $# != 0 ]; then
        ssh_ -tt sudo yum -y install "$@"
    fi
}

build_linux () {
    for user in ec2-user ubuntu ""; do
        set_ user "$user"
        [ -z "$user" ] && error "can't connect to $NAME"
        ssh_ "" : && break
    done

    while [ $# != 0 ]; do
        case $1 in
            --yum) shift; build_linux_yum_ "${1:?packages}"; shift ;;
            *) error "unknown option: $1" ;;
        esac
    done
}

build_windows () {
    set_ password "${1:?password}"; shift

    set_ user Administrator

    packages=openssh
    while [ $# != 0 ]; do
        case $1 in
            --cygwin) shift; packages=$packages,${1:?packages}; shift ;;
            *) error "unknown option: $1" ;;
        esac
    done

    disk=`mktemp -d`
    mkdir "$disk"/cygwin
    for setup in setup-x86.exe setup-x86_64.exe; do
        curl -sRLo "$disk"/cygwin/$setup http://cygwin.com/$setup
    done
    cp "$RC"/aws.pub "$disk"/authorized_keys
    cat >"$disk"/setup.bat <<BAT
@echo off
if "%processor_architecture%"=="x86" (
    set setup=setup-x86.exe
    set root=%SystemDrive%\\cygwin
) else (
    set setup=setup-x86_64.exe
    set root=%SystemDrive%\\cygwin64
)
\\\\tsclient\\setup\\cygwin\\%setup% -q -g -R "%root%" ^
    -s http://mirrors.kernel.org/sourceware/cygwin ^
    -P $packages
"%root%"\\bin\\sh -l //tsclient/setup/setup.sh
BAT
    cat >"$disk"/setup.sh <<'SH'
ssh-host-config -y -w privpass
cygrunsrv -S sshd
netsh advfirewall firewall add rule name=SSH dir=in action=allow protocol=tcp localport=22
ssh-user-config -y -p ""
cat //tsclient/setup/authorized_keys >>~/.ssh/authorized_keys
echo "alias ll='ls -lA'" >>~/.bashrc
logoff
SH

    # could use rdesktop -s, but Windows Server 2008 blocks this by default
    cat <<'MSG'
Open Windows Explorer
Navigate to "share on aws"
Run setup.bat

MSG

    rdesktop_ -r disk:setup="$disk"
}

build_ssh () {
    set_ user "${1:?user}"
}


ssh_ () {
    options=$1; shift
    ssh -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=\"$ROOT/known_hosts\" \
        -i "$RC"/aws \
        $options \
        "`get_ user`@`get_ host`" "$@"
}

command_ssh () {
    name_ "$1"; shift
    ssh_ "" "$@"
}

rdesktop_ () {
    rdesktop -u "`get_ user`" -p "`get_ password`" -d aws -n aws \
             -K -g 1280x1024 -a 16 -z -T "aws $NAME" \
             "$@" "`get_ host`"
}

command_rdesktop () {
    name_ "$1"; shift
    rdesktop_ "$@"
}

command_list () {
    for ROOT in "$RC"/base/*; do
        if [ -d "$ROOT" ]; then
            NAME=${ROOT##*/}
            printf "%s\t%s\n" "$NAME" "`get_ host`"
        fi
    done
}

command_delete () {
    name_ "$1"; shift
    rm -rf -- "$ROOT"
}

case $1 in
    init|build|ssh|rdesktop|list|delete) command_"$@" ;;
    "") command_list ;;
    -h) usage ;;
    *) error "unknown command: $1" ;;
esac
