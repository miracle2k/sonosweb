package Plugins::AIM;

use Data::Dumper;
use LWP::UserAgent;
use POSIX qw(strftime);
use URI::Escape;

eval "use Net::OSCAR qw(:standard); use Net::OSCAR::Utility;";
if ($@) {
    $Plugins::AIM::NET_OSCAR = 0;
} else {
    $Plugins::AIM::NET_OSCAR = 1;
}

$Plugins::AIM::STATE = 0;
%Plugins::AIM::CMDS = ();

use strict;

###############################################################################
sub init {
    main::plugin_register("AIM", "AIM Bot Support", "/AIM", \&Plugins::AIM::html);
    main::http_register_handler("/AIM/index", \&Plugins::AIM::index);

    if ($Plugins::AIM::NET_OSCAR) {
        main::add_timeout (time()+5, \&Plugins::AIM::attempt_signon);
    }

    add ("search", \&Plugins::AIM::cmd_search);
    add ("info", \&Plugins::AIM::cmd_info);
    add ("play", \&Plugins::AIM::cmd_playqueue);
    add ("queue", \&Plugins::AIM::cmd_playqueue);
    add ("volume", \&Plugins::AIM::cmd_volume);
    add ("zone", \&Plugins::AIM::cmd_zone);
    add ("pause", \&Plugins::AIM::cmd_pause);
    add ("stop", \&Plugins::AIM::cmd_stop);
    add ("next", \&Plugins::AIM::cmd_next);
    add ("previous", \&Plugins::AIM::cmd_previous);
    add ("mute", \&Plugins::AIM::cmd_mute);
    add ("link", \&Plugins::AIM::cmd_link);
    add ("unlink", \&Plugins::AIM::cmd_unlink);
    add ("radio", \&Plugins::AIM::cmd_radio);
    add ("linein", \&Plugins::AIM::cmd_linein);
    add ("current", \&Plugins::AIM::cmd_current);
    add ("repeat", \&Plugins::AIM::cmd_repeat);
    add ("shuffle", \&Plugins::AIM::cmd_shuffle);

#    main::sonos_add_waiting("AV", "*", \&Plugins::AIM::av);
}

###############################################################################
sub quit {
}

###############################################################################
sub need_zone {
    my ($oscar, $sender) = @_;

    if (! $Plugins::AIM::zone{$sender}) {
        $oscar->send_im($sender, "Set a zone first with 'zone {zone}'");
        return 1;
    }

    return 0;
}

###############################################################################
sub need_msg {
    my ($oscar, $sender, $message, $minlen) = @_;

    if (length ($message) < $minlen) {
        $oscar->send_im($sender, "Command too short");
        return 1;
    }

    return 0;
}

###############################################################################
sub findzone {
    my ($zonestr) = @_;

    my $zonepos;

    foreach my $zone (main::http_zones()) {
        if ($main::ZONES{$zone}->{ZoneName} =~ /^$zonestr$/i) {
            return $zone;
        }

        if ($main::ZONES{$zone}->{ZoneName} =~ /^$zonestr/i) {
            $zonepos = $zone;
        }
    }

    return $zonepos;
}

###############################################################################
sub cmd_zone {
    my($oscar, $sender, $message, $parts) = @_;

    my $space = index($message, " ");
    return if (need_msg($oscar, $sender, $message, $space+1));
    my $zone = findzone(substr($message, $space+1));
    if ($zone) {
        if (defined $main::PREFS{AIM}->{members}->{$zone}) {
            $oscar->send_im($sender, "Zone set to $main::ZONES{$zone}->{ZoneName}");
            $Plugins::AIM::zone{$sender} = $zone;
        } else {
            $oscar->send_im($sender, "Found zone $main::ZONES{$zone}->{ZoneName}, however that zone is not enabled in the <a href=\"" . main::http_base_url() . "/AIM/index.html\">AIM Controls</a>");
        }
    } else {
        my $msg = "Unknown zone, available zones are: ";
        my $i = 0;
        foreach my $zone (main::http_zones()) {
            next if (! defined $main::PREFS{AIM}->{members}->{$zone});
            $msg .= ", " if ($i > 0);
            $msg .= $main::ZONES{$zone}->{ZoneName};
            $i++;
        }
        $oscar->send_im($sender, $msg);
    }
}

