package Plugins::Rhapsody;

use Data::Dumper;
use LWP::UserAgent;
use POSIX qw(strftime);
use XML::Simple;
use URI::Escape;
use SOAP::Lite maptype => {};
use HTML::Entities;

use strict;

###############################################################################
sub init {
    main::plugin_register("Rhapsody", "Rhapsody Support", "/Rhapsody", \&Plugins::Rhapsody::html);
    main::http_register_handler("/Rhapsody/index", \&Plugins::Rhapsody::index);

    main::sonos_add_hook("SEARCH", \&Plugins::Rhapsody::search);
    main::sonos_add_hook("CONTAINER_RDCPA", \&Plugins::Rhapsody::container);
    main::sonos_add_hook("ITEM_RDCPA", \&Plugins::Rhapsody::item);
    main::sonos_add_hook("ITEM_RDCPI", \&Plugins::Rhapsody::item);
    main::sonos_add_hook("META_RDCPA", \&Plugins::Rhapsody::meta);
    main::sonos_add_hook("META_RDCPI", \&Plugins::Rhapsody::meta);
# Not ready yet, only do this for rhapsody items
#    main::sonos_add_hook("META_SQ",    \&Plugins::Rhapsody::meta);
    main::sonos_add_waiting("SERVICES", "*", \&Plugins::Rhapsody::services);

    $Plugins::Rhapsody::userAgent = LWP::UserAgent->new(timeout => 5);

    $Plugins::Rhapsody::cobrandId = SOAP::Data->name("cobrandId")->value(40134)->type("");
    $Plugins::Rhapsody::filterRightsKey = SOAP::Data->name("filterRightsKey")->value(2)->type("");
    $Plugins::Rhapsody::developerKey = SOAP::Data->name("developerKey")->value("9F7E8I1D3I6H2B0I")->type("");
    $Plugins::Rhapsody::priority = SOAP::Data->name("priority")->value("5")->type("");
    $Plugins::Rhapsody::createdTop = 0;

    $Plugins::Rhapsody::metaurl = "http://direct.rhapsody.com/metadata/services/RhapsodyDirectMetadata";
    $Plugins::Rhapsody::liburl = "http://direct.rhapsody.com/library/services/RhapsodyDirectLibrary";
}

###############################################################################
sub services {
    main::sonos_add_waiting("SERVICES", "*", \&Plugins::Rhapsody::add_top_containers);
    if (exists $main::SERVICES{Rhapsody}) {
        $Plugins::Rhapsody::password = SOAP::Data->name("password")->value($main::SERVICES{Rhapsody}->{Md})->type("");
        $Plugins::Rhapsody::logon = SOAP::Data->name("logon")->value(substr($main::SERVICES{Rhapsody}->{UDN}, 11))->type("");
        add_top_containers();
    } else {
        del_top_containers();
    }
}
###############################################################################
sub add_top_containers {
    return if ($Plugins::Rhapsody::createdTop);
    return if (!exists $main::SERVICES{Rhapsody});
    return if (!$main::PREFS{Rhapsody}->{benabled});

    $Plugins::Rhapsody::createdTop = 1;

    main::sonos_mkcontainer ("", "object.container", "Rhapsody Genres", "RDCPA:GLBGENRES");
    main::sonos_mkcontainer ("", "object.container", "Rhapsody Charts", "RDCPA:GNRCHARTS");
    main::sonos_mkcontainer ("", "object.container", "Rhapsody New Releases", "RDCPA:NEWRELEASES");
    main::sonos_mkcontainer ("", "object.container", "Rhapsody Recommends", "RDCPA:RHAPRECOMMEND");
    main::sonos_mkcontainer ("", "object.container", "Rhapsody Radio Stations", "RDCPA:GLBSTATIONS");
    if ($main::PREFS{Rhapsody}->{menabled}) {
        main::sonos_mkcontainer ("", "object.container", "My Rhapsody", "RDCPA:MYRHAP");

        main::sonos_mkcontainer ("RDCPA:MYRHAP", "object.container", "My Artists", "RDCPA:LIBARTIST");
        main::sonos_mkcontainer ("RDCPA:MYRHAP", "object.container", "My Albums", "RDCPA:LIBALBUM");
        main::sonos_mkcontainer ("RDCPA:MYRHAP", "object.container", "My Genres", "RDCPA:LIBGENRE");
        main::sonos_mkcontainer ("RDCPA:MYRHAP", "object.container", "My Tracks", "RDCPA:LIBTRACKS");
        main::sonos_mkcontainer ("RDCPA:MYRHAP", "object.container", "My Playlists", "RDCPA:LIBPLAYLISTS");
    }

    main::sonos_mkcontainer ("RDCPA:GNRCHARTS", "object.container", "Top Artists", "RDCPA:GNRTOPARTIST");
    main::sonos_mkcontainer ("RDCPA:GNRCHARTS", "object.container", "Top Albums", "RDCPA:GNRTOPALBUM");
    main::sonos_mkcontainer ("RDCPA:GNRCHARTS", "object.container", "Top Tracks", "RDCPA:GNRTOPTRACK");

    if ($main::PREFS{Rhapsody}->{menabled}) {
        main::sonos_mkcontainer ("RDCPA:RHAPRECOMMEND", "object.container", "Albums For You", "RDCPA:ALBUMSFORYOU");
    }
    main::sonos_mkcontainer ("RDCPA:RHAPRECOMMEND", "object.container", "Featured Playlists", "RDCPA:FEATPLAYLISTS");
    main::sonos_mkcontainer ("RDCPA:RHAPRECOMMEND", "object.container", "Staff Picks", "RDCPA:STAFFPICKS");

}

