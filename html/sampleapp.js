/* Sample Sonos JS App. 
 * sonos.js must be included before this file
 *
 * It makes some big assumptions how things will be done.
 * Of course you don't have to use this to write your app.
 *
 */

var app = {};

function updateText(name, text) {
    var element = document.getElementById(name);
    if (element && (!element.innerHTML || element.innerHTML != text)) {
        element.innerHTML = text;
    }
}

function updateSrc(name, src) {
    var element = document.getElementById(name);
    if (!element) return;
    if (!src) {
        element.style.display = "none"
    } else {
        element.src = src
        element.style.display = "inline"
    }
}

function updateToggle(first, second, doFirst) {
    document.getElementById(first).style.display = (doFirst?"inline":"none");
    document.getElementById(second).style.display  = (doFirst?"none":"inline");
}

function start() {
    app.currentMusicPath = "";
    app.rootLastUpdate = 0;
    if (!app.removegif)
        alert("Must set app.removegif");
    if (!app.playgif)
        alert("Must set app.playgif");
    if (!app.addgif)
        alert("Must set app.addgif");
    sonos.start();
}

function setCurrentZone(zoneId) {
    if (app.currentZoneId && app.currentZoneId == zoneId) {
        return;
    }
    app.currentZoneId = zoneId;
    drawControl(zoneId);
    drawQueue(zoneId);
    drawZones();
}
function needZone() {
    if (!app.currentZoneId) {
        alert("Please select a Zone first.");
        return 1;
    }
    return 0
}

function doAction(action) {
    if (needZone()) return;
    sonos.sendControlAction(app.currentZoneId, action);
}

function doQAction(action, id) {
    if (needZone()) return;
    sonos.sendQueueAction(app.currentZoneId, action, id);
}

function doMAction(action, path) {
    if (needZone()) return;
    sonos.sendMusicAction(app.currentZoneId, action, path);
}

// Add Music - Add to the Q
function aM (num) {
    var item = sonos.music[app.currentMusicPath].items[num];
    return doMAction('AddMusic', item.path);
}

// Play Music - Replace the Q
function pM (num) {
    var item = sonos.music[app.currentMusicPath].items[num];
    return doMAction('PlayMusic', item.path);
}

// Browse To
function bT (num) {
    var item = sonos.music[app.currentMusicPath].items[num];
    return browseTo(item.path);
}

function doPlaylistDelete(path) {
    if (needZone()) return;
    if (confirm("Delete " + decodeURIComponent(path) + "?")) {
        sonos.sendMusicAction(app.currentZoneId, "DeleteMusic", path);
    }
}

function doSaveQ() {
    if (needZone()) return;
    var element = document.getElementById("savequeuename");
    if (element.value == "") {
        alert("Please enter a name");
        return;
    }
    sonos.sendSaveAction(app.currentZoneId, encodeURIComponent(element.value));
    element.value = "";
}

function doSearch(auto) {
    if (auto && !app.currentZoneId) {
        return; // Don't bug the user if this is a auto search
    }

    if (needZone()) return;

    var element = document.getElementById("msearch");
    if (element.value == "") {
        browseTo("");
        return;
    }

    var newPath = "Search: "+ encodeURIComponent(element.value);
    if(app.currentMusicPath == newPath) {
        return;
    }

    if (auto && element.value.length < 2) {
        return; // Don't auto search if 1 char, since could be slow
    }

    app.currentMusicPath = newPath;

    if (sonos.music[app.currentMusicPath]) {
        drawMusic(app.currentMusicPath);
    } else {
        sonos.sendMusicSearch(app.currentZoneId, encodeURIComponent(element.value));
    }
}

function browseTo(path) {
    if (needZone()) return;

    app.currentMusicPath = path;

    if (sonos.music[app.currentMusicPath]) {
        drawMusic(app.currentMusicPath);
    } else {
        sonos.sendMusicAction(app.currentZoneId, "Browse", app.currentMusicPath);
    }
}

function browseBack() {
    if (needZone()) return;
    if (sonos.music[app.currentMusicPath]) {
        browseTo(sonos.music[app.currentMusicPath].parent);
    }
}

function doLink(zone) {
    sonos.sendAction(app.currentZoneId, "Link", "&link="+zone);
}

function doUnlink(zone) {
    sonos.sendAction(app.currentZoneId, "Unlink", "&link="+zone);
}

