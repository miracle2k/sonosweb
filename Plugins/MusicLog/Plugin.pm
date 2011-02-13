package Plugins::MusicLog;

use Data::Dumper;
use strict;
use IO::Handle;

###############################################################################
sub init {
    main::plugin_register("MusicLog", "Silly Plugin to log what is played", "/MusicLog", \&Plugins::MusicLog::html);
    main::http_register_handler("/MusicLog/index", \&Plugins::MusicLog::index);
    open (MUSICLOG, ">>music.log");
    MUSICLOG->autoflush(1);
    main::sonos_add_waiting("AV", "*", \&Plugins::MusicLog::av);
}

###############################################################################
sub quit {
    close (MUSICLOG);
    main::Log(4, "Quiting");
}

###############################################################################
sub html {
    my ($c, $r, $diskpath, $template) = @_;

    my @loop_data = ();
    foreach my $zone (main::http_zones()) {
        my %row_data;
        $row_data{MUSICLOG_NAME} = $main::ZONES{$zone}->{ZoneName};
        $row_data{MUSICLOG_ZONE} = $zone;

        if ($main::PREFS{MusicLog}->{zones}->{$zone}->{enabled}) {
            $row_data{MUSICLOG_ENABLED} = "checked";
        }
        push(@loop_data, \%row_data);
    }
    $template->param("MUSICLOG_LOOP" => \@loop_data);
}

###############################################################################
sub index {
    my ($c, $r) = @_;

    my %qf = $r->uri->query_form;

    foreach my $zone (keys %main::ZONES) {
        if (defined $qf{$zone}) {
            $main::PREFS{MusicLog}->{zones}->{$zone}->{enabled} = 1;
        } else {
            delete $main::PREFS{MusicLog}->{zones}->{$zone}->{enabled};
        }
    }

    main::sonos_prefsdb_save();

    $c->send_redirect(main::http_base_url($r) . "/MusicLog/index.html", HTTP::Status::RC_MOVED_TEMPORARILY);
    $c->force_last_request;
    return;
}
###############################################################################
sub av {
    my ($what, $zone) = @_;

    main::sonos_add_waiting("AV", "*", \&Plugins::MusicLog::av);
    my $timestr = localtime (time());

    return if (!$main::PREFS{MusicLog}->{zones}->{$zone}->{enabled});
    return if (!defined $main::ZONES{$zone}->{AV}->{CurrentTrackMetaData});
    return if ($main::ZONES{$zone}->{AV}->{CurrentTrackMetaData} eq "");
    return if (!defined $main::ZONES{$zone}->{AV}->{CurrentTrackMetaData}->{item});
    my $ct = \%{$main::ZONES{$zone}->{AV}->{CurrentTrackMetaData}->{item}};
    return if (!defined $ct);
    if ($main::ZONES{$zone}->{AV}->{TransportState} eq "STOPPED") {
        delete $main::PREFS{MusicLog}->{zones}->{$zone}->{last};
        return;
    }
    my $str = $ct->{"dc:creator"} . "\t" .
              $ct->{"upnp:album"} . "\t" .
              $ct->{"dc:title"} . "\t" .
              $ct->{res}->{duration};
    return if ($str eq $main::PREFS{MusicLog}->{zones}->{$zone}->{last});
    $main::PREFS{MusicLog}->{zones}->{$zone}->{last} = $str;

    print MUSICLOG  $timestr . "\t" .
                    $main::ZONES{$zone}->{ZoneName} . "\t" .
                    $str . "\n";
    main::Log(4, "Logging $str");
}

1;
