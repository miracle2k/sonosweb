package Plugins::Podcasts;

use Data::Dumper;
use strict;
use LWP::UserAgent;
use HTML::Entities;
use XML::Simple;
use URI;
use Config;

###############################################################################
sub init {
    main::plugin_register("Podcasts", "Experimental Podcast Player", "/Podcasts", \&Plugins::Podcasts::html);
    main::http_register_handler("/Podcasts/index",  \&Plugins::Podcasts::index);
    main::http_register_handler("/Podcasts/edit",   \&Plugins::Podcasts::edit);
    main::add_timeout (time()+10, \&Plugins::Podcasts::timer);

    $Plugins::Podcasts::userAgent = LWP::UserAgent->new(timeout => 2);
}

###############################################################################
sub quit {
}

###############################################################################
sub build_zone_menu {
    my ($match) = @_;

    my $menu = "";
    foreach my $zone (main::http_zones()) {
        if (defined $match && ($zone eq $match)) {
            $menu .= "<OPTION VALUE=$zone SELECTED>";
        } else {
            $menu .= "<OPTION VALUE=$zone>";
        }
        $menu .= $main::ZONES{$zone}->{ZoneName} . "\n";
    }
    return $menu
}

###############################################################################
sub build_data {
    my ($id, $zone) = @_;

    my %row_data;

    my $cast = \%{$main::PREFS{Podcasts}->{casts}->{$id}};
    my $x = $Plugins::Podcasts{$id}->{xml};
    if (! $x) {
        $row_data{PODCASTS_NAME} = "Updating ...";
        $row_data{PODCASTS_DESC} = $cast->{url};
    } else {
        $row_data{PODCASTS_NAME} = $x->{channel}->{title};
        $row_data{PODCASTS_DESC} = decode_entities($x->{channel}->{description});
    }
    $row_data{PODCASTS_INFO}     = $cast->{info};
    $row_data{PODCASTS_URL}      = $cast->{url};
    $row_data{PODCASTS_ID}       = $id;
    $row_data{PODCASTS_EXPANDED} = defined $cast->{expanded};
    $row_data{PODCASTS_RENABLED} = "checked" if (! defined $cast->{noauto});
    $row_data{PODCASTS_DENABLED} = "checked" if ($cast->{autodownload});
    $row_data{PODCASTS_MENABLED} = "checked" if ($cast->{automagicsong});
    if ($cast->{magicsongartist} && $cast->{magicsongartist} ne "") {
        $row_data{PODCASTS_MARTIST} = $cast->{magicsongartist};
    } else {
        $row_data{PODCASTS_MARTIST} = "_Podcasts";
    }

    my @item_loop_data = ();
    foreach my $item (@{$x->{channel}->{item}}) {
        my %item_row_data;

        $item_row_data{ITEM_ZONE} = $zone;
        $item_row_data{ITEM_NAME} = $item->{title};
        $item_row_data{ITEM_DESC} = decode_entities($item->{description});
        next if (! defined $item->{enclosure} || ref($item->{enclosure}) ne "HASH" || !defined $item->{enclosure}->{url});
        $item_row_data{ITEM_URL}  = $item->{enclosure}->{url};
        push(@item_loop_data, \%item_row_data);
    }
    $row_data{PODCASTS_ITEM_LOOP} = \@item_loop_data;

    return %row_data;
}

###############################################################################
sub html {
    my ($c, $r, $diskpath, $template) = @_;

    my %qf = $r->uri->query_form;

    $template->param("PODCASTS_ZONEMENU" => build_zone_menu($qf{zone}));

    my @folder_loop_data = ();

    if ($template->query(name => "PODCASTS_LOOP")) {
        foreach my $id (sort (keys %{$main::PREFS{Podcasts}->{casts}})) {
            my %folder_row_data = build_data ($id, $qf{zone});
            push(@folder_loop_data, \%folder_row_data);
        }
        $template->param("PODCASTS_LOOP" => \@folder_loop_data);
    }

    if (defined $qf{podcastid}) {
        my %data = build_data($qf{podcastid}, $qf{zone});
        $template->param(%data);
    }

    if (defined $Plugins::Podcasts::Err) {
        $template->param("PODCASTS_ERR" => $Plugins::Podcasts::Err);
        undef $Plugins::Podcasts::Err;
    }
}

