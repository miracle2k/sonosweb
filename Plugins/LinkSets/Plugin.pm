package Plugins::LinkSets;

use Data::Dumper;
use strict;

###############################################################################
sub init {
    main::plugin_register("LinkSets", "Link Sets - Configure linked zones sets, and make it easy to switch.", "/LinkSets", \&Plugins::LinkSets::html);
    main::http_register_handler("/LinkSets/del",   \&Plugins::LinkSets::del);
    main::http_register_handler("/LinkSets/edit",  \&Plugins::LinkSets::edit);
    main::http_register_handler("/LinkSets/index", \&Plugins::LinkSets::index);
    main::http_register_handler("/LinkSets/go",    \&Plugins::LinkSets::go);

    delete $main::PREFS{LinkSets}->{sets}->{new};

    my $changed = 0;
    foreach my $id (sort (keys %{$main::PREFS{LinkSets}->{sets}})) {
        my $set = \%{$main::PREFS{LinkSets}->{sets}->{$id}};

        if (ref($set->{members}) eq "ARRAY") {
            $changed = 1;
            my @members = @{$set->{members}};
            $set->{members} = {};
            foreach my $member (@members) {
                $set->{members}->{$member} = {};
            }
        }

        main::add_macro("LinkSet - " . $set->{name}, "/LinkSets/go?linksetid=$id");
    }

    main::sonos_prefsdb_save() if ($changed);
}

###############################################################################
sub quit {
    delete $main::PREFS{LinkSets}->{sets}->{new};
}

###############################################################################
sub build_zone_loop {
    my ($set) = @_;

    my $foundcoord = 0;
    
    my @loop_data = ();
    foreach my $zone (main::http_zones()) {
        my %zone_data;
        $zone_data{LINKSETS_ZONEID}   = $zone;
        if ($set eq "") {
            $zone_data{LINKSETS_CENABLED} = "";
            $zone_data{LINKSETS_MENABLED} = "";
        } else {
            if ($set->{coordinator} eq $zone) {
                $zone_data{LINKSETS_CENABLED} = "checked";
                $zone_data{LINKSETS_MENABLED} = "checked";
                $foundcoord = 1;
            }
            if (defined $set->{members}->{$zone}) {
                $zone_data{LINKSETS_MENABLED} = "checked";
                if (defined $set->{members}->{$zone}->{volume}) {
                    $zone_data{LINKSETS_VOLUME} = $set->{members}->{$zone}->{volume};
                } else {
                    $zone_data{LINKSETS_VOLUME} = "0";
                }
            } else {
                $zone_data{LINKSETS_VOLUME} = "0";
            }

        }
        $zone_data{LINKSETS_ZONENAME} = $main::ZONES{$zone}->{ZoneName};

        push(@loop_data, \%zone_data);
    }

    $loop_data[0]->{LINKSETS_CENABLED} = "checked" if (!$foundcoord);

    return \@loop_data;
}
###############################################################################
sub build_data {
    my ($id) = @_;

    my %row_data;

    my $set = \%{$main::PREFS{LinkSets}->{sets}->{$id}};

    $row_data{LINKSETS_INFO}      = $set->{info};
    $row_data{LINKSETS_NAME}      = $set->{name};
    $row_data{LINKSETS_ID}        = $id;
    $row_data{LINKSETS_ZONELOOP}  = build_zone_loop($set);
    $row_data{LINKSETS_ZONEC}     = $main::ZONES{$set->{coordinator}}->{ZoneName} if ($set->{coordinator} ne "");
    $row_data{LINKSETS_ZONES}     = "";
    $row_data{LINKSETS_MAGICSONG} = "checked" if ($set->{magicsong});
    my $first = 1;
    foreach my $zone (main::http_zones()) {
        next if (! defined $set->{members}->{$zone});
        if ($first) {
            $first = 0;
        } else {
            $row_data{LINKSETS_ZONES} .= ", ";
        }
        $row_data{LINKSETS_ZONES} .= $main::ZONES{$zone}->{ZoneName};
    }

    return %row_data;
}

###############################################################################
sub html {
    my ($c, $r, $diskpath, $template) = @_;

    my %qf = $r->uri->query_form;

    if ($template->query(name => "LINKSETS_LOOP")) {
        my @loop_data = ();

        foreach my $id (sort (keys %{$main::PREFS{LinkSets}->{sets}})) {
            next if ($id eq "new");
            my %row_data = build_data ($id);
            push(@loop_data, \%row_data);
        }

        $template->param("LINKSETS_LOOP" => \@loop_data);
    }

    if (defined $qf{linksetid}) {
        if (defined $main::PREFS{LinkSets}->{sets}->{$qf{linksetid}}) {
            my %data = build_data($qf{linksetid});
            $template->param(%data);
        } else {
            $template->param(LINKSETS_INFO     => "",
                             LINKSETS_NAME     => "",
                             LINKSETS_ID       => "new",
                             LINKSETS_ZONELOOP => build_zone_loop(""));
        }
    }
}

