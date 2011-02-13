package Plugins::AlarmClock;

use Data::Dumper;
use strict;

%Plugins::AlarmClocks::Running = ();
$Plugins::AlarmClocks::TempId = 1;

###############################################################################
sub init {
    main::plugin_register("AlarmClock", "Alarm Clock - Configure times to start playing playlists, with volume ramp.", "/AlarmClock", \&Plugins::AlarmClock::html);
    main::add_timeout (time()+10, \&Plugins::AlarmClock::timer);
    main::http_register_handler("/AlarmClock/del",   \&Plugins::AlarmClock::del);
    main::http_register_handler("/AlarmClock/run",   \&Plugins::AlarmClock::run);
    main::http_register_handler("/AlarmClock/stop",  \&Plugins::AlarmClock::stop);
    main::http_register_handler("/AlarmClock/sleep", \&Plugins::AlarmClock::sleep);
    main::http_register_handler("/AlarmClock/edit",  \&Plugins::AlarmClock::edit);
    main::http_register_handler("/AlarmClock/index", \&Plugins::AlarmClock::index);

    delete $main::PREFS{AlarmClock}->{alarms}->{new};

    eval {Plugins::MagicSong::add("_AlarmClock", "_Sleep", "05 Minutes", "/AlarmClock/sleep?zone=%zone%&minutes=5");};
    eval {Plugins::MagicSong::add("_AlarmClock", "_Sleep", "15 Minutes", "/AlarmClock/sleep?zone=%zone%&minutes=15");};
    eval {Plugins::MagicSong::add("_AlarmClock", "_Sleep", "30 Minutes", "/AlarmClock/sleep?zone=%zone%&minutes=30");};
}

###############################################################################
sub quit {
    delete $main::PREFS{AlarmClock}->{alarms}->{new};
}

