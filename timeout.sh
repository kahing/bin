#!/bin/bash
#
# timeout.sh - time out a command execution after x seconds
#
# usage: timeout.sh <seconds> <the rest of the command>
#
# There are probably better way to do this. A coworker once asked if
# there is a way to do this in shell, and so this was born. This
# version is not used anywhere but the basic cases seem to work.
#
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2 as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
# 02110-1301 USA
#

timed_read()
{
    TIMEOUT=$1; shift
    CMD="$@"
    STARTTIME=$(date +%s)
    ENDTIME=$(expr $STARTTIME + $TIMEOUT)

    IFS="
"
    while true; do
        REMAINING=$(expr $ENDTIME - $(date +%s))
        if [ $REMAINING -le 0 ]; then
            echo "\`$CMD' timed out after $TIMEOUT seconds" >&2
            kill -9 $$
            break
        fi
        read -t $REMAINING DUMMY # < $PIPE
        RET=$?

        if [ $RET != 0 ]; then
            if [ $RET -gt 128 ]; then
                echo "\`$CMD' timed out after $TIMEOUT seconds" >&2
                kill -9 $$
            fi
            # else EOF
            break
        fi
    done
}

TIMEOUT=$1; shift
CMD=$@

( $@ | timed_read $TIMEOUT "$CMD"; exit ${PIPESTATUS[0]} )
exit $?
