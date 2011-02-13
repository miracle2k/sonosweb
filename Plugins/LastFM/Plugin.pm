package Plugins::LastFM;

use Data::Dumper;
use LWP::UserAgent;
use POSIX qw(strftime);

eval "use Digest::MD5 qw(md5_hex);";
if ($@) {
    eval "use Digest::Perl::MD5 qw(md5_hex);";
}
use strict;

###############################################################################
sub init {
    main::plugin_register("LastFM", "Last.FM support", "/LastFM", \&Plugins::LastFM::html);
    main::http_register_handler("/LastFM/index", \&Plugins::LastFM::index);
    main::http_register_handler("/LastFM/radio", \&Plugins::LastFM::radio);

    $Plugins::LastFM::userAgent = LWP::UserAgent->new(timeout => 5);
    main::sonos_add_waiting("AV", "*", \&Plugins::LastFM::av);
}

###############################################################################
sub quit {
}

###############################################################################
sub build_zone_menu {
    my ($match) = @_;

    my $menu = qq/<OPTION VALUE="">Inactive\n/;
    if ("All Zones" eq $match) {
        $menu .= qq/<OPTION VALUE="All Zones" SELECTED>All Zones\n/;
    } else {
        $menu .= qq/<OPTION VALUE="All Zones">All Zones\n/;
    }
    foreach my $zone (main::http_zones()) {
        next if ($zone ne $main::ZONES{$zone}->{Coordinator});
        if ($zone eq $match) {
            $menu .= "<OPTION VALUE=$zone SELECTED>";
        } else {
            $menu .= "<OPTION VALUE=$zone>";
        }
        $menu .= $main::ZONES{$zone}->{ZoneName} . "\n";
    }
    return $menu
}

###############################################################################
sub html {
    my ($c, $r, $diskpath, $template) = @_;

    my @loop_data = ();

    foreach my $user (sort (keys %{$main::PREFS{LastFM}->{users}})) {
        my %row_data;
        $row_data{LASTFM_USER} = $user;
        $row_data{LASTFM_ZONEMENU} = build_zone_menu($main::PREFS{LastFM}->{users}->{$user}->{zone});
        push(@loop_data, \%row_data);
    }
    $template->param("LASTFM_LOOP" => \@loop_data,
                     "LASTFM_ERR"  => $Plugins::LastFM::Err);
    undef $Plugins::LastFM::Err;
}

###############################################################################
sub index {
    my ($c, $r) = @_;

    my %qf = $r->uri->query_form;

    if (defined $qf{add}) {
        if (length ($qf{user}) == 0) {
            $Plugins::LastFM::Err = "<B>User name must not be empty</B><BR>";
        } elsif (length ($qf{password}) == 0) {
            $Plugins::LastFM::Err = "<B>Password must not be empty</B><BR>";
        } else {
            $main::PREFS{LastFM}->{users}->{$qf{user}}->{password} = md5_hex($qf{password});
            delete $main::PREFS{LastFM}->{users}->{$qf{user}}->{zone};
        }
    } elsif (defined $qf{del}) {
        delete $main::PREFS{LastFM}->{users}->{$qf{user}};
    } else {
        foreach my $user (sort (keys %{$main::PREFS{LastFM}->{users}})) {
            $main::PREFS{LastFM}->{users}->{$user}->{zone} = $qf{$user};
        }
    }

    main::sonos_prefsdb_save();
    $c->send_redirect(main::http_base_url($r) . "/LastFM/index.html", HTTP::Status::RC_MOVED_TEMPORARILY);
    $c->force_last_request;
}

