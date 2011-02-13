package Plugins::MagicSong;

use Data::Dumper;
use File::Copy;

use strict;

###############################################################################
# Add/update a magic song 
sub add {
    my ($artist, $album, $song, $url) = @_;

    my $id;

    foreach $id (keys %{$main::PREFS{MagicSong}->{cmds}}) {
        my $cmd = \%{$main::PREFS{MagicSong}->{cmds}->{$id}};

        return if ($cmd->{artist} eq $artist && $cmd->{album} eq $album && $cmd->{song} eq $song && $url eq $cmd->{url});

        # Break from loop if url is same and changing info, or info the same and changing url
        last if ($cmd->{url} eq $url);
        last if ($cmd->{artist} eq $artist && $cmd->{album} eq $album && $cmd->{song} eq $song);
    }


    if ( ! defined $id) {
        # Create a new id
        $main::PREFS{MagicSong}->{maxid}++;
        $id = $main::PREFS{MagicSong}->{maxid};
    }

    my $cmd = \%{$main::PREFS{MagicSong}->{cmds}->{$id}};
    $cmd->{artist} = main::trim(substr($artist, 0, 30));
    $cmd->{album}  = main::trim(substr($album, 0, 30));
    $cmd->{song}   = main::trim(substr($song, 0, 30));
    $cmd->{url}    = $url;
    makemp3($id);

    main::sonos_prefsdb_save();
    if (!main::is_timeout_cb(\&main::sonos_reindex)) {
        main::add_timeout (time()+1, \&main::sonos_reindex);
    }
}
###############################################################################
sub makemp3 {
my ($id) = @_;

    if ($main::MUSICDIR eq "") {
        main::Log(0, "sonos.pl -config must be run first");
        return;
    }
    my $cmd = \%{$main::PREFS{MagicSong}->{cmds}->{$id}};

    mkdir("$main::MUSICDIR/MagicSong") if (! -d "$main::MUSICDIR/MagicSong");
    if (! -f "$main::MUSICDIR/MagicSong/magicsong$id.mp3") {
        copy("Plugins/MagicSong/empty.mp3", "$main::MUSICDIR/MagicSong/magicsong$id.mp3") ;
    }
    open(MP3, "+< $main::MUSICDIR/MagicSong/magicsong$id.mp3");
    binmode MP3	;
    sysseek MP3, -125, 2 ; syswrite MP3, padstring($cmd->{song},30),30;
    sysseek MP3, -65, 2  ; syswrite MP3, padstring($cmd->{album},30),30;
    sysseek MP3, -95, 2  ; syswrite MP3, padstring($cmd->{artist},30),30;
    close (MP3);
}
###############################################################################
sub init {
    main::plugin_register("MagicSong", "MagicSong - Add fake songs that perform tasks", "/MagicSong", \&Plugins::MagicSong::html);
    main::http_register_handler("/MagicSong/index", \&Plugins::MagicSong::index);
    main::http_register_handler("/MagicSong/del",   \&Plugins::MagicSong::del);
    main::http_register_handler("/MagicSong/edit",  \&Plugins::MagicSong::edit);
    main::sonos_add_waiting("QUEUE", "*", \&Plugins::MagicSong::queue);

    $Plugins::MagicSong::userAgent = LWP::UserAgent->new(timeout => 5);
    if ($main::PASSWORD ne "") {
        $Plugins::MagicSong::userAgent->credentials (substr(main::http_base_url(), 8), "SonosWeb", "SonosWeb", $main::PASSWORD);
    }

    delete $main::PREFS{MagicSong}->{cmds}->{new};
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

    my $cmd = \%{$main::PREFS{MagicSong}->{cmds}->{$id}};

    $row_data{MAGICSONG_INFO}     = $cmd->{info};
    $row_data{MAGICSONG_NAME}     = $cmd->{artist} . "/" . $cmd->{album} . "/" . $cmd->{song};
    $row_data{MAGICSONG_ARTIST}   = $cmd->{artist};
    $row_data{MAGICSONG_ALBUM}    = $cmd->{album};
    $row_data{MAGICSONG_SONG}     = $cmd->{song};
    $row_data{MAGICSONG_FRIENDLY} = $cmd->{friendly};
    $row_data{MAGICSONG_URL}      = $cmd->{url};
    $row_data{MAGICSONG_FRIENDLY} = $cmd->{url} if (!$cmd->{friendly});
    $row_data{MAGICSONG_CMDMENU}  = build_cmd_menu($cmd->{friendly});
    $row_data{MAGICSONG_ID}       = $id;

    return %row_data;
}

###############################################################################
sub html {
    my ($c, $r, $diskpath, $template) = @_;

    my %qf = $r->uri->query_form;
     
    if ($template->query(name => "MAGICSONG_LOOP")) {
        my @loop_data = ();

        foreach my $id (sort {$a <=> $b} (keys %{$main::PREFS{MagicSong}->{cmds}})) {
            next if ($id eq "new");
            my %row_data = build_data ($id);
            push(@loop_data, \%row_data);
        }

        $template->param("MAGICSONG_LOOP" => \@loop_data);
    }

    if (defined $qf{magicsongid}) {
        if (defined $main::PREFS{MagicSong}->{cmds}->{$qf{magicsongid}}) {
            my %data = build_data($qf{magicsongid});
            $template->param(%data);
        } else {
            $template->param(MAGICSONG_INFO     => "",
                             MAGICSONG_ARTIST   => "_MagicSong",
                             MAGICSONG_ALBUM    => "_MagicSong",
                             MAGICSONG_CMDMENU  => build_cmd_menu(""),
                             MAGICSONG_ID       => "new");
        }
    }
}