###############################################################################
sub index {
    my ($c, $r) = @_;

    my %qf = $r->uri->query_form;

    if (defined $qf{New}) {
        delete $main::PREFS{LinkSets}->{sets}->{new};
        $c->send_redirect(main::http_base_url($r) . "/LinkSets/edit.html?linksetid=new", HTTP::Status::RC_MOVED_TEMPORARILY);
        $c->force_last_request;
        return;
    }

    $c->send_redirect(main::http_base_url($r) . "/LinkSets/index.html", HTTP::Status::RC_MOVED_TEMPORARILY);
    $c->force_last_request;
    return;
}

###############################################################################
sub edit {
    my ($c, $r) = @_;

    my %qf = $r->uri->query_form;

    if (defined $qf{Cancel}) {
        delete $main::PREFS{LinkSets}->{sets}->{new};
        $c->send_redirect(main::http_base_url($r) . "/LinkSets/index.html", HTTP::Status::RC_MOVED_TEMPORARILY);
        $c->force_last_request;
        return;
    }

    my $id = $qf{id};
    my $set = \%{$main::PREFS{LinkSets}->{sets}->{$id}};

    delete $set->{info};

    $set->{info} = "<B>Must set a name</B>" if (length($qf{name}) == 0);
    $set->{info} = "<B>Must select a coordinator</B>" if (length($qf{coordinator}) == 0);

    if ($set->{info}) {
        $c->send_redirect(main::http_base_url($r) . "/LinkSets/edit.html?linksetid=$id", HTTP::Status::RC_MOVED_TEMPORARILY);
        $c->force_last_request;
        return;
    }

    main::del_macro("LinkSet - " . $set->{name});

    $set->{name} = $qf{name};
    $set->{coordinator} = $qf{coordinator};
    if ($id ne "new" && defined $set->{magicsong} && $set->{magicsong} && !defined $qf{"magicsong"}) {
        # Delete Magic Song
    }
    $set->{magicsong} = (defined $qf{magicsong});
    $qf{"z$qf{coordinator}"} = 1; # Make sure  the coordinator is a member

    $set->{members} = {};
    foreach my $zone (keys %main::ZONES) {
        if (defined $qf{"z$zone"}) {
            $set->{members}->{$zone} = {};
            $set->{members}->{$zone}->{volume} = int($qf{"v$zone"});
        }
    }
    
    if ($id eq "new") {
        $main::PREFS{LinkSets}->{maxid}++;
        $id = $main::PREFS{LinkSets}->{maxid};
        $main::PREFS{LinkSets}->{sets}->{$id} = $set;
    }
    if ($set->{magicsong}) {
        eval {Plugins::MagicSong::add("_LinkSets", "_LinkSets", $set->{name}, "/LinkSets/go?linksetid=$id");};
    }
    main::add_macro("LinkSet - " . $set->{name}, "/LinkSets/go?linksetid=$id");
    delete $main::PREFS{LinkSets}->{sets}->{new};
    main::sonos_prefsdb_save();

    $c->send_redirect(main::http_base_url($r) . "/LinkSets/index.html", HTTP::Status::RC_MOVED_TEMPORARILY);
    $c->force_last_request;
    return;

}

###############################################################################
sub del {
    my ($c, $r) = @_;

    my %qf = $r->uri->query_form;

    my $id = $qf{linksetid};
    delete $main::PREFS{LinkSets}->{sets}->{$id};

    main::sonos_prefsdb_save();
    $c->send_redirect(main::http_base_url($r) . "/LinkSets/index.html", HTTP::Status::RC_MOVED_TEMPORARILY);
    $c->force_last_request;
    return;

}

###############################################################################
sub go {
    my ($c, $r) = @_;

    my %qf = $r->uri->query_form;

    my $id = $qf{linksetid};
    if (defined $id && defined $main::PREFS{LinkSets}->{sets}->{$id}) {
        my $set = \%{$main::PREFS{LinkSets}->{sets}->{$id}};
        main::sonos_unlink_zone($set->{coordinator});
        foreach my $zone (keys %{$set->{members}}) {
            if (defined $set->{members}->{$zone}->{volume} &&
                $set->{members}->{$zone}->{volume} != 0) {
                main::upnp_render_volume($zone, $set->{members}->{$zone}->{volume});
            }
            next if ($zone eq $set->{coordinator});
            main::sonos_link_zone($set->{coordinator}, $zone);
        }
    }

    $c->send_redirect(main::http_base_url($r) . "/LinkSets/index.html", HTTP::Status::RC_MOVED_TEMPORARILY);
    $c->force_last_request;
}

1;
