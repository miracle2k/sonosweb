package Plugins::ZPMacros;

use Data::Dumper;
use File::Copy;
use Time::HiRes;

use strict;

###############################################################################
sub init {
    main::plugin_register("ZPMacros", "ZPMacros - Perform tasks based on hitting buttons on the zone player", "/ZPMacros", \&Plugins::ZPMacros::html);
    main::http_register_handler("/ZPMacros/index", \&Plugins::ZPMacros::index);
    main::http_register_handler("/ZPMacros/del",   \&Plugins::ZPMacros::del);
    main::http_register_handler("/ZPMacros/edit",  \&Plugins::ZPMacros::edit);
    main::sonos_add_waiting("RENDER", "*", \&Plugins::ZPMacros::render);

    $Plugins::ZPMacros::userAgent = LWP::UserAgent->new(timeout => 1);
    if ($main::PASSWORD ne "") {
        $Plugins::ZPMacros::userAgent->credentials (substr(main::http_base_url(), 8), "SonosWeb", "SonosWeb", $main::PASSWORD);
    }

    delete $main::PREFS{ZPMacros}->{cmds}->{new};
}

###############################################################################
sub quit {
}

###############################################################################
sub build_cmd_menu {
    my ($match) = @_;

    my $menu     = "";
    my $selected = 0;

    foreach my $cmd (sort (keys %main::Macros)) {
        if ($cmd eq $match) {
            $menu .= "<OPTION VALUE=\"cmd\" SELECTED>";
            $selected = 1;
        } else {
            $menu .= "<OPTION VALUE=\"$cmd\">";
        }
        $menu .= $cmd . "\n";
    }
    if ($selected) {
        $menu = qq/<OPTION VALUE="">Use manual entry\n/ . $menu;
    } else {
        $menu = qq/<OPTION VALUE="" SELECTED>Use manual entry\n/ . $menu;
    }
    return $menu
}

###############################################################################
sub build_data {
    my ($id) = @_;

    my %row_data;

    my $cmd = \%{$main::PREFS{ZPMacros}->{cmds}->{$id}};

    $row_data{ZPMACROS_INFO}     = $cmd->{info};
    $row_data{ZPMACROS_BUTTONS}  = $cmd->{buttons};
    $row_data{ZPMACROS_FRIENDLY} = $cmd->{friendly};
    $row_data{ZPMACROS_URL}      = $cmd->{url};
    $row_data{ZPMACROS_FRIENDLY} = $cmd->{url} if (!$cmd->{friendly});
    $row_data{ZPMACROS_CMDMENU}  = build_cmd_menu($cmd->{friendly});
    $row_data{ZPMACROS_ID}       = $id;

    return %row_data;
}

###############################################################################
sub html {
    my ($c, $r, $diskpath, $template) = @_;

    my %qf = $r->uri->query_form;
     
    if ($template->query(name => "ZPMACROS_LOOP")) {
        my @loop_data = ();

        foreach my $id (sort {$a <=> $b} (keys %{$main::PREFS{ZPMacros}->{cmds}})) {
            next if ($id eq "new");
            my %row_data = build_data ($id);
            push(@loop_data, \%row_data);
        }

        $template->param("ZPMACROS_LOOP" => \@loop_data);
    }

    if (defined $qf{zpmacrosid}) {
        if (defined $main::PREFS{ZPMacros}->{cmds}->{$qf{zpmacrosid}}) {
            my %data = build_data($qf{zpmacrosid});
            $template->param(%data);
        } else {
            $template->param(ZPMACROS_INFO     => "",
                             ZPMACROS_CMDMENU  => build_cmd_menu(""),
                             ZPMACROS_ID       => "new");
        }
    }
}

###############################################################################
sub index {
    my ($c, $r) = @_;

    my %qf = $r->uri->query_form;

    if (defined $qf{New}) {
        delete $main::PREFS{ZPMacros}->{cmds}->{new};
        $c->send_redirect(main::http_base_url($r) . "/ZPMacros/edit.html?zpmacrosid=new", HTTP::Status::RC_MOVED_TEMPORARILY);
        $c->force_last_request;
        return;
    }

    $c->send_redirect(main::http_base_url($r) . "/ZPMacros/index.html", HTTP::Status::RC_MOVED_TEMPORARILY);
    $c->force_last_request;
    return;
}