###############################################################################
sub av {
    my ($what, $zone) = @_;

    main::Log(4, "invoked:$what:$zone");
    main::sonos_add_waiting("AV", "*", \&Plugins::LastFM::av);
    my $oldstr;

    $Plugins::LastFM::LAST{$zone}->{str} = "" if (! defined $Plugins::LastFM::LAST{$zone}->{str});

    return if (! defined $main::ZONES{$zone}->{AV});
    return if (! defined $main::ZONES{$zone}->{AV}->{CurrentTrackMetaData});
    return if ($main::ZONES{$zone}->{AV}->{CurrentTrackMetaData} eq "");
    return if (! defined $main::ZONES{$zone}->{AV}->{CurrentTrackMetaData}->{item});
    my $ct = \%{$main::ZONES{$zone}->{AV}->{CurrentTrackMetaData}->{item}};

    my $duration = 99999999;
    if ($ct->{res}->{duration} =~ /([0-9]):([0-9]+):([0-9]+)/) {
        $duration = $1*3600+$2*60+$3;
    }

    my $str = "&a[0]=" . main::uri_escape_utf8($ct->{"dc:creator"}) .
              "&b[0]=" . main::uri_escape_utf8($ct->{"upnp:album"}) .
              "&t[0]=" . main::uri_escape_utf8($ct->{"dc:title"}) .
              "&m[0]=" . 
              "&l[0]=" . $duration;

    main::Log(4, "Current: $str  Old:" . $Plugins::LastFM::LAST{$zone}->{str});

    return if ($str eq $Plugins::LastFM::LAST{$zone}->{str});

    if (defined $Plugins::LastFM::LAST{$zone}->{duration} && 
        ($Plugins::LastFM::LAST{$zone}->{duration}*0.95) <= (time() - $Plugins::LastFM::LAST{$zone}->{time})) {
        $oldstr = $Plugins::LastFM::LAST{$zone}->{str};
        main::Log(4, "Song was probably listened to");
    }

    #replace the LAST song with the current song
    if ($ct->{'upnp:class'} eq 'object.item.audioItem.musicTrack') {
        $Plugins::LastFM::LAST{$zone}->{str} = $str;
        $Plugins::LastFM::LAST{$zone}->{time} = time();
        $Plugins::LastFM::LAST{$zone}->{duration} = $duration;
    } else {
        delete $Plugins::LastFM::LAST{$zone};
    }

    return if (! $oldstr);

    # Now go through the users, and see if they have a linked zone with a new song to submit
    foreach my $user (keys %{$main::PREFS{LastFM}->{users}}) {
        next if (!$main::PREFS{LastFM}->{users}->{$user}->{zone});
        next if ($zone ne $main::PREFS{LastFM}->{users}->{$user}->{zone} &&
                 ("All Zones" ne $main::PREFS{LastFM}->{users}->{$user}->{zone}));
        submit($user, $zone, $oldstr);
    }
}

###############################################################################
sub submit {
    my($user, $zone, $str) = @_;

    main::Log(3, "$user, $zone, $str");

    my $url;

    if (defined $Plugins::LastFM::LASTFM{$zone}->{lastattempt} &&
        time() < $Plugins::LastFM::LASTFM{$zone}->{lastattempt} + $Plugins::LastFM::LASTFM{$zone}->{interval}) {
        main::Log(1, "Trying to submit again too soon.");
        return;
    }

    $Plugins::LastFM::LASTFM{$zone}->{lastattempt} = time();

    # Do we need to handshake?
    if (!$Plugins::LastFM::LASTFM{$zone}->{challenge} || !$Plugins::LastFM::LASTFM{$zone}->{submiturl}) {
        main::Log(2, "Need to do handshake");
        # Using "tst" for now, which is bad bad bad, waiting for Russ to respond
        $url = "http://post.audioscrobbler.com/?hs=true&p=1.1&c=tst&v=1.0&u=$user";

        $Plugins::LastFM::LASTFM{$zone}->{last} = time();
        my $response = $Plugins::LastFM::userAgent->get($url);
        if (!$response->is_success()) {
            $Plugins::LastFM::LASTFM{$zone}->{interval} = 10; # Wait at least 10 seconds before trying again
            main::Log(1, "LastFM Failed to Connect: ". Dumper($response));
            return;
        }
        my $content = $response->content;

        if ($content =~ m/UPTODATE\n(.*)\n(http:.*)\nINTERVAL ([0-9]+)/) {
            $Plugins::LastFM::LASTFM{$zone}->{challenge} = $1;
            $Plugins::LastFM::LASTFM{$zone}->{submiturl} = $2;
            $Plugins::LastFM::LASTFM{$zone}->{interval} = $3;
        } else {
            main::Log(1, "LastFM Failed handshake: $content");
            $Plugins::LastFM::LASTFM{$zone}->{interval} = 10; # Wait at least 10 seconds before trying again
            return;
        }
    }

    # Now try and submit
    my $now_string = strftime "%Y-%m-%d %H:%M:%S", gmtime;
    my $pass = md5_hex($main::PREFS{LastFM}->{users}->{$user}->{password} . $Plugins::LastFM::LASTFM{$zone}->{challenge});
    my $data = "u=$user&s=". $pass . "&".$str . "&i[0]=" . main::uri_escape_utf8($now_string) . "\n";
    main::Log(3, "Sending to Last.FM $data");

    my $request = HTTP::Request->new(POST => $Plugins::LastFM::LASTFM{$zone}->{submiturl});
    $request->content_type('application/x-www-form-urlencoded');
    $request->content($data);
    my $response = $Plugins::LastFM::userAgent->request($request);
    if ($response->is_success()) {
        my $content = $response->content;
        if ($content =~ /OK/) {
            main::Log(2, "Submitted");
        } else {
            main::Log(1, "Error: " . Dumper($response));
            delete $Plugins::LastFM::LASTFM{$zone};
        }
    } else {
        main::Log(1, "Error: " . Dumper($response));
        delete $Plugins::LastFM::LASTFM{$zone};
    }
}

###############################################################################
sub radio {
    my ($c, $r) = @_;
}


1;