###############################################################################
sub index {
    my ($c, $r) = @_;

    my %qf = $r->uri->query_form;

    if (defined $qf{New}) {
        delete $main::PREFS{MagicSong}->{cmds}->{new};
        $c->send_redirect(main::http_base_url($r) . "/MagicSong/edit.html?magicsongid=new", HTTP::Status::RC_MOVED_TEMPORARILY);
        $c->force_last_request;
        return;
    }

    $c->send_redirect(main::http_base_url($r) . "/MagicSong/index.html", HTTP::Status::RC_MOVED_TEMPORARILY);
    $c->force_last_request;
    return;
}

###############################################################################
sub edit {
    my ($c, $r) = @_;

    my %qf = $r->uri->query_form;

    if (defined $qf{Cancel}) {
        delete $main::PREFS{MagicSong}->{cmds}->{new};
        $c->send_redirect(main::http_base_url($r) . "/MagicSong/index.html", HTTP::Status::RC_MOVED_TEMPORARILY);
        $c->force_last_request;
        return;
    }

    my $id = $qf{id};
    my $cmd = \%{$main::PREFS{MagicSong}->{cmds}->{$id}};

    delete $cmd->{info};

    $cmd->{info} = "<B>Must set a artist</B>" if (length($qf{artist}) == 0);
    $cmd->{info} = "<B>Must set a album</B>" if (length($qf{album}) == 0);
    $cmd->{info} = "<B>Must set a song</B>" if (length($qf{song}) == 0);

    if ((!$qf{command} || $qf{command} eq "") && length($qf{url}) == 0) {
        $cmd->{info} = "<B>Must enter a url</B>";
    }

    if ($cmd->{info}) {
        $c->send_redirect(main::http_base_url($r) . "/MagicSong/edit.html?magicsongid=$id", HTTP::Status::RC_MOVED_TEMPORARILY);
        $c->force_last_request;
        return;
    }

    $cmd->{artist}   = main::trim(substr($qf{artist}, 0, 30));
    $cmd->{album}    = main::trim(substr($qf{album}, 0, 30));
    $cmd->{song}     = main::trim(substr($qf{song}, 0, 30));
    if ($qf{command} && $qf{command} ne "") {
        $cmd->{friendly} = $qf{command};
        $cmd->{url}      = $main::Macros{$qf{command}};
    } else {
        delete $cmd->{friendly};
        $cmd->{url}      = $qf{url};
    }
    
    if ($id eq "new") {
        $main::PREFS{MagicSong}->{maxid}++;
        $id = $main::PREFS{MagicSong}->{maxid};
        $main::PREFS{MagicSong}->{cmds}->{$id} = $cmd;
    }

    makemp3($id);

    delete $main::PREFS{MagicSong}->{cmds}->{new};
    main::sonos_prefsdb_save();
    if (!main::is_timeout_cb(\&main::sonos_reindex)) {
        main::add_timeout (time()+1, \&main::sonos_reindex);
    }

    $c->send_redirect(main::http_base_url($r) . "/MagicSong/index.html", HTTP::Status::RC_MOVED_TEMPORARILY);
    $c->force_last_request;
    return;
}
###############################################################################
sub padstring {
    my ($str, $len) = @_;

    return $str . "\0" x ( $len - length($str));
}

###############################################################################
sub del {
    my ($c, $r) = @_;

    if ($main::MUSICDIR eq "") {
        main::Log(0, "sonos.pl -config must be run first");
        return;
    }

    my %qf = $r->uri->query_form;

    my $id = $qf{magicsongid};
    delete $main::PREFS{MagicSong}->{cmds}->{$id};

    unlink("$main::MUSICDIR/MagicSong/magicsong$id.mp3");

    main::sonos_prefsdb_save();
    $c->send_redirect(main::http_base_url($r) . "/MagicSong/index.html", HTTP::Status::RC_MOVED_TEMPORARILY);
    $c->force_last_request;
    return;

}
###############################################################################
sub queue {
    my ($what, $zone) = @_;

    main::sonos_add_waiting("QUEUE", "*", \&Plugins::MagicSong::queue);

    foreach my $qitem (@{$main::ZONES{$zone}->{QUEUE}}) {
        foreach my $id (keys %{$main::PREFS{MagicSong}->{cmds}}) {
            my $cmd = \%{$main::PREFS{MagicSong}->{cmds}->{$id}};

            if ($cmd->{artist} eq $qitem->{"dc:creator"} &&
                $cmd->{album} eq $qitem->{"upnp:album"} &&
                $cmd->{song} eq $qitem->{"dc:title"}) {

                main::Log (4,  "Found Item: " . Dumper($cmd));
                main::upnp_avtransport_remove_track($zone, $qitem->{id});
                my $url = main::process_macro_url($cmd->{url}, $zone, $cmd->{artist}, $cmd->{album}, $cmd->{song});

                main::Log (3,  "Fetching $url");
                my $response = $Plugins::MagicSong::userAgent->get($url);
            }
        }
    }
}


1;
