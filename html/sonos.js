// Public Functions
/* To use this script, 4 functions must be implemented
 *
 * drawZones()
 *    The available zones have changed.
 *    sonos.zones is an array of the zone ids
 *    sonos[zoneId] is an object with lots of info about the zone
 * 
 * drawControl(zoneId)
 *    The control data for a zone has changed
 *    sonos[zoneId] is an object with lots of info about the zone
 *
 * drawQueue(zoneId)
 *    The queue for a zone has changed
 *    sonos[zoneId].queue is an array of objects with info about the
 *    items in the queue
 *
 * drawMusic(path)
 *    A Music query has returned, path is "*Search*" for searches.
 *    sonos.music[path].items is an array of objects with info about the 
 *    music at the path location
 *
 */
 
var sonos = {};

sonos.start = function() {
    sonos.music = {};
    sonos._lastUpdate = 1;
    sonos._fetch();
}

sonos.sendAction = function(zoneId, action, other) {
    if (!other)
        other = "";
    sonos._loadData("/action.html?NoWait=1&action=" + action + "&zone=" + zoneId + other);
}

sonos.sendControlAction = function(zoneId, action) {
    sonos.sendAction(zoneId, action);
}

sonos.sendSaveAction = function(zoneId, name) {
    sonos.sendAction(zoneId, "Save", "&savename=" + name);
}

sonos.sendQueueAction = function(zoneId, action, id) {
    sonos.sendAction(zoneId, action, "&queue=" + id);
}

sonos.sendMusicAction = function(zoneId, action, path) {
    sonos.sendAction(zoneId, action, "&mpath=" + encodeURIComponent(path));
}

sonos.sendMusicSearch = function(zoneId, str) {
    sonos._loadData("/action.html?zone=" + zoneId + "&lastupdate="+sonos._lastUpdate + "&msearch="+str);
}

sonos.setVolume = function(zoneId, volume) {
    sonos.sendAction(zoneId, "SetVolume", "&volume=" + volume);
}


// Private Functions
sonos._loadData = function(filename, afterFunc) {
    Http.get(filename, function (data) {
        eval(data);
        if (afterFunc)
            eval(afterFunc);
    });
}

sonos._doFetch = function() {
    sonos._loadData("/data.html?action=Wait&lastupdate="+sonos._lastUpdate, "sonos._fetch();");
}

sonos._fetch = function() {
    window.setTimeout("sonos._doFetch();", 100);
}

sonos._setLastUpdate = function(lastUpdate) {
    sonos._lastUpdate = lastUpdate;
}

sonos._setZones = function() {
    if (sonos.zoneUpdate && sonos.zoneUpdate == arguments[0]) {
        return;
    }
    sonos.zoneUpdate = arguments[0];
    sonos.zones = new Array((arguments.length-1)/3);
    for (i=1, j=0; i < arguments.length; i+=3, j++) {
        sonos.zones[j] = arguments[i];
        sonos[arguments[i]] = {};
        sonos[arguments[i]].zoneId    = arguments[i];
        sonos[arguments[i]].zoneName  = arguments[i+1];
        sonos[arguments[i]].linked    = arguments[i+2];
    }
    drawZones();
}
sonos._startQueue = function(zoneId, lastUpdate) {
    sonos[zoneId].queue = new Array();
    sonos[zoneId]._queueLastUpdate = lastUpdate;
}

sonos._addQueue = function(zoneId, name, id) {
    var i = sonos[zoneId].queue.length;
    var obj = {};
    obj.name = name;
    obj.id = id;
    sonos[zoneId].queue[i] = obj;
}

sonos._finishQueue = function(zoneId) {
    drawQueue(zoneId, sonos[zoneId]._queueLastUpdate);
}

sonos._startMusic = function(path, lastUpdate, parent, albumArt) {
    // Refresh of top, drop the cache
    if (path == "") {
        sonos.music = {};
    }

    path = decodeURIComponent(path);
    sonos.music[path] = {};
    sonos.music[path].items = new Array();
    sonos.music[path].lastUpdate = lastUpdate;
    sonos.music[path].parent = decodeURIComponent(parent);
    sonos.music[path].albumArt = decodeURIComponent(albumArt);
}

sonos._addMusic = function(root, name, path, icon, isSong) {
    root = decodeURIComponent(root);

    var i = sonos.music[root].items.length;
    var obj = {};
    obj.name = name;
    obj.path = decodeURIComponent(path);
    obj.icon = icon;
    obj.isSong = isSong;
    sonos.music[root].items[i] = obj;
}

sonos._finishMusic = function(path) {
    drawMusic(decodeURIComponent(path));
}

sonos._setZoneInfo = function(zoneId, lastUpdate, volume, muted, mode, shuffle, repeat, isradio, trackNum, trackTot, song, album, artist, position, trackLen, albumArt) {
    if (sonos[zoneId] && sonos[zoneId]._lastUpdate == lastUpdate) {
        return;
    }

    sonos[zoneId]._lastUpdate  = lastUpdate;
    sonos[zoneId].volume      = volume;
    sonos[zoneId].muted       = muted;
    sonos[zoneId].mode        = mode;
    sonos[zoneId].shuffle     = shuffle;
    sonos[zoneId].repeat      = repeat;
    sonos[zoneId].isradio     = isradio;
    sonos[zoneId].trackNum    = trackNum;
    sonos[zoneId].trackTot    = trackTot;
    sonos[zoneId].song        = song;
    sonos[zoneId].album       = album;
    sonos[zoneId].artist      = artist;
    sonos[zoneId].position    = position;
    sonos[zoneId].trackLen    = trackLen;
    sonos[zoneId].albumArt    = albumArt;

    drawControl(zoneId);
}

