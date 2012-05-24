#!/usr/bin/perl -w
#
# lrc.pl - prints the lyric of the currently playing song
#
# Prints lyric as the songs are played. Works even if you seek to
# random locations in the song. Expects the LRC formatted lyric file
# to be in the same directory of the currently playing song with
# ".lrc" appended to the file name (including the .ogg/.mp3/.whatever
# suffix). Rhythmbox/MPRIS is known to (still) work, while the status
# of QuodLibet is unclear. It should be trivial to update it to
# support other players that implement the MPRIS API (and not that
# difficult to support other DBus APIs).
#
# Includes very basic edit functionality that can be invoked with the -e
# option.
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

package LRC;

sub _insert_lrc_line;

sub open
{
    my ($file) = @_;

    unless (open FH, "<$file") {
        #warn $!;
        return ();
    }
    my @lines = <FH>;
    close FH or return ();

    my %settings = ( 'offset' => 0 );
    my @ret = ([0, undef]);

    for my $l (@lines) {
        chomp $l;
        my @times = ();

        while ($l =~ /\[(.+?):(.+?)\]/ogc) {
            my $car = $1;
            my $cdr = $2;

            if ($car =~ /^\d+$/ and $cdr =~ /^((\d+)(\.(\d\d))?)$/) {
                my $sec = $1;
                my $t = $car * 60 + $sec;

                push @times, $t - ($settings{'offset'} / 1000);
            } else {
                $settings{$car} = $cdr;
            }
        }

        if (pos $l and (pos($l) + 1) < length $l) {
            my $s = substr $l, pos $l;
            if ($s) {
                _insert_lrc_line(\@ret, $_, $s) for @times;
            }
        }
    }

    shift @ret;

    for (@ret) {
        my ($t, $s) = @{$_};
    }

    return @ret;
}

sub calc_diff
{
    my ($r) = @_;
    my $cur = 0;
    my @ret = ();

    for (@$r) {
        my ($t, $s) = (@$_);

        push @ret, [$t - $cur, $s];
        $cur = $t;
    }

    return @ret;
}

sub _insert_lrc_line
{
    my ($rec, $t, $s) = @_;
    my $len = $#$rec;

    for (reverse(0..$len)) {
        my $r = $$rec[$_];

        if ($$r[0] < $t) {
            splice @$rec, $_ + 1, 0, [$t, $s];
            return;
        }
    }

    splice @$rec, 1, 0, [$t, $s];
}

use URI;
use URI::Escape;
use Net::DBus;
use Net::DBus::Reactor;
use Net::DBus::Callback;

sub lrc_open;
sub lrc_play;
sub lrc_seek;
sub lrc_pause;
sub lrc_resume;

my $service = undef;
my $player = undef;

sub _rhythmbox_play
{
    my ($uri) = @_;
    return unless $uri;

    my $file = uri_unescape(URI->new($uri)->path);
#    $file =~ s/'/\\'/g;
    lrc_open("$file.lrc");

    my $song = $service->get_object("/org/gnome/Rhythmbox/Shell")->getSongProperties($uri);
    my $album = $$song{'album'} || 'Unknown';
    my $artist = $$song{'artist'} || 'Unknown';
    my $title = $$song{'title'} || 'Unknown';
    print "\n--------------------";
    print "\n$album: $artist - $title";
}

my %rhythmbox = (
    'service' => 'org.gnome.Rhythmbox',
    'object' => '/org/gnome/Rhythmbox/Player',
    'signals' => {
        'playingUriChanged' => \&_rhythmbox_play,
        'elapsedChanged' => \&lrc_seek,
        'playingChanged' => sub {
            my ($playing) = @_;

            if ($playing) {
                lrc_resume();
            } else {
                lrc_pause();
            }
        },
    },
    'methods' => {
        'time' => sub {
            return $player->getElapsed();
        }
    },
    'init' => sub {
        my $uri = $player->getPlayingUri();
        if ($uri) {
            _rhythmbox_play($uri);

            if ($player->getPlaying()) {
                lrc_play();
            }

            my $elapsed = $player->getElapsed();
            lrc_seek($elapsed);
        }
    }
    );

sub _quodlibet_play
{
    my ($song) = @_;
    my $file = $$song{'~filename'};
    lrc_open("$file.lrc");

    if ($player->IsPlaying()) {
        lrc_play();
    }

    my $album = $$song{'album'} || 'Unknown';
    my $artist = $$song{'artist'} || 'Unknown';
    my $title = $$song{'title'} || 'Unknown';
    print "\n--------------------";
    print "\n$album: $artist - $title";
}

