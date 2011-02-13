/*
 * Konfabulator support for Sonos is 8 easy steps :-) 
 *    (Yes I know this is kind of a pain)
 *
 * 1) Find a iTunes widget you want to use
 * 2) Make a copy of the widget to edit
 * 3) Change into the Contents directory under the widget
 *    a) On windows you have to first use winzip to extract the widget
 * 4) Do a global search and replace of iTunes. to iSonos. in all *.js and *.kon files
 * 5) Copy this file (iSonosStub.js) into the Contents directory
 * 6) Configure this file in the Config section below
 * 7) Edit the .kon file and look for a onLoad section
 *    a) If no onLoad section exists add the following in the file
         <action trigger="onLoad" file="iSonosStub.js"/>   
 *    b) If an onLoad section exists and has code add the follow as the first line
         include("iSonosStub.js");
 *    c) If an onLoad section exists and refers to a file, open that file and add
         include("iSonosStub.js");
 * 8) Now you can open the widget
 */

var iSonos = {};

/**** CONFIG BEGIN ****/
// Host Sonos Web Controller is running on
iSonos.host = "192.168.0.3";

// Port Sonos Web Controller is running on
iSonos.port = 8001;

// EXACT Name of Zone you want to control
iSonos.zone = "Family Room";

/**** CONFIG END ****/


/**** Load the JS that does everything ****/
var url = new URL();
url.fetch("http://" + iSonos.host + ":" + iSonos.port + "/iSonos.js");
if (url.response != 200) {
    alert ("Couldn't contact Sonos Web Controller Software.  iSonosStub.js probably needs to be updated.");
}
eval(url.result);