###############################################################################
sub del_top_containers {
    return if (!$Plugins::Rhapsody::createdTop);

    $Plugins::Rhapsody::createdTop = 0;

    @{$main::CONTAINERS{""}} = grep ($_->{id} !~ /^RDCP/, @{$main::CONTAINERS{""}});
    delete $main::CONTAINERS{"RDCPA:MYRHAP"};
    delete $main::CONTAINERS{"RDCPA:RHAPRECOMMEND"};
    delete $main::CONTAINERS{"RDCPA:GNRCHARTS"};
}

###############################################################################
sub quit {
}

###############################################################################
sub container {
    my ($what, $name) = @_;

    my $i = 1;
    my $tree;


#Only cache items for 12 hours
    if ((exists $Plugins::Rhapsody::CONTAINERS{$name}) && 
        ((time() - $Plugins::Rhapsody::CONTAINERS{$name}) > 12*60*60)) {

        delete $main::CONTAINERS{$name};
    }


    return undef if (exists $main::CONTAINERS{$name});

    my $startnum = 0;
    my $endnum = 500;
    my $type = $name;
    my $id = "";

    if ((my $semicolon = rindex($type, ";")) != -1) {
        $startnum = int(substr($type, $semicolon+1));
        $endnum = $startnum+500;
        $type = substr($type, 0, $semicolon);
    }

    my $start = SOAP::Data->name("start")->value($startnum)->type("");
    my $end = SOAP::Data->name("end")->value($endnum)->type("");

    $Plugins::Rhapsody::CONTAINERS{$name} = time();
    if ((my $colon = rindex($type, ":")) != 5) {
        $id = substr($type, $colon+1);
        $type = substr($type, 0, $colon+1);
    }


    if ($name eq "RDCPA:GNRTOPARTIST") {
        $tree = SOAP::Lite
          -> proxy($Plugins::Rhapsody::metaurl)
          -> uri('urn:kani')
          -> getTopArtists($start, $end, $Plugins::Rhapsody::cobrandId, $Plugins::Rhapsody::filterRightsKey)
          -> result;

        foreach my $artist (@{$tree->{artists}}) {
            main::sonos_mkcontainer($name, "object.container.person.musicArtist", "$i. ". decode_entities($artist->{name}), "RDCPA:GLBARTIST:" . $artist->{artistId}, "x-rincon-cpcontainer:RDCPA:GLBARTIST:" . $artist->{artistId});
            $i++;
        }
    } elsif ($name eq "RDCPA:GNRTOPALBUM") {
        $tree = SOAP::Lite
          -> proxy($Plugins::Rhapsody::metaurl)
          -> uri('urn:kani')
          -> getTopAlbums($start, $end, $Plugins::Rhapsody::cobrandId, $Plugins::Rhapsody::filterRightsKey)
          -> result;

        foreach my $album (@{$tree->{albums}}) {
            main::sonos_mkcontainer($name, "object.container.album.musicAlbum", "$i. ". decode_entities($album->{displayName}), "RDCPA:GLBALBUM:" . $album->{albumId}, "x-rincon-cpcontainer:RDCPA:GLBALBUM:" . $album->{albumId});
            $i++;

        }

    } elsif ($name eq "RDCPA:GNRTOPTRACK") {
        $tree = SOAP::Lite
          -> proxy($Plugins::Rhapsody::metaurl)
          -> uri('urn:kani')
          -> getTopTracks($start, $end, $Plugins::Rhapsody::cobrandId, $Plugins::Rhapsody::filterRightsKey)
          -> result;

        foreach my $track (@{$tree->{tracks}}) {
            main::sonos_mkcontainer($name, "object.item.audioItem.musicTrack", "$i. ". decode_entities($track->{name}), "RDCPI:GLBTRACK:" . $track->{trackId}, "radea:" . $track->{trackId} . ".wma");
            $i++;

        }
    } elsif ($type eq "RDCPA:GNRTOPARTIST:") {
        my $genreId = SOAP::Data->name("genreId")->value($id)->type("");
        $tree = SOAP::Lite
          -> proxy($Plugins::Rhapsody::metaurl)
          -> uri('urn:kani')
          -> getTopArtistsForGenre($genreId, $start, $end, $Plugins::Rhapsody::cobrandId, $Plugins::Rhapsody::filterRightsKey)
          -> result;

        foreach my $artist (@{$tree->{artists}}) {
            main::sonos_mkcontainer($name, "object.container.person.musicArtist", "$i. ". decode_entities($artist->{name}), "RDCPA:GLBARTIST:" . $artist->{artistId}, "x-rincon-cpcontainer:RDCPA:GLBARTIST:" . $artist->{artistId});
            $i++;
        }
    } elsif ($type eq "RDCPA:GNRTOPALBUM:") {
        my $genreId = SOAP::Data->name("genreId")->value($id)->type("");
        $tree = SOAP::Lite
          -> proxy($Plugins::Rhapsody::metaurl)
          -> uri('urn:kani')
          -> getTopAlbumsForGenre($genreId, $start, $end, $Plugins::Rhapsody::cobrandId, $Plugins::Rhapsody::filterRightsKey)
          -> result;

        foreach my $album (@{$tree->{albums}}) {
            main::sonos_mkcontainer($name, "object.container.album.musicAlbum", "$i. ". decode_entities($album->{displayName}), "RDCPA:GLBALBUM:" . $album->{albumId}, "x-rincon-cpcontainer:RDCPA:GLBALBUM:" . $album->{albumId});
            $i++;

        }

    } elsif ($type eq "RDCPA:GNRTOPTRACK:") {
        my $genreId = SOAP::Data->name("genreId")->value($id)->type("");
        $tree = SOAP::Lite
          -> proxy($Plugins::Rhapsody::metaurl)
          -> uri('urn:kani')
          -> getTopTracksForGenre($genreId, $start, $end, $Plugins::Rhapsody::cobrandId, $Plugins::Rhapsody::filterRightsKey)
          -> result;

        foreach my $track (@{$tree->{tracks}}) {
            main::sonos_mkcontainer($name, "object.item.audioItem.musicTrack", "$i. ". decode_entities($track->{name}), "RDCPI:GLBTRACK:" . $track->{trackId}, "radea:" . $track->{trackId} . ".wma");
            $i++;

        }
    } elsif ($type eq "RDCPA:ARTSAMPLER:") {
        my $artistId = SOAP::Data->name("artistId")->value($id)->type("");
        $tree = SOAP::Lite
          -> proxy($Plugins::Rhapsody::metaurl)
          -> uri('urn:kani')
          -> getTracksForArtistSampler($artistId, $start, $end, $Plugins::Rhapsody::cobrandId, $Plugins::Rhapsody::filterRightsKey)
          -> result;

        foreach my $track (@{$tree->{tracks}}) {
            main::sonos_mkcontainer($name, "object.item.audioItem.musicTrack", decode_entities($track->{name}), "RDCPI:GLBTRACK:" . $track->{trackId}, "radea:" . $track->{trackId} . ".wma");
        }
          
    } elsif ($type eq "RDCPA:ARTTOPTRACKS:") {
        my $artistId = SOAP::Data->name("artistId")->value($id)->type("");
        $tree = SOAP::Lite
          -> proxy($Plugins::Rhapsody::metaurl)
          -> uri('urn:kani')
          -> getTopTracksForArtist($artistId, $start, $end, $Plugins::Rhapsody::cobrandId, $Plugins::Rhapsody::filterRightsKey)
          -> result;

        foreach my $track (@{$tree->{tracks}}) {
            main::sonos_mkcontainer($name, "object.item.audioItem.musicTrack", "$i. ". decode_entities($track->{name}), "RDCPI:GLBTRACK:" . $track->{trackId}, "radea:" . $track->{trackId} . ".wma");
            $i++;
        }
          
    } elsif ($type eq "RDCPA:GLBARTIST:") {
        my $artistId = SOAP::Data->name("artistId")->value($id)->type("");
        $tree = SOAP::Lite
          -> proxy($Plugins::Rhapsody::metaurl)
          -> uri('urn:kani')
          -> getArtist($artistId, $Plugins::Rhapsody::developerKey, $Plugins::Rhapsody::cobrandId, $Plugins::Rhapsody::filterRightsKey)
          -> result;

        main::sonos_mkcontainer($name, "object.container.album.musicAlbum", "Top Tracks", "RDCPA:ARTSAMPLER:" . $tree->{artistId}, "x-rincon-cpcontainer:RDCPA:ARTSAMPLER:" . $tree->{artistId});

        main::sonos_mkcontainer($name, "object.container.album.musicAlbum", "Artist Sampler", "RDCPA:ARTTOPTRACKS:" . $tree->{artistId}, "x-rincon-cpcontainer:RDCPA:ARTTOPTRACKS:" . $tree->{artistId});

        foreach my $album (@{$tree->{albums}}) {
            main::sonos_mkcontainer($name, "object.container.album.musicAlbum", decode_entities($album->{displayName}), "RDCPA:GLBALBUM:" . $album->{albumId}, "x-rincon-cpcontainer:RDCPA:GLBALBUM:" . $album->{albumId});

        }
    } elsif ($type eq "RDCPA:GLBALBUM:") {
        my $albumId = SOAP::Data->name("albumId")->value($id)->type("");
        $tree = SOAP::Lite
          -> proxy($Plugins::Rhapsody::metaurl)
          -> uri('urn:kani')
          -> getAlbum($albumId, $Plugins::Rhapsody::developerKey, $Plugins::Rhapsody::cobrandId, $Plugins::Rhapsody::filterRightsKey)
          -> result;

        foreach my $track (@{$tree->{trackMetadatas}}) {
            main::sonos_mkcontainer($name, "object.item.audioItem.musicTrack", decode_entities($track->{name}), "RDCPI:GLBTRACK:" . $track->{trackId}, "radea:" . $track->{trackId} . ".wma");
        }
    } elsif ($name eq "RDCPA:GLBGENRES") {
        $tree = SOAP::Lite
          -> proxy($Plugins::Rhapsody::metaurl)
          -> uri('urn:kani')
          -> getRootGenre($Plugins::Rhapsody::cobrandId, $Plugins::Rhapsody::filterRightsKey)
          -> result;

        foreach my $genre (@{$tree->{childGenres}}) {
            main::sonos_mkcontainer($name, "object.container.genre.musicGenre", decode_entities($genre->{name}), "RDCPA:GLBSUBGENRE:" . $genre->{genreId});
        }
    } elsif ($type eq "RDCPA:GLBSUBGENRE:") {
        my $genreId = SOAP::Data->name("genreId")->value($id)->type("");
        $tree = SOAP::Lite
          -> proxy($Plugins::Rhapsody::metaurl)
          -> uri('urn:kani')
          -> getGenre($genreId, $Plugins::Rhapsody::cobrandId, $Plugins::Rhapsody::filterRightsKey)
          -> result;

        main::sonos_mkcontainer($name, "object.container", "All Artists", "RDCPA:SUBGNRALLARTISTS:$id");
        main::sonos_mkcontainer($name, "object.container", "Charts", "RDCPA:GNRCHARTS:$id");
        main::sonos_mkcontainer($name, "object.container", "Key Artists", "RDCPA:SUBGNRKEYARTISTS:$id");
        main::sonos_mkcontainer($name, "object.container", "Key Albums", "RDCPA:SUBGNRKEYALBUMS:$id");
        main::sonos_mkcontainer($name, "object.container", "Genre Sampler", "RDCPA:SUBGNRSAMPLER:$id");
        if ($tree->{subGenreCount} > 0) {
            main::sonos_mkcontainer($name, "object.container", "Subgenres", "RDCPA:GLBLEAFGENRE:$id");
            foreach my $genre (@{$tree->{childGenres}}) {
                main::sonos_mkcontainer ("RDCPA:GLBLEAFGENRE:$id", "object.container.genre.musicGenre", decode_entities($genre->{displayName}), "RDCPA:GLBSUBGENRE:" . $genre->{genreId});
            }
        }

        main::sonos_mkcontainer ("RDCPA:GNRCHARTS:$id", "object.container", "Top Artists", "RDCPA:GNRTOPARTIST:$id");
        main::sonos_mkcontainer ("RDCPA:GNRCHARTS:$id", "object.container", "Top Albums", "RDCPA:GNRTOPALBUM:$id");
        main::sonos_mkcontainer ("RDCPA:GNRCHARTS:$id", "object.container", "Top Tracks", "RDCPA:GNRTOPTRACK:$id");
    } elsif ($name eq "RDCPA:GLBSTATIONS") {
        $tree = SOAP::Lite
          -> proxy($Plugins::Rhapsody::metaurl)
          -> uri('urn:kani')
          -> getProgrammedStations($start, $end, $Plugins::Rhapsody::cobrandId, $Plugins::Rhapsody::filterRightsKey)
          -> result;

        foreach my $station (@{$tree->{stations}}) {

            main::sonos_mkcontainer($name, "object.item.audioItem.audioBroadcast", decode_entities($station->{name}), "RDCPI:GLBSTATION:" . $station->{stationId}, "rdradio:station:" . $station->{stationId});
        }
    } elsif ($type eq "RDCPA:SUBGNRALLARTISTS:") {
        my $genreId = SOAP::Data->name("genreId")->value($id)->type("");
        $tree = SOAP::Lite
          -> proxy($Plugins::Rhapsody::metaurl)
          -> uri('urn:kani')
          -> getArtistsForGenreByPriority($genreId, $Plugins::Rhapsody::priority, $start, $end, $Plugins::Rhapsody::developerKey, $Plugins::Rhapsody::cobrandId, $Plugins::Rhapsody::filterRightsKey)
          -> result;

        if ($startnum > 0) {
            main::sonos_mkcontainer($name, "object.container", "--- Previous Page ---", "$type$id;" . ($startnum - 500));
        }

        foreach my $artist (@{$tree->{artists}}) {
            main::sonos_mkcontainer($name, "object.container.person.musicArtist", decode_entities($artist->{name}), "RDCPA:GLBARTIST:" . $artist->{artistId}, "x-rincon-cpcontainer:RDCPA:GLBARTIST:" . $artist->{artistId});
        }

        if ($endnum < $tree->{fullArraySize}) {
            main::sonos_mkcontainer($name, "object.container", "--- Next Page ---", "$type$id;$endnum");
        }
    } elsif ($type eq "RDCPA:SUBGNRKEYARTISTS:") {
        my $genreId = SOAP::Data->name("genreId")->value($id)->type("");
        $tree = SOAP::Lite
          -> proxy($Plugins::Rhapsody::metaurl)
          -> uri('urn:kani')
          -> getKeyArtistsForGenre($genreId, $start, $end, $Plugins::Rhapsody::cobrandId, $Plugins::Rhapsody::filterRightsKey)
          -> result;

        foreach my $artist (@{$tree->{artists}}) {
            main::sonos_mkcontainer($name, "object.container.person.musicArtist", decode_entities($artist->{name}), "RDCPA:GLBARTIST:" . $artist->{artistId}, "x-rincon-cpcontainer:RDCPA:GLBARTIST:" . $artist->{artistId});
        }
    } elsif ($type eq "RDCPA:SUBGNRKEYALBUMS:") {
        my $genreId = SOAP::Data->name("genreId")->value($id)->type("");
        $tree = SOAP::Lite
          -> proxy($Plugins::Rhapsody::metaurl)
          -> uri('urn:kani')
          -> getKeyAlbumsForGenre($genreId, $start, $end, $Plugins::Rhapsody::cobrandId, $Plugins::Rhapsody::filterRightsKey)
          -> result;

        foreach my $album (@{$tree->{albums}}) {
            main::sonos_mkcontainer($name, "object.container.album.musicAlbum", decode_entities($album->{displayName}), "RDCPA:GLBALBUM:" . $album->{albumId}, "x-rincon-cpcontainer:RDCPA:GLBALBUM:" . $album->{albumId});
        }
    } elsif ($type eq "RDCPA:SUBGNRSAMPLER:") {
        my $genreId = SOAP::Data->name("genreId")->value($id)->type("");
        $tree = SOAP::Lite
          -> proxy($Plugins::Rhapsody::metaurl)
          -> uri('urn:kani')
          -> getTracksForGenreSampler($genreId, $start, $end, $Plugins::Rhapsody::cobrandId, $Plugins::Rhapsody::filterRightsKey)
          -> result;
        foreach my $track (@{$tree->{tracks}}) {
            main::sonos_mkcontainer($name, "object.item.audioItem.musicTrack", decode_entities($track->{name}), "RDCPI:GLBTRACK:" . $track->{trackId}, "radea:" . $track->{trackId} . ".wma");
        }
    } elsif ($type eq "RDCPA:STAFFPICKS") {
        $tree = SOAP::Lite
          -> proxy($Plugins::Rhapsody::metaurl)
          -> uri('urn:kani')
          -> getArtistsForStaffPicks($start, $end, $Plugins::Rhapsody::cobrandId, $Plugins::Rhapsody::filterRightsKey)
          -> result;

        foreach my $artist (@{$tree->{artists}}) {
            main::sonos_mkcontainer($name, "object.container.person.musicArtist", decode_entities($artist->{name}), "RDCPA:STAFFPICKS:" . $artist->{artistId}, "x-rincon-cpcontainer:RDCPA:STAFFPICKS:" . $artist->{artistId});
        }
    } elsif ($type eq "RDCPA:STAFFPICKS:") {
        my $artistId = SOAP::Data->name("artistId")->value($id)->type("");
        $tree = SOAP::Lite
          -> proxy($Plugins::Rhapsody::metaurl)
          -> uri('urn:kani')
          -> getStaffPicksForArtist($artistId, $start, $end, $Plugins::Rhapsody::cobrandId, $Plugins::Rhapsody::filterRightsKey)
          -> result;

        foreach my $album (@{$tree->{albums}}) {
            main::sonos_mkcontainer($name, "object.container.album.musicAlbum", decode_entities($album->{displayName}), "RDCPA:GLBALBUM:" . $album->{albumId}, "x-rincon-cpcontainer:RDCPA:GLBALBUM:" . $album->{albumId});

        }
    } elsif ($type eq "RDCPA:NEWRELEASES") {
        $tree = SOAP::Lite
          -> proxy($Plugins::Rhapsody::metaurl)
          -> uri('urn:kani')
          -> getArtistsForNewReleases($start, $end, $Plugins::Rhapsody::cobrandId, $Plugins::Rhapsody::filterRightsKey)
          -> result;

        foreach my $artist (@{$tree->{artists}}) {
            main::sonos_mkcontainer($name, "object.container.person.musicArtist", decode_entities($artist->{name}), "RDCPA:NEWRELEASES:" . $artist->{artistId}, "x-rincon-cpcontainer:RDCPA:NEWRELEASES:" . $artist->{artistId});
        }
    } elsif ($type eq "RDCPA:NEWRELEASES:") {
        my $artistId = SOAP::Data->name("artistId")->value($id)->type("");
        $tree = SOAP::Lite
          -> proxy($Plugins::Rhapsody::metaurl)
          -> uri('urn:kani')
          -> getNewReleasesForArtist($artistId, $start, $end, $Plugins::Rhapsody::cobrandId, $Plugins::Rhapsody::filterRightsKey)
          -> result;

        foreach my $album (@{$tree->{albums}}) {
            main::sonos_mkcontainer($name, "object.container.album.musicAlbum", decode_entities($album->{displayName}), "RDCPA:GLBALBUM:" . $album->{albumId}, "x-rincon-cpcontainer:RDCPA:GLBALBUM:" . $album->{albumId});

        }
    } elsif ($type eq "RDCPA:FEATPLAYLISTS") {
        $tree = SOAP::Lite
          -> proxy($Plugins::Rhapsody::metaurl)
          -> uri('urn:kani')
          -> getFeaturedPlaylists()
          -> result;

        foreach my $playlist (@{$tree->{playlists}}) {
            main::sonos_mkcontainer($name, "object.container.playlist", decode_entities($playlist->{name}), "RDCPA:GLBPLAYLIST:" . $playlist->{playlistId}, "x-rincon-cpcontainer:RDCPA:GLBPLAYLIST:" . $playlist->{playlistId});

        }
    } elsif ($type eq "RDCPA:GLBPLAYLIST:") {
        my $playlistId = SOAP::Data->name("playlistId")->value($id)->type("");
        $tree = SOAP::Lite
          -> proxy($Plugins::Rhapsody::metaurl)
          -> uri('urn:kani')
          -> getTracksForPlaylist($playlistId, $start, $end, $Plugins::Rhapsody::cobrandId, $Plugins::Rhapsody::filterRightsKey)
          -> result;

        foreach my $track (@{$tree->{tracks}}) {
            main::sonos_mkcontainer($name, "object.item.audioItem.musicTrack", decode_entities($track->{name}), "RDCPI:GLBTRACK:" . $track->{trackId}, "radea:" . $track->{trackId} . ".wma");
        }

    } elsif ($type eq "RDCPA:LIBGENRE") {
        $tree = SOAP::Lite
          -> proxy($Plugins::Rhapsody::liburl)
          -> uri('urn:kani')
          -> getGenresInLibrary($Plugins::Rhapsody::logon, $Plugins::Rhapsody::cobrandId, $Plugins::Rhapsody::password, $start, $end, $Plugins::Rhapsody::developerKey)
          -> result;

        foreach my $genre (@{$tree->{genres}}) {
            main::sonos_mkcontainer ($name, "object.container.genre.musicGenre", decode_entities($genre->{name}), "RDCPA:LIBGENRE:" . $genre->{genreId});
        }
    } elsif ($type eq "RDCPA:LIBGENRE:") {
        my $genreId = SOAP::Data->name("genreId")->value($id)->type("");
        $tree = SOAP::Lite
          -> proxy($Plugins::Rhapsody::liburl)
          -> uri('urn:kani')
          -> getArtistsForGenreInLibrary($Plugins::Rhapsody::logon, $Plugins::Rhapsody::cobrandId, $Plugins::Rhapsody::password, $genreId, $start, $end, $Plugins::Rhapsody::developerKey)
          -> result;

        foreach my $artist (@{$tree->{artists}}) {
            main::sonos_mkcontainer($name, "object.container.person.musicArtist", decode_entities($artist->{name}), "RDCPA:LIBARTIST:" . $artist->{artistId}, "x-rincon-cpcontainer:RDCPA:LIBARTIST:" . $artist->{artistId});
        }

    } elsif ($type eq "RDCPA:LIBARTIST") {
        $tree = SOAP::Lite
          -> proxy($Plugins::Rhapsody::liburl)
          -> uri('urn:kani')
          -> getArtistsInLibrary($Plugins::Rhapsody::logon, $Plugins::Rhapsody::cobrandId, $Plugins::Rhapsody::password, $start, $end, $Plugins::Rhapsody::developerKey)
          -> result;

        foreach my $artist (@{$tree->{artists}}) {
            main::sonos_mkcontainer($name, "object.container.person.musicArtist", decode_entities($artist->{name}), "RDCPA:LIBARTIST:" . $artist->{artistId}, "x-rincon-cpcontainer:RDCPA:LIBARTIST:" . $artist->{artistId});
        }
    } elsif ($type eq "RDCPA:LIBARTIST:") {
        my $artistId = SOAP::Data->name("artistId")->value($id)->type("");
        $tree = SOAP::Lite
          -> proxy($Plugins::Rhapsody::liburl)
          -> uri('urn:kani')
          -> getAlbumsForArtistInLibrary($Plugins::Rhapsody::logon, $Plugins::Rhapsody::cobrandId, $Plugins::Rhapsody::password, $artistId, $start, $end, $Plugins::Rhapsody::developerKey)
          -> result;

        foreach my $album (@{$tree->{albums}}) {
            main::sonos_mkcontainer($name, "object.container.album.musicAlbum", decode_entities($album->{name}), "RDCPA:LIBALBUM:" . $album->{albumId}, "x-rincon-cpcontainer:RDCPA:LIBALBUM:" . $album->{albumId});

        }
    } elsif ($type eq "RDCPA:LIBALBUM") {
        $tree = SOAP::Lite
          -> proxy($Plugins::Rhapsody::liburl)
          -> uri('urn:kani')
          -> getAlbumsInLibrary($Plugins::Rhapsody::logon, $Plugins::Rhapsody::cobrandId, $Plugins::Rhapsody::password, $start, $end, $Plugins::Rhapsody::developerKey)
          -> result;

        foreach my $album (@{$tree->{albums}}) {
            main::sonos_mkcontainer($name, "object.container.album.musicAlbum", decode_entities($album->{name}), "RDCPA:LIBALBUM:" . $album->{albumId}, "x-rincon-cpcontainer:RDCPA:LIBALBUM:" . $album->{albumId});

        }
    } elsif ($type eq "RDCPA:LIBALBUM:") {
        my $albumId = SOAP::Data->name("albumId")->value($id)->type("");
        $tree = SOAP::Lite
          -> proxy($Plugins::Rhapsody::liburl)
          -> uri('urn:kani')
          -> getTracksForAlbumInLibrary($Plugins::Rhapsody::logon, $Plugins::Rhapsody::cobrandId, $Plugins::Rhapsody::password, $albumId, $start, $end, $Plugins::Rhapsody::developerKey)
          -> result;

        foreach my $track (@{$tree->{tracks}}) {
            main::sonos_mkcontainer($name, "object.item.audioItem.musicTrack", decode_entities($track->{name}), "RDCPI:GLBTRACK:" . $track->{trackId}, "radea:" . $track->{trackId} . ".wma");
        }
    } elsif ($type eq "RDCPA:LIBTRACKS") {
        $tree = SOAP::Lite
          -> proxy($Plugins::Rhapsody::liburl)
          -> uri('urn:kani')
          -> getTracksInLibrary($Plugins::Rhapsody::logon, $Plugins::Rhapsody::cobrandId, $Plugins::Rhapsody::password, $start, $end, $Plugins::Rhapsody::developerKey)
          -> result;

        foreach my $track (@{$tree->{tracks}}) {
            main::sonos_mkcontainer($name, "object.item.audioItem.musicTrack", decode_entities($track->{name}), "RDCPI:GLBTRACK:" . $track->{trackId}, "radea:" . $track->{trackId} . ".wma");
        }
    } elsif ($type eq "RDCPA:LIBPLAYLISTS") {
        $tree = SOAP::Lite
          -> proxy($Plugins::Rhapsody::liburl)
          -> uri('urn:kani')
          -> getPlaylistsInLibrary($Plugins::Rhapsody::logon, $Plugins::Rhapsody::cobrandId, $Plugins::Rhapsody::password, $start, $end, $Plugins::Rhapsody::developerKey)
          -> result;

        foreach my $playlist (@{$tree->{playlists}}) {
            main::sonos_mkcontainer($name, "object.container.playlist", decode_entities($playlist->{name}), "RDCPA:GLBPLAYLIST:" . $playlist->{playlistId}, "x-rincon-cpcontainer:RDCPA:GLBPLAYLIST:" . $playlist->{playlistId});

        }
    } elsif ($type eq "RDCPA:ALBUMSFORYOU") {
        $tree = SOAP::Lite
          -> proxy($Plugins::Rhapsody::liburl)
          -> uri('urn:kani')
          -> getAlbumsForYou($Plugins::Rhapsody::logon, $Plugins::Rhapsody::cobrandId, $Plugins::Rhapsody::password, $Plugins::Rhapsody::developerKey)
          -> result;

        foreach my $album (@{$tree->{albums}}) {
            main::sonos_mkcontainer($name, "object.container.album.musicAlbum", decode_entities($album->{name}), "RDCPA:GLBALBUM:" . $album->{albumId}, "x-rincon-cpcontainer:RDCPA:GLBALBUM:" . $album->{albumId});

        }

    } else {
        main::Log (1, "Unknown container $name\n");
        return undef;
    }

    main::Log (4, Dumper($tree)) if (main::isLog(4));

    return undef;
}