###############################################################################
sub index {
    my ($c, $r) = @_;

    my %qf = $r->uri->query_form;


    if (defined $qf{New}) {
        delete $main::PREFS{Podcasts}->{casts}->{new};
        $c->send_redirect(main::http_base_url($r) . "/Podcasts/edit.html?podcastid=new", HTTP::Status::RC_MOVED_TEMPORARILY);
        $c->force_last_request;
        return;
    }

    my $zonearg = "";
    if (defined $qf{zone} && $qf{zone} ne "") {
        $zonearg = "?zone=$qf{zone}";
    }
    
    if (defined $qf{refresh} && $qf{refresh} == 1) {
        foreach my $id (sort (keys %{$main::PREFS{Podcasts}->{casts}})) {
            delete $Plugins::Podcasts{$id}->{xml};
            delete $Plugins::Podcasts{$id}->{time};
        }
        eval {dofetch(100);};
        if ($@) {
            main::Log (2, "Fetch failed: $@");
        }
    }

    if (defined $qf{podcastdel} &&
        defined $main::PREFS{Podcasts}->{casts}->{$qf{podcastdel}}) {
        delete $main::PREFS{Podcasts}->{casts}->{$qf{podcastdel}};
    }
    
    if (defined $qf{podcastplay}) {
        my $url = decode_entities($qf{podcastplay});
        main::Log(3, "Play: $url on Zone: $qf{zone}");

        if  ($zonearg eq "") {
            $Plugins::Podcasts::Err = "<H1>Please select a zone.<P></H1>";
        } else  {
            main::upnp_avtransport_set_uri($qf{zone}, $url, "");
            main::upnp_avtransport_play($qf{zone});
        }
    }

    if (defined $qf{podcastadd}) {
        my $url = decode_entities($qf{podcastadd});
        main::Log(3, "Add: $url on Zone: $qf{zone}");

        if  ($zonearg eq "") {
            $Plugins::Podcasts::Err = "<H1>Please select a zone.<P></H1>";
        } else  {
            main::upnp_avtransport_add_uri($qf{zone}, $url, "");
        }
    }

    if (defined $qf{podcastcollapse}) {
        delete $main::PREFS{Podcasts}->{casts}->{$qf{podcastcollapse}}->{expanded};
        main::sonos_prefsdb_save();
    } 

    if (defined $qf{podcastexpand}) {
        $main::PREFS{Podcasts}->{casts}->{$qf{podcastexpand}}->{expanded} = 1;
        main::sonos_prefsdb_save();
    } 

    $c->send_redirect(main::http_base_url($r) . "/Podcasts/index.html$zonearg", HTTP::Status::RC_MOVED_TEMPORARILY);
    $c->force_last_request;
    return;

}