###############################################################################
sub cmd_volume {
    my($oscar, $sender, $message, $parts) = @_;

    return if (need_zone($oscar, $sender));
    my $space = index($message, " ");
    return if (need_msg($oscar, $sender, $message, $space+1));

    my $ch = substr($message, 2, 1);
    my $zone = $Plugins::AIM::zone{$sender};

    if ($ch eq "-") {
        return if (need_msg($oscar, $sender, $message, $space+2));
        my $dif = int (substr($message, $space+2)) * -1;
        main::upnp_render_volume_change($zone, $dif);
    } elsif ($ch eq "+") {
        return if (need_msg($oscar, $sender, $message, $space+2));
        my $dif = int (substr($message, $space+2));
        main::upnp_render_volume_change($zone, $dif);
    } else {
        my $raw = int (substr($message, $space+1));
        main::upnp_render_volume($zone, $raw);
    }

    $oscar->send_im($sender, "Volume for $main::ZONES{$zone}->{ZoneName} is now " . main::upnp_render_volume($zone));
}

###############################################################################
sub cmd_search {
    my($oscar, $sender, $message, $parts) = @_;

    return if (need_zone($oscar, $sender));
    my $space = index($message, " ");
    return if (need_msg($oscar, $sender, $message, $space+2));
    my $zone = $Plugins::AIM::zone{$sender};

    my @data = @{$Plugins::AIM::results{$sender}} = main::http_do_search($zone, substr($message, $space+1), 30);
    $Plugins::AIM::results{$sender} = \@data;

    my $i = 0;
    my $msg = "<br>\n";
    foreach my $item (@{$Plugins::AIM::results{$sender}}) {
        $msg .= sprintf("%2d %s<br>\n",$i, $item->{MUSIC_NAME});
        $i++;
    }

    if ($#data > 30) {
        $msg .= "Truncating at 30 results<br>\n";
    }
    $msg .= "Now use p [id] or q [id]<br>\n";


    $oscar->send_im($sender, $msg);
}

###############################################################################
sub cmd_radio {
    my($oscar, $sender, $message, $parts) = @_;

    return if (need_zone($oscar, $sender));
    my $space = index($message, " ");
    return if (need_msg($oscar, $sender, $message, $space+2));
    my $zone = $Plugins::AIM::zone{$sender};
    my $stationname = substr($message, $space+1);

    my $match;
    my $matched = 0;
    my $msg = "";

    my $groups = main::sonos_containers_get("R:");
    foreach my $group (@{$groups}) {
        my $stations = main::sonos_containers_get($group->{id});
        foreach my $station (@{$stations}) {
            if ($station->{'dc:title'} =~ /^$stationname/i) {
                $matched++;
                $match = $station;
                $msg .= " " . $station->{"dc:title"} . ",";
            }
        }
    }

    chop $msg;
    if ($matched == 0) {
        $msg = "No matches found";
    } elsif ($matched > 1) {
        $msg = "Too many matches: " . $msg;
    } else {
        $msg = "Found Station: " . $msg;
        main::sonos_avtransport_set_radio($zone, $match->{id});
    }

    $oscar->send_im($sender, $msg);
}

###############################################################################
sub cmd_linein {
    my($oscar, $sender, $message, $parts) = @_;

    return if (need_zone($oscar, $sender));
    my $space = index($message, " ");
    return if (need_msg($oscar, $sender, $message, $space+2));
    my $zone = $Plugins::AIM::zone{$sender};
    my $lineinname = substr($message, $space+1);

    my $lineins = main::sonos_containers_get("AI:");
    my $match;
    my $matched = 0;
    my $msg = "";

    foreach my $linein (@{$lineins}) {
        if ($linein->{"dc:title"} =~ /^$lineinname/i) {
            $matched++;
            $match = $linein;
            $msg .= " " . $linein->{"dc:title"} . ",";
        }
    }

    chop $msg;
    if ($matched == 0) {
        $msg = "No matches found";
    } elsif ($matched > 1) {
        $msg = "Too many matches: " . $msg;
    } else {
        $msg = "Found Linein: " . $msg;
        main::sonos_avtransport_set_linein($zone, $match->{id});
    }

    $oscar->send_im($sender, $msg);
}