###############################################################################
sub item {
    my ($what, $name) = @_;

    my $tree;
    if ($name =~ /^RDCPA:ARTSAMPLER:(.*)/) {
        my $artistId = $1;
        main::sonos_mkitem ("RDCPA:GLBARTIST:$1", "object.container.album.musicAlbum", "Artist Sampler", $name, "x-rincon-cpcontainer:$name");
    } elsif ($name =~ /^RDCPA:ARTTOPTRACKS:(.*)/) {
        main::sonos_mkitem ("RDCPA:GLBARTIST:$1", "object.container.album.musicAlbum", "Top Tracks", $name, "x-rincon-cpcontainer:$name");

    } elsif ($name =~ /^RDCPA:GLBARTIST:(.*)/) {
        my $artistId = SOAP::Data->name("artistId")->value($1)->type("");
        $tree = SOAP::Lite
          -> proxy($Plugins::Rhapsody::metaurl)
          -> uri('urn:kani')
          -> getArtist($artistId, $Plugins::Rhapsody::developerKey, $Plugins::Rhapsody::cobrandId, $Plugins::Rhapsody::filterRightsKey)
          -> result;

        main::sonos_mkitem ("", "object.container.person.musicArtist", decode_entities($tree->{name}), $name, "x-rincon-cpcontainer:RDCPA:GLBARTIST:" . $tree->{artistId});

    } elsif ($name =~ /^RDCPA:GLBALBUM:(.*)/) {
        my $albumId = SOAP::Data->name("albumId")->value($1)->type("");
        $tree = SOAP::Lite
          -> proxy($Plugins::Rhapsody::metaurl)
          -> uri('urn:kani')
          -> getAlbum($albumId, $Plugins::Rhapsody::developerKey, $Plugins::Rhapsody::cobrandId, $Plugins::Rhapsody::filterRightsKey)
          -> result;

        main::sonos_mkitem ("", "object.container.album.musicAlbum", decode_entities($tree->{displayName}), $name, "x-rincon-cpcontainer:RDCPA:GLBALBUM:" . $tree->{albumId});

    } elsif ($name =~/^RDCPI:GLBTRACK:(.*)/) {
        my $trackId = SOAP::Data->name("trackId")->value($1)->type("");
        $tree = SOAP::Lite
          -> proxy($Plugins::Rhapsody::metaurl)
          -> uri('urn:kani')
          -> getTrack($trackId, $Plugins::Rhapsody::developerKey, $Plugins::Rhapsody::cobrandId, $Plugins::Rhapsody::filterRightsKey)
          -> result;

        main::sonos_mkitem ("RDCPA:GLBALBUM:" . $tree->{albumId}, "object.item.audioItem.musictrack", decode_entities($tree->{name}), $name, "radea:" . $tree->{trackId} . ".wma");

    } elsif ($name =~ /^RDCPA:GLBPLAYLIST:(.*)/) {
        my $playlistId = SOAP::Data->name("playlistId")->value($1)->type("");
        my $start = SOAP::Data->name("start")->value("0")->type("");
        my $end = SOAP::Data->name("end")->value("100")->type("");
        $tree = SOAP::Lite
          -> proxy($Plugins::Rhapsody::metaurl)
          -> uri('urn:kani')
          -> getTracksForPlaylist($playlistId, $start, $end, $Plugins::Rhapsody::cobrandId, $Plugins::Rhapsody::filterRightsKey)
          -> result;

        main::sonos_mkitem ("", "object.container.playlist", decode_entities($tree->{name}), $name, "x-rincon-cpcontainer:RDCPA:GLBPLAYLIST:" . $tree->{playlistId});

    } else {
        main::Log (1, "Unknown item $name\n");
        return undef;
    }

    main::Log (4, Dumper($tree)) if (main::isLog(4));

    return undef;
}
###############################################################################
sub meta {
    my ($what, $name, $entry) = @_;

# Not ready yet, only do this for rhapsody items
    if (0==1 && $what eq "META_SQ") {
        main::Log(2,"Rhapsody item queued from Sonos playlist - massaging data...");
        $what = 'META_RDCPI';
        my $newID = "RDCPI:GLBTRACK:". $entry->{res}->{content};
        $newID =~ s/radea://;   # Strip out "radea:"
        $newID =~ s/\....$//;   # Strip of 3-letter extension
        main::Log(2, "Changing '$entry->{id}' and '$name' to '$newID'"); 
        $entry->{id} = $newID;
        $name = $newID;
    }

    my $metadata = '&lt;DIDL-Lite xmlns:dc=&quot;http://purl.org/dc/elements/1.1/&quot; xmlns:upnp=&quot;urn:schemas-upnp-org:metadata-1-0/upnp/&quot; xmlns:r=&quot;urn:schemas-rinconnetworks-com:metadata-1-0/&quot; xmlns=&quot;urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/&quot;&gt;&lt;item id=&quot;' . $entry->{id} . '&quot; parentID=&quot;' . $entry->{parentID} . '&quot; restricted=&quot;true&quot;&gt;&lt;dc:title&gt;'. $entry->{"dc:title"} .  '&lt;/dc:title&gt;&lt;upnp:class&gt;';

    if ($what eq "META_RDCPI") {
        $metadata .= 'object.item.audioItem.musicTrack';
    } elsif ($name =~ /^RDCPA:GLBPLAYLIST/) {
        $metadata .= 'object.container';
    } else {
        $metadata .= 'object.container.album.musicAlbum';
    }
    $metadata .= '&lt;/upnp:class&gt;&lt;desc id=&quot;cdudn&quot; nameSpace=&quot;urn:schemas-rinconnetworks-com:metadata-1-0/&quot;&gt;' . $main::SERVICES{Rhapsody}->{UDN} . '&lt;/desc&gt;&lt;/item&gt;&lt;/DIDL-Lite&gt;';

    return decode_entities($metadata);
}
###############################################################################
sub search {
    my ($what, $zone, $results, $search, $maxsearch, $searchartist, $searchalbum, $searchsong) = @_;

    return if (!$main::PREFS{Rhapsody}->{senabled});

    my $url = "http://realsearch.real.com/search/?searchtype=RhapKeyword&query=" . $search . "&size=150&availability=Stream";
    my $response = $Plugins::Rhapsody::userAgent->get($url);

    if (!$response->is_success()) {
        main::Log(2, "Rhapsody search failed: ". Dumper($response));
        return undef;
    }
    my $content = $response->content;
    my $tree = XMLin($content, forcearray => ["artist", "album", "track"],
                               keyattr=>{"search-results"   => "searchcode"});

    main::Log (4, Dumper($tree)) if (main::isLog(4));

    if ($searchartist) {
        foreach my $artist (@{$tree->{"search-results"}->{artist}->{artists}->{artist}}) {
            last if (scalar @{$results} > $maxsearch);
            my %data;
            $data{MUSIC_ISSONG} = 0;
            $data{MUSIC_NAME} = encode_entities($artist->{"display-name"});
            $data{MUSIC_PATH} = uri_escape("RDCPA:GLBARTIST:Art." . $artist->{"artist-id"});
            if (defined $zone) {
                $data{MUSIC_ARG} = "zone=" . uri_escape($zone) . 
                                      "&amp;mpath=" . $data{MUSIC_PATH};
            }
            $data{MUSIC_ICON} = "/artist.gif";
            push(@{$results}, \%data);
        }
    }

    if ($searchalbum) {
        foreach my $album (@{$tree->{"search-results"}->{album}->{albums}->{album}}) {
            last if (scalar @{$results} > $maxsearch);
            my %data;
            $data{MUSIC_ISSONG} = 0;
            $data{MUSIC_NAME} = encode_entities($album->{"display-name"} . " - " . $album->{"artist-name"});
            $data{MUSIC_PATH} = uri_escape("RDCPA:GLBALBUM:Alb." . $album->{"album-content-id"});
            if (defined $zone) {
                $data{MUSIC_ARG} = "zone=" . uri_escape($zone) . 
                                      "&amp;mpath=" . $data{MUSIC_PATH};
            }
            $data{MUSIC_ICON} = "/album.gif";
            push(@{$results}, \%data);
        }
    }

    if ($searchsong) {
        foreach my $track (@{$tree->{"search-results"}->{track}->{tracks}->{track}}) {
            last if (scalar @{$results} > $maxsearch);
            my %data;
            $data{MUSIC_ISSONG} = 1;
            $data{MUSIC_NAME} = encode_entities($track->{"display-name"} . " - " . $track->{"album-title"} . " - " . $track->{"artist-name"});
            $data{MUSIC_PATH} = uri_escape("RDCPI:GLBTRACK:Tra." . $track->{"content-id"});
            if (defined $zone) {
                $data{MUSIC_ARG} = "zone=" . uri_escape($zone) . 
                                      "&amp;mpath=" . $data{MUSIC_PATH};
            }
            $data{MUSIC_ICON} = "/song.gif";
            push(@{$results}, \%data);
        }
    }

    return undef;
}