my %quodlibet = (
    'service' => 'net.sacredchao.QuodLibet',
    'object' => '/net/sacredchao/QuodLibet',
    'signals' => {
        'SongStarted' => \&_quodlibet_play,
        'SongEnded' => \&lrc_pause,
        'Paused' => \&lrc_pause,
        'Unpaused' => \&lrc_resume,
#         'SongSeeked' => sub {
#             my ($song, $t) = @_;
#             lrc_seek($t / 1000);
#         }
    },
    'init' => sub {
        my $song = $player->CurrentSong();
        if ($song) {
            _quodlibet_play($song);
            my $pos = $player->GetPosition();
            lrc_seek($pos / 1000) if $pos;
        }
    },
    );

sub mpris_play
{
    my ($metadata) = @_;
    my $url = $$metadata{'xesam:url'};
    my $title = $$metadata{'xesam:title'} || 'Unknown';
    my $album = $$metadata{'xesam:album'} || 'Unknown';
    my $artist = $$metadata{'xesam:artist'} || ['Unknown'];
    $artist = $$artist[0];

    if ($url) {
        my $file = uri_unescape(URI->new($url)->path);
        lrc_open("$file.lrc");
        print "\n--------------------";
        print "\n$album: $artist - $title";
    }

    my $player = $service->get_object('/org/mpris/MediaPlayer2');
    my $playbackstatus = $player->Get('org.mpris.MediaPlayer2.Player',
                                      'PlaybackStatus');
    if ($playbackstatus eq 'Playing') {
        lrc_play();
        return 1;
    }

    return 0;
}

my %mpris = (
    'service' => 'org.mpris.MediaPlayer2.rhythmbox',
    'object' => '/org/mpris/MediaPlayer2',
    'signals' => {
        'PropertiesChanged' => sub {
            # for some reason there's always an empty array reference
            # at the end
            my ($iface, $changes, @ignored) = @_;

            if (ref($changes) eq 'HASH') {
                while (my ($k, $v) = each(%$changes)) {
                    if ($k eq 'PlaybackStatus') {
                        if ($v eq 'Paused') { lrc_pause(); }
                        elsif ($v eq 'Playing') { lrc_resume(); }
                    } elsif ($k eq 'Metadata') {
                        mpris_play($v);
                    } else {
                        #print "$k = $v\n";
                    }
                }
            }
        },
        'Seeked' => sub {
            my ($t) = @_;
            lrc_seek($t / 1000 / 1000);
        }
    },
    'methods' => {
        'time' => sub {
            return $player->Get('org.mpris.MediaPlayer2.Player', 'Position') / 1000 / 1000;
        }
    },
    'init' => sub {
        my $metadata = $player->Get('org.mpris.MediaPlayer2.Player', 'Metadata');
        if (mpris_play($metadata)) {
            my $t = $player->Get('org.mpris.MediaPlayer2.Player', 'Position');
            lrc_seek($t / 1000 / 1000);
        }
    },
    );

my %players = (
    'org.gnome.Rhythmbox' => \%rhythmbox,
    'net.sacredchao.QuodLibet' => \%quodlibet,
    'org.mpris.MediaPlayer2.rhythmbox' => \%mpris,
    );

my $loop = Net::DBus::Reactor->main(); 
my $bus = Net::DBus->find;
my $dbus = $bus->get_service("org.freedesktop.DBus")->get_object("/org/freedesktop/DBus");
my $using = undef;

while (my ($name, $value) = each(%players)) {
    if ($dbus->NameHasOwner($name)) {
        print "Using $name\n";
        $using = $value;
        last;
    }
}

unless ($using) {
    print STDERR "No running player detected\n";
    exit(1);
}

sub connect_to_player
{
    $service = $bus->get_service($$using{'service'});
    $player = $service->get_object($$using{'object'});

    while (my ($signal, $v) = each(%{$$using{'signals'}})) {
        if (ref($v)) {
            $player->connect_to_signal($signal, $v);
        }
    }
};

# found a player, register to be notified for when it goes down
$dbus->connect_to_signal(
    'NameOwnerChanged', sub {
        my ($name, $old, $new) = @_;

        if ($name eq $$using{'service'}) {
            if ($new and $new ne $old) {
                connect_to_player();
                my $init = $$using{'init'};
                $init->() if $init;
            } else {
                lrc_pause();
            }
        }
    });

connect_to_player();

######################################################################
# LRC Editing
######################################################################
my $editing = 0;
my @lrc_abs = ();

my $cur = -1;