###############################################################################
sub cmd_unlink {
    my($oscar, $sender, $message, $parts) = @_;

    shift @{$parts};

    my $msg = "";

    foreach my $zonestr (@{$parts}) {
        my $zone = findzone($zonestr);
        if ($zone) {
            next if (! defined $main::PREFS{AIM}->{members}->{$zone});
            main::sonos_unlink_zone($zone);
            $msg .= " $main::ZONES{$zone}->{ZoneName} unlinked,";
        } else {
            $msg .= " $zonestr not found,";
        }
    }

    chop $msg;
    $oscar->send_im($sender, $msg);
}

###############################################################################
sub cmd_link {
    my($oscar, $sender, $message, $parts) = @_;

    shift @{$parts};
    my $coordstr = shift @{$parts};
    my $msg = "";

    my $coordzone = findzone($coordstr);
    if (! $coordzone || ! defined $main::PREFS{AIM}->{members}->{$coordzone}) {
        $oscar->send_im($sender, "Coordinator zone not found or not allowed");
        return;
    }

    foreach my $zonestr (@{$parts}) {
        my $zone = findzone($zonestr);
        if ($zone) {
            next if (! defined $main::PREFS{AIM}->{members}->{$zone});
            main::sonos_link_zone($coordzone, $zone);
            $msg .= " $main::ZONES{$zone}->{ZoneName} linked,";
        } else {
            $msg .= " $zonestr not found,";
        }
    }
    chop $msg;
    $oscar->send_im($sender, $msg);
}

###############################################################################
sub cmd_playqueue {
    my($oscar, $sender, $message, $parts) = @_;

    my $str = $parts->[0];
    my $play = ("play" =~ /^$str/i);

    return if (need_zone($oscar, $sender));
    my $zone = $Plugins::AIM::zone{$sender};

    shift @{$parts};

    my $msg = "";
    if ($#{$parts} == -1) {
        main::upnp_avtransport_play($zone);
        sendinfo($oscar, $sender, $Plugins::AIM::zone{$sender});
        return;
    }

    if (!defined $Plugins::AIM::results{$sender}) {
        $oscar->send_im($sender, "Please do a <b>search</b> first");
        return;
    }

    my @data = @{$Plugins::AIM::results{$sender}};

    foreach my $idstr (@{$parts}) {
        my $id = int($idstr);
        if ($id < 0 || $id > $#data) {
            $msg .= " $idstr not valid id,";
            next;
        }

        my $item = $data[$id];

        if ($play) {
            main::upnp_avtransport_action($zone, "RemoveAllTracksFromQueue");
            $play = 0;
        }
        main::sonos_avtransport_add($zone, uri_unescape($item->{MUSIC_PATH}));
        $msg .= " $item->{MUSIC_NAME} added,";
    }
    main::upnp_avtransport_play($zone);

    chop $msg;
    $oscar->send_im($sender, $msg);
}

###############################################################################
sub sendinfo {
    my ($oscar, $sender, $zone) = @_;

    my %data = main::http_build_zone_data($zone, 0);
    my $msg = "<br>";
    if ($data{ACTIVE_ISRADIO}) {
        $msg .= "<b>Station:</b> $data{ACTIVE_ALBUM}<br>\n";
        $msg .= "<b>Song:</b> $data{ACTIVE_NAME}<br>\n";
    } else {
        $msg .= "<b>Artist:</b> $data{ACTIVE_ARTIST}<br>\n";
        $msg .= "<b>Album:</b> $data{ACTIVE_ALBUM}<br>\n";
        $msg .= "<b>Song:</b> $data{ACTIVE_NAME}<br>\n";
    }

    $msg .= "<b>Volume:</b> $data{ACTIVE_VOLUME} ";
    $msg .= "<b>Mute:</b> " . ($data{"ACTIVE_MUTED"}?"On":"Off") . "<br>\n";
    $msg .= "<b>Shuffle:</b> " . ($data{"ACTIVE_SHUFFLE"}?"On":"Off");
    $msg .= " <b>Repeat:</b> " . ($data{"ACTIVE_REPEAT"}?"On":"Off") . "<br>\n";
    if ($data{"ACTIVE_MODE"} == 0) {
    $msg .= "<b>Mode:</b> Stopped<br>\n"  
    } elsif ($data{"ACTIVE_MODE"} == 1) {
    $msg .= "<b>Mode:</b> Playing<br>\n"  
    } else {
    $msg .= "<b>Mode:</b> Paused<br>\n"  
    }

    $oscar->send_im($sender, $msg);
}