###############################################################################
sub html {
    my ($c, $r, $diskpath, $template) = @_;

    $template->param("RHAPSODY_CONFIGED" => exists $main::SERVICES{Rhapsody});
    $template->param("RHAPSODY_SENABLED" => "checked") if ($main::PREFS{Rhapsody}->{senabled});
    $template->param("RHAPSODY_BENABLED" => "checked") if ($main::PREFS{Rhapsody}->{benabled});
    $template->param("RHAPSODY_MENABLED" => "checked") if ($main::PREFS{Rhapsody}->{menabled});

    undef $Plugins::Rhapsody::Err;
}

###############################################################################
sub index {
    my ($c, $r) = @_;

    my %qf = $r->uri->query_form;

    $main::PREFS{Rhapsody}->{benabled} = defined $qf{benabled};
    $main::PREFS{Rhapsody}->{senabled} = defined $qf{senabled};
    $main::PREFS{Rhapsody}->{menabled} = defined $qf{menabled};
    main::sonos_prefsdb_save();

    if ($main::PREFS{Rhapsody}->{benabled}) {
        del_top_containers();
        add_top_containers();
    }
    $c->send_redirect(main::http_base_url($r) . "/Rhapsody/index.html", HTTP::Status::RC_MOVED_TEMPORARILY);
    $c->force_last_request;
}

1;