###############################################################################
sub edit {
    my ($c, $r) = @_;

    my %qf = $r->uri->query_form;

    if (defined $qf{Cancel}) {
        delete $main::PREFS{ZPMacros}->{cmds}->{new};
        $c->send_redirect(main::http_base_url($r) . "/ZPMacros/index.html", HTTP::Status::RC_MOVED_TEMPORARILY);
        $c->force_last_request;
        return;
    }

    my $id = $qf{id};
    my $cmd = \%{$main::PREFS{ZPMacros}->{cmds}->{$id}};

    delete $cmd->{info};

    $cmd->{info} = "<B>Must set buttons</B>" if (length($qf{buttons}) == 0);

    if ((!$qf{command} || $qf{command} eq "") && length($qf{url}) == 0) {
        $cmd->{info} = "<B>Must enter a url</B>";
    }

    if ($cmd->{info}) {
        $c->send_redirect(main::http_base_url($r) . "/ZPMacros/edit.html?zpmacrosid=$id", HTTP::Status::RC_MOVED_TEMPORARILY);
        $c->force_last_request;
        return;
    }

    $cmd->{buttons}     = main::trim(substr($qf{buttons}, 0, 30));
    if ($qf{command} && $qf{command} ne "") {
        $cmd->{friendly} = $qf{command};
        $cmd->{url}      = $main::Macros{$qf{command}};
    } else {
        delete $cmd->{friendly};
        $cmd->{url}      = $qf{url};
    }
    
    if ($id eq "new") {
        $main::PREFS{ZPMacros}->{maxid}++;
        $id = $main::PREFS{ZPMacros}->{maxid};
        $main::PREFS{ZPMacros}->{cmds}->{$id} = $cmd;
    }

    delete $main::PREFS{ZPMacros}->{cmds}->{new};
    main::sonos_prefsdb_save();

    $c->send_redirect(main::http_base_url($r) . "/ZPMacros/index.html", HTTP::Status::RC_MOVED_TEMPORARILY);
    $c->force_last_request;
    return;
}

###############################################################################
sub del {
    my ($c, $r) = @_;

    my %qf = $r->uri->query_form;

    my $id = $qf{zpmacrosid};
    delete $main::PREFS{ZPMacros}->{cmds}->{$id};

    main::sonos_prefsdb_save();
    $c->send_redirect(main::http_base_url($r) . "/ZPMacros/index.html", HTTP::Status::RC_MOVED_TEMPORARILY);
    $c->force_last_request;
    return;

}
###############################################################################
sub render {
    my ($what, $zone) = @_;

    main::sonos_add_waiting("RENDER", "*", \&Plugins::ZPMacros::render);
    my $curtime = Time::HiRes::time();

    if ($curtime > $Plugins::ZPMacros::time{$zone} + 2.0) {
        $Plugins::ZPMacros::history{$zone} = "";
        $Plugins::ZPMacros::start{$zone}{Volume} = $main::ZONES{$zone}->{RENDER}->{Volume}->{Master}->{val};
    }

    if (exists $Plugins::ZPMacros::data{$zone}) {
        my $timediff = $curtime - $Plugins::ZPMacros::time{$zone};

        if ($Plugins::ZPMacros::data{$zone}{Volume} < $main::ZONES{$zone}->{RENDER}->{Volume}->{Master}->{val}) {
            if (substr ($Plugins::ZPMacros::history{$zone}, -1) ne "U" || $timediff > 0.200) {
                $Plugins::ZPMacros::history{$zone} .= "U";
            } else {
                main::Log(2, "Skipping U because short time diff $timediff");
            }
        } elsif ($Plugins::ZPMacros::data{$zone}{Volume} > $main::ZONES{$zone}->{RENDER}->{Volume}->{Master}->{val}) {
            if (substr ($Plugins::ZPMacros::history{$zone}, -1) ne "D" || $timediff > 0.200) {
                $Plugins::ZPMacros::history{$zone} .= "D";
            } else {
                main::Log(2, "Skipping U because short time diff $timediff");
            }
        } elsif ($Plugins::ZPMacros::data{$zone}{Mute} != $main::ZONES{$zone}->{RENDER}->{Mute}->{Master}->{val}) {
            $Plugins::ZPMacros::history{$zone} .= "M";
            #$Plugins::ZPMacros::history{$zone} .= (($timediff < 0.500)?"m":"M");
        }
    }

    $Plugins::ZPMacros::time{$zone} = $curtime;
    $Plugins::ZPMacros::data{$zone}{Mute} = $main::ZONES{$zone}->{RENDER}->{Mute}->{Master}->{val};
    $Plugins::ZPMacros::data{$zone}{Volume} = $main::ZONES{$zone}->{RENDER}->{Volume}->{Master}->{val};

    main::Log(2, "$zone $Plugins::ZPMacros::history{$zone}");
    foreach my $id (keys %{$main::PREFS{ZPMacros}->{cmds}}) {
        my $cmd = \%{$main::PREFS{ZPMacros}->{cmds}->{$id}};

        if ($Plugins::ZPMacros::history{$zone} eq $cmd->{buttons}) {
            my $url = main::process_macro_url($cmd->{url}, $zone, "", "", "");

            main::Log (3,  "Fetching $url");
            my $response = $Plugins::ZPMacros::userAgent->get($url);
        }
    }
}

1;