###############################################################################
sub cmd_current {
    my($oscar, $sender, $message, $parts) = @_;

    my $msg = "<br>\n";

    foreach my $zone (main::http_zones()) {
        next if (! defined $main::PREFS{AIM}->{members}->{$zone});

        $msg .= "<b>$main::ZONES{$zone}->{ZoneName}:</b>";
        my %data = main::http_build_zone_data($zone, 0);

        if ($data{ACTIVE_ISRADIO}) {
            $msg .= "Radio: $data{ACTIVE_NAME} / $data{ACTIVE_ALBUM} ";
        } else {
            $msg .= "$data{ACTIVE_NAME} / $data{ACTIVE_ALBUM} ";
        }

        $msg .= "<b>Vol:</b> $data{ACTIVE_VOLUME} ";
        $msg .= "<br>\n";
    }


    $oscar->send_im($sender, $msg);
}

###############################################################################
sub cmd_pause {
    my($oscar, $sender, $message, $parts) = @_;

    return if (need_zone($oscar, $sender));
    main::upnp_avtransport_action($Plugins::AIM::zone{$sender}, "Pause");
    $oscar->send_im($sender, "Paused");
}

###############################################################################
sub cmd_info {
    my($oscar, $sender, $message, $parts) = @_;

    return if (need_zone($oscar, $sender));
    sendinfo($oscar, $sender, $Plugins::AIM::zone{$sender});
}

###############################################################################
sub cmd_stop {
    my($oscar, $sender, $message, $parts) = @_;

    return if (need_zone($oscar, $sender));
    main::upnp_avtransport_action($Plugins::AIM::zone{$sender}, "Stop");
    $oscar->send_im($sender, "Stopped");
}

###############################################################################
sub cmd_next {
    my($oscar, $sender, $message, $parts) = @_;

    return if (need_zone($oscar, $sender));
    main::upnp_avtransport_action($Plugins::AIM::zone{$sender}, "Next");
    sendinfo($oscar, $sender, $Plugins::AIM::zone{$sender});
}

###############################################################################
sub cmd_previous {
    my($oscar, $sender, $message, $parts) = @_;

    return if (need_zone($oscar, $sender));
    main::upnp_avtransport_action($Plugins::AIM::zone{$sender}, "Previous");
    sendinfo($oscar, $sender, $Plugins::AIM::zone{$sender});
}

###############################################################################
sub cmd_mute {
    my($oscar, $sender, $message, $parts) = @_;

    return if (need_zone($oscar, $sender));
    if ($#{$parts} == 0) {
        $oscar->send_im($sender, "Usage: mute {on|off}");
        return;
    }

    if ($parts->[1] eq "on" || $parts->[1] eq "1") {
        main::upnp_render_mute($Plugins::AIM::zone{$sender}, 1);
        $oscar->send_im($sender, "Mute On");
    } elsif ($parts->[1] eq "off" || $parts->[1] eq "of" || $parts->[1] eq "off") {
        main::upnp_render_mute($Plugins::AIM::zone{$sender}, 0);
        $oscar->send_im($sender, "Mute Off");
    } else {
        $oscar->send_im($sender, "Usage: mute {on|off}");
    }
}

