package Plugins::Nanny;

use Data::Dumper;
use strict;

###############################################################################
sub init {
    main::plugin_register("Nanny", "Nanny - Monitor zones, and allow/prevent certain actions.", "/Nanny", \&Plugins::Nanny::html);
    main::http_register_handler("/Nanny/del",   \&Plugins::Nanny::del);
    main::http_register_handler("/Nanny/edit",  \&Plugins::Nanny::edit);
    main::http_register_handler("/Nanny/index", \&Plugins::Nanny::index);

    main::add_timeout (time()+10, \&Plugins::Nanny::add_waiting);
}
###############################################################################
sub add_waiting {
    main::sonos_add_waiting("RENDER", "*", \&Plugins::Nanny::waiting);
    main::sonos_add_waiting("ZONES", "*", \&Plugins::Nanny::waiting);
    check();
}

###############################################################################
sub quit {
    delete $main::PREFS{Nanny}->{rules}->{new};
}

###############################################################################
sub build_zone_menu {
    my ($id, $set) = @_;

    my $i = 0;
    my $str = "";
    foreach my $zone (main::http_zones()) {
        if ($i > 0) {
            $str .= ", ";
            if ($i % 3 == 0) {
                $str .= "<br>";
            }
        }


        $str .= "<input type=checkbox name='$id,$zone' ";
        if ($set ne "" && defined $set->{members}->{$zone}) {
            $str .= "checked ";
        }

        $str .= ">&nbsp;" . $main::ZONES{$zone}->{ZoneName};
        $i++;
    }
    return $str;
}
###############################################################################
sub build_data {
    my ($id) = @_;

    my %row_data;

    my $set = \%{$main::PREFS{Nanny}->{rules}->{$id}};

    $row_data{NANNYS_INFO}      = $set->{info};
    $row_data{NANNYS_NAME}      = $set->{name};
    $row_data{NANNYS_ID}        = $id;
    $row_data{NANNYS_ZONES}     = build_zone_menu($id, $set);
    $row_data{NANNYS_CANLINK}   = "checked" if ($set->{canlink});
    $row_data{NANNYS_MINVOLUME} = $set->{minvolume};
    $row_data{NANNYS_MAXVOLUME} = $set->{maxvolume};
    $row_data{NANNYS_STARTTIME} = $set->{starttime};
    $row_data{NANNYS_STOPTIME}  = $set->{stoptime};
    return %row_data;
}

###############################################################################
sub html {
    my ($c, $r, $diskpath, $template) = @_;

    my %qf = $r->uri->query_form;

    my $now_string = localtime;
    $template->param("NANNYS_CURTIME" => $now_string);
    if ($template->query(name => "NANNYS_LOOP")) {
        my @loop_data = ();

        foreach my $id (sort (keys %{$main::PREFS{Nanny}->{rules}})) {
            next if ($id eq "new");
            my %row_data = build_data ($id);
            push(@loop_data, \%row_data);
        }

        $template->param("NANNYS_LOOP" => \@loop_data);
    }

    if (defined $qf{nannyid}) {
        if (defined $main::PREFS{Nanny}->{rules}->{$qf{nannyid}}) {
            my %data = build_data($qf{nannyid});
            $template->param(%data);
        } else {
            $template->param(NANNYS_INFO       => "",
                             NANNYS_NAME       => "",
                             NANNYS_ID         => "new",
                             NANNYS_MINVOLUME  => "0",
                             NANNYS_MAXVOLUME  => "100",
                             NANNYS_CANLINK    => "",
                             NANNYS_STARTTIME  => "00:00",
                             NANNYS_STOPTIME   => "00:00",
                             NANNYS_ZONES      => build_zone_menu("new", ""));
        }
    }
}

###############################################################################
sub index {
    my ($c, $r) = @_;

    my %qf = $r->uri->query_form;

    if (defined $qf{New}) {
        delete $main::PREFS{Nanny}->{rules}->{new};
        $c->send_redirect(main::http_base_url($r) . "/Nanny/edit.html?nannyid=new", HTTP::Status::RC_MOVED_TEMPORARILY);
        $c->force_last_request;
        return;
    }

    if (defined $qf{Update}) {
        foreach my $id (sort (keys %{$main::PREFS{Nanny}->{rules}})) {
            foreach my $zone (main::http_zones()) {
                if (defined $qf{"$id,$zone"}) {
                    $main::PREFS{Nanny}->{rules}->{$id}->{members}->{$zone} = {};
                } else {
                    delete $main::PREFS{Nanny}->{rules}->{$id}->{members}->{$zone};
                }
            }
        }
        main::sonos_prefsdb_save();
        check();
    }

    $c->send_redirect(main::http_base_url($r) . "/Nanny/index.html", HTTP::Status::RC_MOVED_TEMPORARILY);
    $c->force_last_request;
    return;
}