###############################################################################
sub build_zone_menu {
    my ($match) = @_;

    my $menu = "";
    foreach my $zone (main::http_zones()) {
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
sub build_pl_menu {
    my ($match) = @_;

    my $selected = 0;
    my $menu;
    my $playlists = main::sonos_containers_get("SQ:");
    foreach my $pl (sort {$a->{"dc:title"} cmp $b->{"dc:title"}} (@{$playlists})) {
        if ($pl->{"dc:title"} eq $match) {
            $menu .= qq/<OPTION VALUE="$pl->{"dc:title"}" SELECTED>/;
            $selected = 1;
        } else {
            $menu .= qq/<OPTION VALUE="$pl->{"dc:title"}">/;
        }
        $menu .= $pl->{"dc:title"} . "\n";
    }
    if ($selected) {
        $menu = qq/<OPTION VALUE="">Use Current\n/ . $menu;
    } else {
        $menu = qq/<OPTION VALUE="" SELECTED>Use Current\n/ . $menu;
    }
    return $menu
}
###############################################################################
sub build_linein_menu {
    my ($match) = @_;

    my $selected = 0;
    my $menu;
    my $lineins = main::sonos_containers_get("AI:");
    foreach my $linein (sort {$a->{"dc:title"} cmp $b->{"dc:title"}} (@{$lineins})) {
        if ($linein->{"dc:title"} eq $match) {
            $menu .= qq/<OPTION VALUE="$linein->{"dc:title"}" SELECTED>/;
            $selected = 1;
        } else {
            $menu .= qq/<OPTION VALUE="$linein->{"dc:title"}">/;
        }
        $menu .= $linein->{"dc:title"} . "\n";
    }
    if ($selected) {
        $menu = qq/<OPTION VALUE="">Use Current\n/ . $menu;
    } else {
        $menu = qq/<OPTION VALUE="" SELECTED>Use Current\n/ . $menu;
    }
    return $menu
}
###############################################################################
sub build_pm_menu {
    my ($match) = @_;
    my $selected = 0;

    my $menu;
    foreach my $pm ("Normal", "Repeat", "Shuffle", "Shuffle - Repeat") {
        if ($pm eq $match) {
            $menu .= qq/<OPTION VALUE="$pm" SELECTED>/;
            $selected = 1;
        } else {
            $menu .= qq/<OPTION VALUE="$pm">/;
        }
        $menu .= $pm . "\n";
    }
    if ($selected) {
        $menu = qq/<OPTION VALUE="">Use Current Mode/ . $menu;
    } else {
        $menu = qq/<OPTION VALUE="" SELECTED>Use Current Mode/ . $menu;
    }
    return $menu
}
###############################################################################
sub build_radio_menu {
    my ($match) = @_;

    my $selected = 0;
    my $menu;
    my $groups = main::sonos_containers_get("R:");
    foreach my $group (sort {$a->{"dc:title"} cmp $b->{"dc:title"}} @{$groups}) {
        my $stations = main::sonos_containers_get($group->{id});
        foreach my $station (sort {$a->{"dc:title"} cmp $b->{"dc:title"}} @{$stations}) {

            if ("$group->{'dc:title'}/$station->{'dc:title'}" eq $match) {
                $menu .= qq,<OPTION VALUE="$group->{'dc:title'}/$station->{'dc:title'}" SELECTED>\n,;
                $selected = 1;
            } else {
                $menu .= qq,<OPTION VALUE="$group->{'dc:title'}/$station->{'dc:title'}">\n,;
            }
            $menu .= $group->{'dc:title'} . " - " . $station->{'dc:title'} . "\n";
        }
    }
    if ($selected) {
        $menu = qq/<OPTION VALUE="">Use Current/ . $menu;
    } else {
        $menu = qq/<OPTION VALUE="" SELECTED>Use Current/ . $menu;
    }
    return $menu
}
###############################################################################
sub build_data {
    my ($id) = @_;

    my %row_data;

    my $alarm = \%{$main::PREFS{AlarmClock}->{alarms}->{$id}};

    $row_data{ALARMCLOCK_INFO}     = $alarm->{info};
    $row_data{ALARMCLOCK_NAME}     = $alarm->{name};
    $row_data{ALARMCLOCK_TIME}     = $alarm->{time};
    $row_data{ALARMCLOCK_BVOLUME}  = $alarm->{bvolume};
    $row_data{ALARMCLOCK_EVOLUME}  = $alarm->{evolume};
    $row_data{ALARMCLOCK_TVOLUME}  = $alarm->{tvolume};
    $row_data{ALARMCLOCK_PLAYLIST} = $alarm->{playlist};
    $row_data{ALARMCLOCK_RUNNING}  = defined $Plugins::AlarmClocks::Running{$alarm->{id}};
    $row_data{ALARMCLOCK_PLMENU}   = build_pl_menu($alarm->{playlist});
    $row_data{ALARMCLOCK_RADIO}    = $alarm->{radio};
    $row_data{ALARMCLOCK_RMENU}    = build_radio_menu($alarm->{radio});
    $row_data{ALARMCLOCK_INPUT}    = $alarm->{linein};
    $row_data{ALARMCLOCK_LMENU}   = build_linein_menu($alarm->{linein});
    $row_data{ALARMCLOCK_ID}       = $id;
    $row_data{ALARMCLOCK_ENABLED}  = "checked" if ($alarm->{enabled});
    $row_data{ALARMCLOCK_UNMUTE}   = "checked" if ($alarm->{unmute});
    $row_data{ALARMCLOCK_UNLINK}   = "checked" if ($alarm->{unlink});
    $row_data{ALARMCLOCK_ZONE}     = $alarm->{zone};
    $row_data{ALARMCLOCK_ZONENAME} = $main::ZONES{$alarm->{zone}}->{ZoneName} if ($main::ZONES{$alarm->{zone}});
    $row_data{ALARMCLOCK_ZONEMENU} = build_zone_menu($alarm->{zone});
    $row_data{ALARMCLOCK_PMMENU }  = build_pm_menu($alarm->{playmode});
    $row_data{ALARMCLOCK_PLAYTIME } = $alarm->{playtime};

    my $days = "";
    foreach my $d ("sun", "mon", "tue", "wed", "thu", "fri", "sat") {
        if ($alarm->{$d}) {
            $row_data{"ALARMCLOCK_".uc($d)} = "checked" if ($alarm->{$d});
            $days .= ucfirst($d) . " ";
        }
    }
    $row_data{ALARMCLOCK_DAYS} = $days;

    return %row_data;
}

###############################################################################
sub html {
    my ($c, $r, $diskpath, $template) = @_;

    my %qf = $r->uri->query_form;

    my $now_string = localtime;
    $template->param("ALARMCLOCK_CURTIME" => $now_string);

    if ($template->query(name => "ALARMCLOCK_LOOP")) {
        my @loop_data = ();

        foreach my $id (sort (keys %{$main::PREFS{AlarmClock}->{alarms}})) {
            next if ($id eq "new");
            my %row_data = build_data ($id);
            push(@loop_data, \%row_data);
        }

        $template->param("ALARMCLOCK_LOOP" => \@loop_data);
        $template->param("ALARMCLOCK_ZONEMENU" => build_zone_menu(""));
    }

    if (defined $qf{alarmclockid}) {
        if (defined $main::PREFS{AlarmClock}->{alarms}->{$qf{alarmclockid}}) {
            my %data = build_data($qf{alarmclockid});
            $template->param(%data);
        } else {
            $template->param("ALARMCLOCK_BVOLUME" => 10,
                             "ALARMCLOCK_EVOLUME" => 60,
                             "ALARMCLOCK_TVOLUME" => 5,
                             "ALARMCLOCK_ID"      => "new",
                             "ALARMCLOCK_TIME"    => "07:00",
                             "ALARMCLOCK_UNMUTE"  => "checked",
                             "ALARMCLOCK_MON"     => "checked",
                             "ALARMCLOCK_TUE"     => "checked",
                             "ALARMCLOCK_WED"     => "checked",
                             "ALARMCLOCK_THU"     => "checked",
                             "ALARMCLOCK_FRI"     => "checked",
                             "ALARMCLOCK_PLAYTIME"=> 0,
                             "ALARMCLOCK_PLMENU"  => build_pl_menu(),
                             "ALARMCLOCK_RMENU"   => build_radio_menu(),
                             "ALARMCLOCK_LMENU"   => build_linein_menu(),
                             "ALARMCLOCK_PMMENU"  => build_pm_menu(),
                             "ALARMCLOCK_UNLINK"  => "checked",
                             "ALARMCLOCK_ZONEMENU"=> build_zone_menu());
        }
    }
}

###############################################################################
sub startAlarm {
    my ($alarm) = @_;

    main::Log(1, "Doing Alarm:" . $alarm->{name});


    # First unlink so the coordinator is right
    if ($alarm->{unlink}) {
        main::sonos_unlink_zone($alarm->{zone});
    }

    my $zone = $main::ZONES{$alarm->{zone}}->{Coordinator};

    $alarm->{last} = time();
    $Plugins::AlarmClocks::Running{$alarm->{id}} = $alarm;

    if ($alarm->{unmute}) {
        main::upnp_render_mute($zone, 0);
    }

    if ($alarm->{bvolume} != -1) {
        main::upnp_render_volume($zone, $alarm->{bvolume});
    }

    if ($alarm->{playlist}) {
        main::upnp_avtransport_action($zone, "RemoveAllTracksFromQueue");
        if (! ($main::ZONES{$zone}->{AV}->{AVTransportURI} =~ /queue/)) {
            main::sonos_avtransport_set_queue($zone);
        }
        my $playlists = main::sonos_containers_get("SQ:");
        foreach my $pl (@{$playlists}) {
            next if ($pl->{"dc:title"} ne $alarm->{playlist});
            main::sonos_avtransport_add($zone, $pl->{id});
            last;
        }
    }

    if ($alarm->{radio}) {
        my ($ugroup, $ustation) = split("/", $alarm->{radio});
        my $groups = main::sonos_containers_get("R:");
        foreach my $group (@{$groups}) {
            next if ($group->{"dc:title"} ne $ugroup);
            my $stations = main::sonos_containers_get($group->{id});
            foreach my $station (@{$stations}) {
                next if ($station->{"dc:title"} ne $ustation);
                main::sonos_avtransport_set_radio($zone, $station->{id});
                last;
            }
            last;
        }
    }

    if ($alarm->{linein}) {
        my $lineins = main::sonos_containers_get("AI:");
        foreach my $linein (@{$lineins}) {
            next if ($linein->{"dc:title"} ne $alarm->{linein});
            main::sonos_avtransport_set_linein($zone, $linein->{id});
            last;
        }
    }


    if ($alarm->{playmode}) {
        if ($alarm->{playmode} =~ /Repeat/) {
            main::upnp_avtransport_repeat($zone, 1);
        } else {
            main::upnp_avtransport_repeat($zone, 0);
        }

        if ($alarm->{playmode} =~ /Shuffle/) {
            main::upnp_avtransport_shuffle($zone, 1);
        } else {
            main::upnp_avtransport_shuffle($zone, 0);
        }
    }

    $alarm->{lastvolume} = main::upnp_render_volume($zone);
    $alarm->{startvolume} = main::upnp_render_volume($zone);
    $alarm->{vstoptime} = time() + ($alarm->{tvolume}*60);
    if (defined $alarm->{playtime} && $alarm->{playtime} > 0) {
        $alarm->{stoptime} = time() + ($alarm->{playtime}*60);
    } else {
        $alarm->{stoptime} = $alarm->{vstoptime};
    }

    main::upnp_avtransport_play($zone);
}
###############################################################################
sub continueAlarm {
    my ($alarm) = @_;

    my $zone = $main::ZONES{$alarm->{zone}}->{Coordinator};

    if (time() >= $alarm->{stoptime}) {
        main::upnp_render_volume($zone, $alarm->{evolume}); # Make sure we hit end volume
        delete $Plugins::AlarmClocks::Running{$alarm->{id}};
        if (defined $alarm->{playtime} && $alarm->{playtime} != 0) {
            main::upnp_avtransport_action($zone, "Pause");
        }
        return;
    }

    if ($alarm->{lastvolume} != main::upnp_render_volume($zone)) {
        main::Log(1, "Alarm " . $alarm->{name} . " stopped, since volume changed");
        delete $Plugins::AlarmClocks::Running{$alarm->{id}};
        return;
    }

    if (time() >= $alarm->{vstoptime}) {
        main::upnp_render_volume($zone, $alarm->{evolume}); # Make sure we hit end volume
        $alarm->{lastvolume} = main::upnp_render_volume($zone);
        return;
    }

    my $vol = int($alarm->{startvolume} +
           ($alarm->{evolume} - $alarm->{startvolume}) * (time() - $alarm->{last})/($alarm->{tvolume}*60));

    if (main::upnp_render_volume($zone) != $vol) {
        main::upnp_render_volume($zone, $vol);
        $alarm->{lastvolume} = main::upnp_render_volume($zone);
    }
}
###############################################################################
sub timer {
    main::add_timeout (time()+1, \&Plugins::AlarmClock::timer);

    my @days = ("sun", "mon", "tue", "wed", "thu", "fri", "sat");

    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime time();


    foreach my $id (sort (keys %{$main::PREFS{AlarmClock}->{alarms}})) {
        next if ($id eq "new");
        my $alarm = \%{$main::PREFS{AlarmClock}->{alarms}->{$id}};

        next if ($Plugins::AlarmClocks::Running{$id});

        # See if we should start this alarm
        next if (!$alarm->{enabled});
        next if ($alarm->{last} && (time() - $alarm->{last} < 120));
        next if ($alarm->{hour} != $hour);
        next if ($alarm->{min} != $min);
        next if (!$alarm->{$days[$wday]});

        $alarm->{id} = $id;
        startAlarm($alarm);
    }

# Go through the ones running already
    foreach my $id (keys %Plugins::AlarmClocks::Running) {
        continueAlarm($Plugins::AlarmClocks::Running{$id});
    }
}

###############################################################################
sub index {
    my ($c, $r) = @_;

    my %qf = $r->uri->query_form;

    if (defined $qf{New}) {
        delete $main::PREFS{AlarmClock}->{alarms}->{new};
        $c->send_redirect(main::http_base_url($r) . "/AlarmClock/edit.html?alarmclockid=new", HTTP::Status::RC_MOVED_TEMPORARILY);
        $c->force_last_request;
        return;
    }

    foreach my $id (sort (keys %{$main::PREFS{AlarmClock}->{alarms}})) {
        next if ($id eq "new");
        my $alarm = \%{$main::PREFS{AlarmClock}->{alarms}->{$id}};
        $alarm->{enabled} = (defined $qf{"al$id"});
    }

    main::sonos_prefsdb_save();
    $c->send_redirect(main::http_base_url($r) . "/AlarmClock/index.html", HTTP::Status::RC_MOVED_TEMPORARILY);
    $c->force_last_request;
    return;

}

###############################################################################
sub edit {
    my ($c, $r) = @_;

    my %qf = $r->uri->query_form;

    if (defined $qf{Cancel}) {
        delete $main::PREFS{AlarmClock}->{alarms}->{new};
        $c->send_redirect(main::http_base_url($r) . "/AlarmClock/index.html", HTTP::Status::RC_MOVED_TEMPORARILY);
        $c->force_last_request;
        return;
    }

    my $id = $qf{id};
    my $alarm = \%{$main::PREFS{AlarmClock}->{alarms}->{$id}};

    delete $alarm->{info};

    $alarm->{info} = "<B>Must set a name</B>" if (length($qf{name}) == 0);
    $alarm->{info} = "<B>Must set a time</B>" if (length($qf{time}) != 5);
    $alarm->{info} = "<B>Time wrong format, must be 5 characters 24hr time.</B>" if (!($qf{time} =~ /^[012][0-9]:[0-5][0-9]$/));
    $alarm->{info} = "<B>Don't select both a Radio Station and a Playlist</B>" if ($qf{radio} && $qf{playlist});
    $alarm->{info} = "<B>Don't select both a Radio Station and an Line-In</B>" if ($qf{radio} && $qf{linein});
    $alarm->{info} = "<B>Don't select both a Playlist and an Line-In</B>" if ($qf{playlist} && $qf{linein});

    if ($alarm->{info}) {
        $c->send_redirect(main::http_base_url($r) . "/AlarmClock/edit.html?alarmclockid=$id", HTTP::Status::RC_MOVED_TEMPORARILY);
        $c->force_last_request;
        return;
    }

    delete $alarm->{last};

    $alarm->{name} = $qf{name};
    $alarm->{time} = $qf{time};
    $alarm->{hour} = int(substr($alarm->{time}, 0, 2));
    $alarm->{min}  = int(substr($alarm->{time}, 3, 2));

    foreach my $v ("bvolume", "evolume", "tvolume") {
        $alarm->{$v} = int($qf{$v});
        next if ($v eq "bvolume" && $alarm->{$v} == -1);
        $alarm->{$v} = 0 if ($alarm->{$v} < 0);
        $alarm->{$v} = 100 if ($alarm->{$v} > 100);
    }

    $alarm->{radio}    = $qf{radio};
    $alarm->{playlist} = $qf{playlist};
    $alarm->{linein}   = $qf{linein};
    $alarm->{zone}     = $qf{zone};
    if (!defined $qf{playtime} || $qf{playtime} eq "") {
        $alarm->{playtime} = 0;
    } else {
        $alarm->{playtime} = int($qf{playtime});
    }
    $alarm->{playmode} = $qf{playmode};

    foreach my $d ("sun", "mon", "tue", "wed", "thu", "fri", "sat") {
        $alarm->{$d} = (defined $qf{$d});
    }
    $alarm->{unmute} = (defined $qf{unmute});
    $alarm->{unlink} = (defined $qf{unlink});

    if ($id eq "new") {
        $main::PREFS{AlarmClock}->{maxid}++;
        $id = $main::PREFS{AlarmClock}->{maxid};
        $main::PREFS{AlarmClock}->{alarms}->{$id} = $alarm;
    }
    delete $main::PREFS{AlarmClock}->{alarms}->{new};
    main::sonos_prefsdb_save();

    $c->send_redirect(main::http_base_url($r) . "/AlarmClock/index.html", HTTP::Status::RC_MOVED_TEMPORARILY);
    $c->force_last_request;
    return;
}

###############################################################################
sub del {
    my ($c, $r) = @_;

    my %qf = $r->uri->query_form;

    my $id = $qf{alarmclockid};
    delete $main::PREFS{AlarmClock}->{alarms}->{$id};

    main::sonos_prefsdb_save();
    $c->send_redirect(main::http_base_url($r) . "/AlarmClock/index.html", HTTP::Status::RC_MOVED_TEMPORARILY);
    $c->force_last_request;
    return;
}

###############################################################################
sub run {
    my ($c, $r) = @_;

    my %qf = $r->uri->query_form;

    my $id = $qf{alarmclockid};
    my $alarm = \%{$main::PREFS{AlarmClock}->{alarms}->{$id}};
    if (defined $alarm) {
        $alarm->{id} = $id;
        startAlarm($alarm);
    }
    $c->send_redirect(main::http_base_url($r) . "/AlarmClock/index.html", HTTP::Status::RC_MOVED_TEMPORARILY);
    $c->force_last_request;
    return;
}
###############################################################################
sub stop {
    my ($c, $r) = @_;

    my %qf = $r->uri->query_form;

    my $id = $qf{alarmclockid};
    my $alarm = \%{$main::PREFS{AlarmClock}->{alarms}->{$id}};
    if (defined $alarm) {
        delete $Plugins::AlarmClocks::Running{$alarm->{id}};
    }
    $c->send_redirect(main::http_base_url($r) . "/AlarmClock/index.html", HTTP::Status::RC_MOVED_TEMPORARILY);
    $c->force_last_request;
    return;
}
###############################################################################
sub sleep {
    my ($c, $r) = @_;

    my %qf = $r->uri->query_form;

    my $alarm;
    $alarm->{id}       = "t" . $Plugins::AlarmClocks::TempId++;
    if (exists $qf{bvolume}) {
        $alarm->{bvolume}  = int($qf{bvolume});
    } else {
        $alarm->{bvolume}  = -1;
    }
    if (exists $qf{evolume}) {
        $alarm->{evolume}  = int($qf{evolume});
    } else {
        $alarm->{evolume}  = -1;
    }
    $alarm->{tvolume}  = int($qf{minutes});
    $alarm->{zone}     = $qf{zone};
    $alarm->{playtime} = int($qf{minutes});
    $alarm->{unlink}   = 1;

    startAlarm($alarm);
    $c->send_redirect(main::http_base_url($r) . "/AlarmClock/index.html", HTTP::Status::RC_MOVED_TEMPORARILY);
    $c->force_last_request;
    return;
}

1;