###############################################################################
sub cmd_repeat {
    my($oscar, $sender, $message, $parts) = @_;

    return if (need_zone($oscar, $sender));
    if ($#{$parts} == 0) {
        $oscar->send_im($sender, "Usage: repeat {on|off}");
        return;
    }

    if ($parts->[1] eq "on" || $parts->[1] eq "1") {
        main::upnp_avtransport_repeat($Plugins::AIM::zone{$sender}, 1);
        $oscar->send_im($sender, "Repeat On");
    } elsif ($parts->[1] eq "off" || $parts->[1] eq "of" || $parts->[1] eq "off") {
        main::upnp_avtransport_repeat($Plugins::AIM::zone{$sender}, 0);
        $oscar->send_im($sender, "Repeat Off");
    } else {
        $oscar->send_im($sender, "Usage: repeat {on|off}");
    }
}

###############################################################################
sub cmd_shuffle {
    my($oscar, $sender, $message, $parts) = @_;

    return if (need_zone($oscar, $sender));
    if ($#{$parts} == 0) {
        $oscar->send_im($sender, "Usage: shuffle {on|off}");
        return;
    }

    if ($parts->[1] eq "on" || $parts->[1] eq "1") {
        main::upnp_avtransport_shuffle($Plugins::AIM::zone{$sender}, 1);
        $oscar->send_im($sender, "Shuffle On");
    } elsif ($parts->[1] eq "off" || $parts->[1] eq "of" || $parts->[1] eq "off") {
        main::upnp_avtransport_shuffle($Plugins::AIM::zone{$sender}, 0);
        $oscar->send_im($sender, "Shuffle Off");
    } else {
        $oscar->send_im($sender, "Usage: shuffle {on|off}");
    }
}

###############################################################################
sub add {
    my ($cmd, $cb) = @_;

    $Plugins::AIM::CMDS{$cmd} = $cb;
}

