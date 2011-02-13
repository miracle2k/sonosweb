package Plugins::AutoReindex;

use Data::Dumper;
use strict;

###############################################################################
sub init {
    main::plugin_register("AutoReindex", "Schedule an interval to automatically do a Music Reindex", "/AutoReindex", \&Plugins::AutoReindex::html);
    main::add_timeout (time()+10, \&Plugins::AutoReindex::timer);
    main::http_register_handler("/AutoReindex/settings", \&Plugins::AutoReindex::settings);
}

###############################################################################
sub quit {
}

###############################################################################
sub html {
    my ($c, $r, $diskpath, $template) = @_;

    if ($main::PREFS{AutoReindex}->{on}) {
        $template->param("AUTOREINDEX_CHECKED" => "checked");
    }

    if ($main::PREFS{AutoReindex}->{updatemin}) {
        $template->param("AUTOREINDEX_UPDATEMIN" => $main::PREFS{AutoReindex}->{updatemin});
    } else {
        $template->param("AUTOREINDEX_UPDATEMIN" => "60");
    }
}

###############################################################################
sub timer {
    main::add_timeout (time()+10, \&Plugins::AutoReindex::timer);
    if ($main::PREFS{AutoReindex}->{on} &&
        time() - $main::PREFS{AutoReindex}->{last} > 60 * $main::PREFS{AutoReindex}->{updatemin}) {
        main::Log(3, "Need to reindex");
        $main::PREFS{AutoReindex}->{last} = time();
        main::sonos_prefsdb_save();
        main::sonos_reindex();
    }
}

###############################################################################
sub settings {
    my ($c, $r) = @_;

    my %qf = $r->uri->query_form;

    if (defined $qf{on}) {
        $main::PREFS{AutoReindex}->{on} = 1;
    } else {
        $main::PREFS{AutoReindex}->{on} = 0;
    }

    if (defined $qf{updatemin}) {
        $main::PREFS{AutoReindex}->{updatemin} = int($qf{updatemin});
    }

    if ($main::PREFS{AutoReindex}->{updatemin} < 10) {
        $main::PREFS{AutoReindex}->{updatemin} = 10;
    }

    main::sonos_prefsdb_save();

    $c->send_redirect(main::http_base_url($r) . "/AutoReindex/index.html", HTTP::Status::RC_MOVED_TEMPORARILY);
    $c->force_last_request;
    return;

}

1;