###############################################################################
sub edit {
    my ($c, $r) = @_;

    my %qf = $r->uri->query_form;

    if (defined $qf{Cancel}) {
        delete $main::PREFS{Podcasts}->{casts}->{new};
        $c->send_redirect(main::http_base_url($r) . "/Podcasts/index.html", HTTP::Status::RC_MOVED_TEMPORARILY);
        $c->force_last_request;
        return;
    }

    my $id = $qf{id};
    my $cast = \%{$main::PREFS{Podcasts}->{casts}->{$id}};

    delete $cast->{info};

    $cast->{info} = "<B>Must set a URL</B>" if (length($qf{url}) == 0);
    $cast->{info} = "<B>Must set a magic song prefix</B>" if (length($qf{magicsongartist}) == 0 && $main::MUSICDIR ne "");

    if ($cast->{info}) {
        $c->send_redirect(main::http_base_url($r) . "/Podcasts/edit.html?podcastid=$id", HTTP::Status::RC_MOVED_TEMPORARILY);
        $c->force_last_request;
        return;
    }

    $cast->{url} = $qf{url};
    if (defined $qf{radio}) {
        delete $cast->{noauto};
    } else {
        $cast->{noauto} = 1;
    }
    $cast->{autodownload} = (defined $qf{download});
    $cast->{automagicsong} = (defined $qf{magicsong});
    $cast->{magicsongartist} = $qf{magicsongartist};
    
    if ($id eq "new") {
        $main::PREFS{Podcasts}->{maxid}++;
        $id = $main::PREFS{Podcasts}->{maxid};
        $main::PREFS{Podcasts}->{casts}->{$id} = $cast;
    }

    delete $main::PREFS{Podcasts}->{casts}->{new};
    main::sonos_prefsdb_save();

    $c->send_redirect(main::http_base_url($r) . "/Podcasts/index.html", HTTP::Status::RC_MOVED_TEMPORARILY);
    $c->force_last_request;
    return;
}
###############################################################################
sub dofetch {
    my ($maxfetch) = @_;

    my $changed = 0;
    my $fetched = 0;

    foreach my $id (sort (keys %{$main::PREFS{Podcasts}->{casts}})) {
        my $cast = \%{$main::PREFS{Podcasts}->{casts}->{$id}};
        my $icast = \%{$Plugins::Podcasts{$id}};

        if (! defined $icast->{time} || ($icast->{time} < time()) ) {

            main::Log(3, "Updating " . $cast->{$id}->{url});
            my $response = $Plugins::Podcasts::userAgent->get($cast->{url});
            if (!$response->is_success() || $response->content eq "") {
                main::Log (4, "Failure: " . Dumper($response));
                $icast->{time} = time() + 5*60; # Wait 5 minutes for errors
                next;
            } else {
                $icast->{time} = time() + 2*60*60; # Wait 2 hours for success
            }

            $icast->{xml} = XMLin($response->content, forcearray => ["item"]);
            my $x = $Plugins::Podcasts{$id}->{xml};

            my $num = 0;
            foreach my $item (@{$x->{channel}->{item}}) {
                my $guid;

                if (defined $item->{guid}) {
                    if (ref($item->{guid}) eq "HASH" && $item->{guid}->{isPermaLink}) {
                        $guid = $item->{guid}->{content};
                    } else {
                        $guid = $item->{guid};
                    }
                } else {
                    next;
                }
                next if (defined $cast->{guids}->{$guid});
                next if (!defined $item->{enclosure} || ref($item->{enclosure}) ne "HASH" || !defined $item->{enclosure}->{url});
                $num++;
                last if ($num > 5); # Add at most 5 things per podcast

                $cast->{guids}->{$guid} = localtime();
                $changed = 1;

                my $ctitle = decode_entities($x->{channel}->{title});
                my $ititle = decode_entities($item->{title});
                my $stitle = "Cast: " . $ctitle . " " . $ititle;
                if (length($stitle) > 47) {
                    $stitle = "Cast: " . substr($ctitle, 0, 14) . " " . $ititle;
                }

                if (length($stitle) > 47) {
                    $stitle = substr($stitle, 0, 47);
                }

                if (!$cast->{noauto}) {
                    my $result = main::sonos_add_radio($stitle, $item->{enclosure}->{url});
                }

                if ($cast->{autodownload} && $main::MUSICDIR ne "") {
                    mkdir("$main::MUSICDIR/Podcasts") if (! -d "$main::MUSICDIR/Podcasts");
                    my $uri = URI->new($item->{enclosure}->{url});
                    my @segments = $uri->path_segments;

                    main::download($item->{enclosure}->{url}, "$main::MUSICDIR/Podcasts/$segments[-1]");
                }

                if ($cast->{automagicsong}) {
                    my $artist = "_Podcasts";
                    if ($cast->{magicsongartist} && $cast->{magicsongartist} ne "") {
                        $artist = $cast->{magicsongartist};
                    }

                    eval {Plugins::MagicSong::add($artist, $x->{channel}->{title}, $item->{title}, "/Podcasts/index?zone=%zone%&podcastadd=".$item->{enclosure}->{url});};
                }

            }
            $fetched++;
        }
        last if ($fetched > $maxfetch);
    }

    main::sonos_prefsdb_save() if ($changed);

    return $fetched;
}

###############################################################################
sub timer {
    main::add_timeout (time()+5, \&Plugins::Podcasts::timer);
    eval {dofetch(1);};
    if ($@) {
        main::Log (2, "Fetch failed: $@");
    }
}


1;