###############################################################################
sub im_in {
    my($oscar, $sender, $message, $is_away) = @_;

    main::Log(4, "IM: $sender: $message: $is_away");

    $sender = Net::OSCAR::Utility::normalize($sender);

    if (! exists $main::PREFS{AIM}->{names}->{$sender}) {
        main::Log(1, "Dropping message from $sender");
        return
    }

    if ($is_away) {
        main::Log(1, "Dropping away message from $sender");
        return
    }

 
    $message =~ s/<(?:[^>'"]*|(['"]).*?\1)*>//gs;
    $message = main::trim($message);
    main::Log(1, "IM: $sender: $message");

    my @parts = split (" ", $message);

    my $msg = "";
    my $matched = 0;
    my $match;
    foreach my $cmdname (keys %Plugins::AIM::CMDS) {
        if ($cmdname =~ /^$parts[0]/i) {
            $matched++;
            $match = $cmdname;
            $msg .= " $cmdname,";
        }
    }

    chop $msg;
    if ($matched == 0) {
        $oscar->send_im($sender, "Unknown command:  See web <a href=\"" . main::http_base_url() . "/AIM/help.html\">help</a><br>" .
        "Commands include: zone [zone], info, search [regex], play [id], queue [id], next, previous, pause, stop, mute on|off, repeat on|off, shuffle on|off, radio [station], linein [name], current");
    } elsif ($matched > 1) {
        $oscar->send_im($sender, "Ambiguous command:" . $msg);
    } else {
        &{$Plugins::AIM::CMDS{$match}}($oscar,$sender,$message,\@parts);
    }
}

###############################################################################
sub signon_done {
       my($oscar) = @_;
}

###############################################################################
sub connection_changed {
    my ($oscar, $connection, $status) = @_;

    main::Log(3, "$status");
    if ($status eq "deleted") {
        main::del_read_socket($connection->get_filehandle());
    } elsif ($status eq "write") {
    } else {
        main::add_read_socket($connection->get_filehandle(), \&Plugins::AIM::process);
    }

    process();
}

###############################################################################
sub process {
    $Plugins::AIM::oscar->do_one_loop();
    $Plugins::AIM::oscar->do_one_loop();
}

###############################################################################
sub attempt_signon {
    return if ($Plugins::AIM::STATE == 1);

    if ($main::PREFS{AIM}->{enabled} && $main::PREFS{AIM}->{name} && $main::PREFS{AIM}->{password}) {
        main::Log(2, "Trying to signon");

        $Plugins::AIM::oscar = Net::OSCAR->new();
        $Plugins::AIM::oscar->set_callback_im_in(\&Plugins::AIM::im_in);
        $Plugins::AIM::oscar->set_callback_signon_done(\&Plugins::AIM::signon_done);
        $Plugins::AIM::oscar->set_callback_connection_changed(\&Plugins::AIM::connection_changed);
        $Plugins::AIM::oscar->signon($main::PREFS{AIM}->{name}, $main::PREFS{AIM}->{password});
        $Plugins::AIM::STATE = 1;
        main::add_timeout (time(), \&Plugins::AIM::timer);
    }
}

###############################################################################
sub timer {
    return if ($Plugins::AIM::STATE == 0);

    main::add_timeout (time()+2, \&Plugins::AIM::timer);
    process();
}

###############################################################################
sub build_zone_menu {
    my $i = 0;
    my $str = "";
    foreach my $zone (main::http_zones()) {
        if ($i > 0) {
            $str .= ", ";
            if ($i % 3 == 0) {
                $str .= "<br>";
            }
        }


        $str .= "<input type=checkbox name='$zone' ";
        if (defined $main::PREFS{AIM}->{members}->{$zone}) {
            $str .= "checked ";
        }

        $str .= ">&nbsp;" . $main::ZONES{$zone}->{ZoneName};
        $i++;
    }
    return $str;
}

###############################################################################
sub build_names_menu {
    my ($match) = @_;

    return "" if (! defined $main::PREFS{AIM}->{names});
    my $menu = "";
    foreach my $name (sort keys %{$main::PREFS{AIM}->{names}} ) {
        $menu .= qq/<OPTION VALUE="$name">$name\n/;
    }
    return $menu
}

###############################################################################
sub html {
    my ($c, $r, $diskpath, $template) = @_;

    $template->param("AIM_NETOSCAR" => $Plugins::AIM::NET_OSCAR,
                     "AIM_ERR"  => $Plugins::AIM::Err,
                     "AIM_NAME" => $main::PREFS{AIM}->{name},
                     "AIM_PASSWORD" => $main::PREFS{AIM}->{password},
                     "AIM_ZONES" => build_zone_menu(),
                     "AIM_NAMES" => build_names_menu()
                     );

    $template->param("AIM_ENABLED" => "checked") if ($main::PREFS{AIM}->{enabled});

    undef $Plugins::AIM::Err;
}

###############################################################################
sub index {
    my ($c, $r) = @_;

    my %qf = $r->uri->query_form;

    if (defined $qf{Add}) {
        my $newname = Net::OSCAR::Utility::normalize($qf{newname});
        if (length $newname > 0) {
            $main::PREFS{AIM}->{names}->{$newname} = ();
        }
    } elsif (defined $qf{Del}) {
        delete $main::PREFS{AIM}->{names}->{$qf{names}};
    } else {
        if (defined $qf{name} && (length ($qf{name}) > 0)) {
            $main::PREFS{AIM}->{name} = $qf{name};
        } else {
            delete $main::PREFS{AIM}->{name};
        }

        if (defined $qf{password} && (length ($qf{password}) > 0)) {
            $main::PREFS{AIM}->{password} = $qf{password};
        } else {
            delete $main::PREFS{AIM}->{password};
        }

        if ($main::PREFS{AIM}->{enabled} && !defined $qf{enabled} && $Plugins::AIM::STATE) {
            $Plugins::AIM::STATE = 0;
            $Plugins::AIM::oscar->signoff();
        }

        $main::PREFS{AIM}->{enabled} = (defined $qf{enabled});
        foreach my $zone (main::http_zones()) {
            if (defined $qf{"$zone"}) {
                $main::PREFS{AIM}->{members}->{$zone} = {};
            } else {
                delete $main::PREFS{AIM}->{members}->{$zone};
            }
        }

        attempt_signon();
    }

    main::sonos_prefsdb_save();
    $c->send_redirect(main::http_base_url($r) . "/AIM/index.html", HTTP::Status::RC_MOVED_TEMPORARILY);
    $c->force_last_request;
}

1;