$editing = 1 if @ARGV and $ARGV[0] eq '-e';

sub _lrc_mark
{
    <STDIN>;
    my $methods = $$using{'methods'};
    my $time = $methods ? $$methods{'time'} : undef;
    my $rec = undef;

    unless(@lrc_abs) {
        print "No lrc file found\n";
        exit(1);
    }
    return unless @lrc_abs;
    return unless $time;
    $cur = 0 if $cur < 0;

    $rec = $lrc_abs[$cur];
    $$rec[0] = $time->();
    if ($$rec[0] > 60) {
        use integer;
        my $m = $$rec[0] / 60;
        my $s = $$rec[0] % 60;
        $$rec[0] = sprintf "%02d:%02d", $m, $s;
    } else {
        $$rec[0] = sprintf "00:%02d", $$rec[0];
    }
    print "$$rec[1]\n";

    $cur++;

    if ($cur > $#lrc_abs) {
        print "[$$_[0]]$$_[1]\n" for @lrc_abs;
        exit(0);
    }
}

if ($editing) {
    $loop->add_read(
        0, Net::DBus::Callback->new(method => \&_lrc_mark));
}

######################################################################

use Time::HiRes qw(gettimeofday tv_interval);

sub _show_lrc_next;

my @lrc_rel = ();
my $last_shown = -1;
my $time_last = undef;
my $time_offset = 0;

my $time_w = undef;
my $time_active = 0;

BEGIN {
    $| = 1;
    system('tput', 'civis');
};

my $init = $$using{'init'};
$init->() if $init;

$loop->run();

sub _toggle_timer
{
    my ($status, $t) = @_;

    return if $editing;

    if ($status) {
        $loop->remove_timeout($time_w) if defined $time_w;
        $time_w = $loop->add_timeout(
            $t, Net::DBus::Callback->new( method => \&_show_lrc_next ), 1);
    } else {
        $loop->remove_timeout($time_w) if defined $time_w;
        $time_w = undef;
    }

    $time_active = $status;
}

sub lrc_open
{
    my ($file) = @_;

    @lrc_rel = ();
    if ((@lrc_abs = LRC::open($file))) {
        @lrc_rel = LRC::calc_diff(\@lrc_abs);
    }

    $cur = -1;
    $last_shown = -1;

    _toggle_timer(0);
}

sub lrc_play
{
    return unless @lrc_rel;

    $cur = -1;
    _toggle_timer(0);

    _show_lrc_next;
}

sub _show_line
{
    my ($n) = @_;

    return if $editing;

    if ($last_shown != $n) {
        my $r = $lrc_rel[$n];
        my (undef, $str) = @$r;

        print "\n$str";
        $last_shown = $n;
    }
}

sub _show_lrc_next
{
    return unless @lrc_rel;
    return if $editing;

    $time_last = [gettimeofday()];
    $time_offset = 0;

    if ($cur != -1 and $cur < @lrc_rel) {
        _show_line($cur);
    }

    $cur++;

    if ($cur < @lrc_rel) {
        my $r = $lrc_rel[$cur];
        my ($t, undef) = @$r;

        _toggle_timer(1, $t * 1000);
    }
}

sub lrc_seek
{
    return unless @lrc_rel;
    return if $editing;

    my ($to) = @_;
    my $was_active = $time_active;

    _toggle_timer(0);

    for (0..$#lrc_abs) {
        my ($t, $s) = (@{$lrc_abs[$_]});

        if ($t > $to) {
            if ($was_active) {
                _toggle_timer(1, ($t - $to) * 1000);
            }

            if ($_ > 0 and $_ != $cur) {
                _show_line($_ - 1);
#                my (undef, $prev) = (@{$lrc_abs[$_ - 1]});
#                print "\n$prev";
            }

            $cur = $_;

            return;
        }
    }

    if ($cur - 1 != $#lrc_abs) {
        # seeked past the end, show the last line
        _show_line($#lrc_abs);
#        my (undef, $last) = @{$lrc_abs[$#lrc_abs]};
#        print "\n$last";
#        $cur = @lrc_abs;
    }
}

sub lrc_pause
{
    return unless @lrc_rel;
    return if $editing;

    _toggle_timer(0);
    $time_offset += tv_interval($time_last);
}

sub lrc_resume
{
    return unless @lrc_rel && $cur < @lrc_abs;
    return if $editing;

    if ($cur == -1) {
        lrc_play();
        return;
    }

    my ($t, undef) = @{$lrc_rel[$cur]};

    _toggle_timer(1, ($t - $time_offset) * 1000);
}
