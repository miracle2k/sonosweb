package Plugins::ViewState;

use Data::Dumper;
use strict;

###############################################################################
sub init {
    main::plugin_register("ViewState", "View internal sonos.pl state", "/ViewState", \&Plugins::ViewState::html);
}

###############################################################################
sub quit {
}

###############################################################################
sub html {
    my ($c, $r, $diskpath, $template) = @_;
    if ($template->query(name => "VIEWSTATE_OTHER")) {
        my $state;
        $state .= "<HR><PRE>" . Data::Dumper->Dump([\@main::TIMERS], [ qw ( *main::TIMERS) ] ) . "</PRE>\n";
        $state .= "<HR><PRE>" . Data::Dumper->Dump([$main::LASTUPDATE], [ qw ( *main::LASTUPDATE) ] ) . "</PRE>\n";
        $state .= "<HR><PRE>" . Data::Dumper->Dump([\%main::PREFS], [ qw ( *main::PREFS) ] ) . "</PRE>\n";
        $state .= "<HR><PRE>" . Data::Dumper->Dump([\%main::PLUGINS], [ qw ( *main::PLUGINS) ] ) . "</PRE>\n";
        $state .= "<HR><PRE>" . Data::Dumper->Dump([\%main::WAITING], [ qw ( *main::WAITING) ] ) . "</PRE>\n";
        $state .= "<HR><PRE>" . Data::Dumper->Dump([\%main::SERVICES], [ qw ( *main::SERVICES) ] ) . "</PRE>\n";
        $template->param("VIEWSTATE_OTHER" => $state);
    }

    if ($template->query(name => "VIEWSTATE_ZONES")) {
        $template->param("VIEWSTATE_ZONES" => Data::Dumper->Dump([\%main::ZONES], [ qw ( *main::ZONES) ] ));
    }

    if ($template->query(name => "VIEWSTATE_MUSIC")) {
        $template->param("VIEWSTATE_MUSIC" => Data::Dumper->Dump([\%main::MUSIC], [ qw ( *main::MUSIC) ] ));
    }

    if ($template->query(name => "VIEWSTATE_SUBSCRIPTIONS")) {
        $template->param("VIEWSTATE_SUBSCRIPTIONS" => Data::Dumper->Dump([\%main::SUBSCRIPTIONS], [ qw ( *main::SUBSCRIPTIONS) ] ));
    }

    if ($template->query(name => "VIEWSTATE_CONTAINERS")) {
        $template->param("VIEWSTATE_CONTAINERS" => Data::Dumper->Dump([\%main::CONTAINERS], [ qw ( *main::CONTAINERS) ] ));
    }

    if ($template->query(name => "VIEWSTATE_ITEMS")) {
        $template->param("VIEWSTATE_ITEMS" => Data::Dumper->Dump([\%main::ITEMS], [ qw ( *main::ITEMS) ] ));
    }
}

1;