function drawZones() {
    var str = "";
    for (i=0; i < sonos.zones.length; i++) {
        var zone = sonos.zones[i];
        if (app.currentZoneId == zone) str += "<B>";
        if (sonos[zone].linked) {
            str += "&nbsp; &nbsp;" + sonos[zone].zoneName;
            if (app.currentZoneId && app.currentZoneId != zone) {
                str += " <a class=ulink href=\"#\" onClick=\"doUnlink('"+zone+"')\">[U]</a>";
            }
            str += "<BR>\n";
        } else {
            str += "<A HREF=\"#\" onClick=\"setCurrentZone('" + sonos[zone].zoneId + "')\">" + sonos[zone].zoneName + "</A>";
            if (app.currentZoneId && app.currentZoneId != zone) {
                str += " <a class=ulink href=\"#\" onClick=\"doLink('"+zone+"')\">[L]</a></font>";
            }
            str += "<BR>\n";
        }
        if (app.currentZoneId == zone) str += "</B>";
    }
    str += "<P>";
    if (app.currentZoneId) {
        str += "<A HREF=\"#\" onClick=\"doAction('LinkAll')\">Party Mode</A><BR>\n";
    }
    str += "<hr><A HREF=\"/\" \">Home Page</A><BR>\n";
    updateText("zones", str);
}

function drawControl(zoneId) {
    if (app.currentZoneId != zoneId) {
        return;
    }

    var zone = sonos[zoneId];

    updateText('currentzonename', zone.zoneName);
    updateText('song', zone.song);
    updateText('album', zone.album);
    updateText('artist', zone.artist);
    updateText('tracknum', zone.trackNum);
    updateText('tracktot', zone.trackTot);
    updateToggle("pause", "play", zone.mode == 1);
    updateToggle("shuffleoff", "shuffleon", zone.shuffle);
    updateToggle("repeatoff", "repeaton", zone.repeat);
    updateToggle("muteoff", "muteon", zone.muted);
    updateText('volume', zone.volume);
    updateSrc('albumart', zone.albumArt);
}

function drawQueue(zoneId) {
    if (app.currentZoneId != zoneId) {
        return;
    }

    var str = new Array();
    for (i=0; i < sonos[app.currentZoneId].queue.length; i++) {
        var item = sonos[app.currentZoneId].queue[i];
        str.push("<A HREF=\"#\" onClick=\"doQAction('Remove', '" + item.id + "')\"><IMG SRC="+app.removegif + "></A>");
        str.push("<A HREF=\"#\" onClick=\"doQAction('Seek', '" + item.id + "')\">" + item.name + "</A><BR>");
    }
    updateText("queuedata", str.join(""));
}

function drawMusic(path) {
    if (path != app.currentMusicPath) {

        // Got a refresh for top, might mean we should refresh the screen
        if ((path == "") && !sonos.music[app.currentMusicPath]) {
            browseTo(app.currentMusicPath);
        }
        return;
    }

    var isPlaylist = (path.substr(0,3) == "SQ:");
    var isRadio = (path.substr(0,2) == "R:");

    if (path == "") {
        updateText("musicpath", "");
        document.getElementById("rootmusicdata").style.display = "inline";
        document.getElementById("musicdata").style.display     = "none";
        updateSrc('musicalbumart', "");
        if (app.rootLastUpdate == sonos.music[path].lastUpdate)
            return;
        app.rootLastUpdate = sonos.music[path].lastUpdate;
    } else {
        updateText("musicpath", decodeURIComponent(path));
        document.getElementById("rootmusicdata").style.display = "none";
        document.getElementById("musicdata").style.display     = "inline";
        updateSrc('musicalbumart', sonos.music[path].albumArt);
    }

    var str = new Array();

    for (i=0; i < sonos.music[path].items.length; i++) {
        var item = sonos.music[path].items[i];
        str.push("<img src=" + item.icon + "> ");
        if (path != "") {
            if (!isRadio) {
                str.push("<A HREF=\"#\" onClick=\"aM(" + i + ")\"><IMG SRC="+app.addgif+"></A>");
            }
            str.push("<A HREF=\"#\" onClick=\"pM(" + i + ")\"><IMG SRC="+app.playgif+"></A>");
            if (isPlaylist) {
                str.push("<A HREF=\"#\" onClick=\"doPlaylistDelete('" + encodeURIComponent(item.path) + "')\" ><IMG SRC="+app.removegif+"></A>");
            }
        }
        if (item.isSong) {
            str.push(item.name + "<BR>\n");
        } else {
            str.push("<A HREF=\"#\" onClick=\"bT(" + i + ")\" > ");
            str.push (item.name + "</A> <BR>\n");
        }
    }
    var text = str.join("");
    if (path == "") {
        updateText("rootmusicdata", text);
    } else {
        updateText("musicdata", text);
    }
}