###############################################################################
sub edit {
    my ($c, $r) = @_;

    my %qf = $r->uri->query_form;

    if (defined $qf{Cancel}) {
        delete $main::PREFS{Nanny}->{rules}->{new};
        $c->send_redirect(main::http_base_url($r) . "/Nanny/index.html", HTTP::Status::RC_MOVED_TEMPORARILY);
        $c->force_last_request;
        return;
    }

    my $id = $qf{id};
    my $set = \%{$main::PREFS{Nanny}->{rules}->{$id}};

    delete $set->{info};

    $set->{info} = "<B>Must set a name</B>" if (length($qf{name}) == 0);
    $set->{info} = "<B>Must set a start time</B>" if (length($qf{starttime}) != 5);
    $set->{info} = "<B>Start time wrong format, must be 5 characters 24hr time.</B>" if (!($qf{starttime} =~ /^[012][0-9]:[0-5][0-9]$/));
    $set->{info} = "<B>Must set a stop time</B>" if (length($qf{stoptime}) != 5);
    $set->{info} = "<B>Stop time wrong format, must be 5 characters 24hr time.</B>" if (!($qf{stoptime} =~ /^[012][0-9]:[0-5][0-9]$/));

    if ($set->{info}) {
        $c->send_redirect(main::http_base_url($r) . "/Nanny/edit.html?nannyid=$id", HTTP::Status::RC_MOVED_TEMPORARILY);
        $c->force_last_request;
        return;
    }

    $set->{name} = $qf{name};
    $set->{minvolume} = int($qf{minvolume});
    $set->{maxvolume} = int($qf{maxvolume});
    $set->{canlink}   = (defined $qf{canlink});
    $set->{starttime} = $qf{starttime};
    $set->{startmin} =   int(substr($set->{starttime}, 0, 2)) * 60 + int(substr($set->{starttime}, 3, 2));
    $set->{stoptime} = $qf{stoptime};
    $set->{stopmin} =   int(substr($set->{stoptime}, 0, 2)) * 60 + int(substr($set->{stoptime}, 3, 2));

    if ($id eq "new") {
        $main::PREFS{Nanny}->{maxid}++;
        $id = $main::PREFS{Nanny}->{maxid};
        $main::PREFS{Nanny}->{rules}->{$id} = $set;
    }

    delete $main::PREFS{Nanny}->{rules}->{new};
    main::sonos_prefsdb_save();

    $c->send_redirect(main::http_base_url($r) . "/Nanny/index.html", HTTP::Status::RC_MOVED_TEMPORARILY);
    $c->force_last_request;
    return;

}

###############################################################################
sub del {
    my ($c, $r) = @_;

    my %qf = $r->uri->query_form;

    my $id = $qf{nannyid};
    delete $main::PREFS{Nanny}->{rules}->{$id};

    main::sonos_prefsdb_save();
    $c->send_redirect(main::http_base_url($r) . "/Nanny/index.html", HTTP::Status::RC_MOVED_TEMPORARILY);
    $c->force_last_request;
    return;

}
###############################################################################
sub check {
    main::Log(4, "invoked");

    foreach my $id (sort (keys %{$main::PREFS{Nanny}->{rules}})) {
        my $set = $main::PREFS{Nanny}->{rules}->{$id};

        foreach my $zone (main::http_zones()) {
            if (!defined $set->{members}->{$zone}) {
                next;
            }

            if ($set->{startmin} != $set->{stopmin}) {
                my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime time();
                $min += $hour*60;

                if ($set->{startmin} < $set->{stopmin}) {
                    if ($min < $set->{startmin} || $min > $set->{stopmin}) {
                        main::Log(4, "Skipping from time:$min:$set->{startmin}:$set->{stopmin}");
                        next;
                    }
                } else {
                # Pass thru Midnight
                    if ($min < $set->{startmin} && $min > $set->{stopmin}) {
                        main::Log(4, "Skipping from time:$min:$set->{startmin}:$set->{stopmin}");
                        next;
                    }
                }

            }

            if (main::upnp_render_volume($zone) < $set->{minvolume}) {
                main::Log(4, "$zone Increasing volume");
                main::upnp_render_volume($zone, $set->{minvolume});
            }

            if (main::upnp_render_volume($zone) > $set->{maxvolume}) {
                main::Log(4, "$zone Reducing volume from " . main::upnp_render_volume($zone) . " to " . $set->{maxvolume});
                main::upnp_render_volume($zone, $set->{maxvolume});
            }

            if (!$set->{canlink} && $main::ZONES{$zone}->{Coordinator} ne $zone) {
                if (defined $main::ZONES{$main::ZONES{$zone}->{Coordinator}}) {
                    main::Log(4, "$zone Unlinking");
                    main::sonos_unlink_zone($zone);
                }
            }
        }
    }
}
###############################################################################
sub waiting {
    my ($what, $zone) = @_;
    main::sonos_add_waiting($what, "*", \&Plugins::Nanny::waiting);
    check();
}

1;
