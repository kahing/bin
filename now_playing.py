#!/usr/bin/python
#
# now_playing.py - sets pidgin's tune status to the current song
#
# This was written a long time ago (on 12/31/2008 if the file's mtime
# is to be believed. Rhythmbox's DBus API has changed (to be MPRIS
# based) and I don't use Quodlibet anymore so I can't speak to its
# workingness. This only sets the tune attribute in pidgin, so it has
# no effect on protocols that don't support one. It was tested to work
# with MSN and GTalk (but it won't work with other XMPP protocols).
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

import dbus
import sys
from dbus.mainloop.glib import DBusGMainLoop
import gobject

DBusGMainLoop(set_as_default=True)

bus = dbus.SessionBus()

purple = bus.get_object('im.pidgin.purple.PurpleService',
                        '/im/pidgin/purple/PurpleObject')
purple = dbus.Interface(purple, 'im.pidgin.purple.PurpleInterface')

album = None
artist = None
title = None

def playing_now(new_album, new_artist, new_title):
    global album, artist, title
    album = new_album
    artist = new_artist
    title = new_title
    print("Now playing [%s] [%s] [%s]" % (album, artist, title))

def playing_resume(*args):
    purple.PurpleUtilSetCurrentSong(title, artist, album)

def playing_pause(*args):
    purple.PurpleUtilSetCurrentSong('', '', '')

player = None

######################################################################
# Rhythmbox support
######################################################################
def _rhythmbox_play(uri):
    if uri is None or uri == '':
        return

    shell = bus.get_object(using['service'], '/org/gnome/Rhythmbox/Shell')
    song = shell.getSongProperties(uri)
    playing_now(song['album'], song['artist'], song['title'])

def _rhythmbox_playing_changed(playing):
    if playing:
        playing_resume()
    else:
        playing_pause()

def _rhythmbox_init():
    uri = player.getPlayingUri()

    if uri is not None:
        _rhythmbox_play(uri)

        if player.getPlaying():
            playing_resume()

rhythmbox = {
    'service' : 'org.gnome.Rhythmbox',
    'object' : '/org/gnome/Rhythmbox/Player',
    'signals' : {
        'playingUriChanged' : _rhythmbox_play,
        'playingChanged' : _rhythmbox_playing_changed,
    },
    'init' : _rhythmbox_init
}

######################################################################
# Quodlibet support
######################################################################
def _quodlibet_play(song):
    playing_now(song['album'], song['artist'], song['title'])

    if player.IsPlaying():
        playing_resume()

def _quodlibet_init():
    song = player.CurrentSong()

    if song is not None:
        _quodlibet_play(song)

quodlibet = {
    'service' : 'net.sacredchao.QuodLibet',
    'object' : '/net/sacredchao/QuodLibet',
    'signals' : {
        'SongStarted' : _quodlibet_play,
        'SongEnded' : playing_pause,
        'Paused' : playing_pause,
        'Unpaused' : playing_resume,
    },
    'init' : _quodlibet_init
}

######################################################################
# Connect to players
######################################################################
players = ( rhythmbox, quodlibet )

bus = dbus.SessionBus()
bus_obj = bus.get_object('org.freedesktop.DBus', '/org/freedesktop/DBus');
using = None

for p in players:
    if bus_obj.NameHasOwner(p['service']):
        using = p
        break

if using is None:
    sys.stderr.write("No running player detected\n")
    sys.exit(1)

def connect_to_player():
    global player
    player = bus.get_object(using['service'], using['object'])

    for (s, v) in using['signals'].iteritems():
        player.connect_to_signal(s, v, utf8_strings=True)

    print("Connected to %s" % (using['service']))

    init = using['init']
    if callable(init):
        init()


# found a player, register to be notified for when it goes down
def _dbus_name_owner_changed(name, old, new):
    if name == using['service']:
        if new != '' and new != old:
            connect_to_player()
        else:
            playing_pause()

bus_obj.connect_to_signal('NameOwnerChanged', _dbus_name_owner_changed)

connect_to_player()

try:
    gobject.MainLoop().run()
except:
    pass

playing_pause()
