import Toybox.Application.Storage;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

// Supplies the "current location" fix for Model.LOC_AUTO.
//
// Two passive sources cost nothing and are polled while the full view is
// open: the watch's last known position (Position.getInfo, which also
// reflects a GPS fix requested with START) and the phone's weather
// observation location (city level, which is all prayer times need; the
// desktop app uses IP geolocation for the same reason). Whichever is
// fresher wins, with the watch's own position preferred when the two are
// within an hour of each other, since it is the more precise of the two.
// A real GPS search is only started when the user asks for it (START in
// the full view), because it drains the battery and is slow indoors.
//
// The place name shown in the header comes from the weather observation
// when that is what we are using (or is nearby), otherwise from a reverse
// geocoding lookup through the phone (BigDataCloud, the same service the
// desktop app uses), cached against the coordinates it was resolved for.
class LocationProvider {

    // Weather station within this distance of the fix lends it its name.
    const NAME_REUSE_KM = 25.0d;
    // Coordinates this close share a geocoded name.
    const GEO_CACHE_KM = 2.0d;
    // Minimum gap between reverse geocoding attempts for the same spot.
    const GEO_RETRY_SECONDS = 600;

    var acquiring as Boolean = false;

    private var _geoPending as Boolean = false;
    private var _geoTryLat as Double? = null;
    private var _geoTryLon as Double? = null;
    private var _geoTryTime as Number = 0;

    // Refresh from passive sources. Returns true when the stored fix or its
    // name changed.
    function refreshPassive() as Boolean {
        var gpsPos = null;
        var gpsTime = 0;
        var pi = Position.getInfo();
        if (pi != null && pi.position != null && pi.accuracy != null
            && pi.accuracy >= Position.QUALITY_LAST_KNOWN) {
            gpsPos = pi.position;
            if (pi.when != null) { gpsTime = (pi.when as Time.Moment).value(); }
        }

        var wxPos = null;
        var wxTime = 0;
        var wxName = null;
        if (Toybox has :Weather) {
            try {
                var cc = Toybox.Weather.getCurrentConditions();
                if (cc != null && cc.observationLocationPosition != null) {
                    wxPos = cc.observationLocationPosition;
                    if (cc.observationTime != null) { wxTime = (cc.observationTime as Time.Moment).value(); }
                    var name = cc.observationLocationName;
                    if (name instanceof String && name.length() > 0) {
                        // "Ümraniye, İstanbul" -> "Ümraniye": one short label.
                        var comma = name.find(",");
                        if (comma != null && comma > 0) { name = name.substring(0, comma); }
                        wxName = name;
                    }
                }
            } catch (e) {
                // Weather unavailable on this device/firmware; fall through.
            }
        }

        if (gpsPos != null && (wxPos == null || gpsTime + 3600 >= wxTime)) {
            var name = null;
            if (wxPos != null && wxName != null) {
                var g = (gpsPos as Position.Location).toDegrees();
                var x = (wxPos as Position.Location).toDegrees();
                if (distanceKm(g[0].toDouble(), g[1].toDouble(), x[0].toDouble(), x[1].toDouble()) < NAME_REUSE_KM) {
                    name = wxName;
                }
            }
            return store(gpsPos as Position.Location, name);
        }
        if (wxPos != null) {
            return store(wxPos as Position.Location, wxName);
        }
        return false;
    }

    function startGps() as Void {
        if (acquiring) { return; }
        acquiring = true;
        Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, method(:onPosition));
    }

    function stopGps() as Void {
        if (!acquiring) { return; }
        acquiring = false;
        Position.enableLocationEvents(Position.LOCATION_DISABLE, method(:onPosition));
    }

    function onPosition(info as Position.Info) as Void {
        if (info.position == null) { return; }
        var accuracy = info.accuracy;
        if (accuracy == null || accuracy < Position.QUALITY_POOR) { return; }
        store(info.position as Position.Location, null);
        stopGps();
        WatchUi.requestUpdate();
    }

    // Equirectangular approximation, plenty for "is this the same town".
    private function distanceKm(lat1 as Double, lon1 as Double, lat2 as Double, lon2 as Double) as Double {
        var dLat = (lat2 - lat1) * 111.0d;
        var dLon = (lon2 - lon1) * 111.0d * Math.cos(lat1 * 0.017453292519943295d);
        return Math.sqrt(dLat * dLat + dLon * dLon);
    }

    // Persist a fix. Coordinates are rounded to ~100 m so that jitter does
    // not invalidate the schedule cache on every refresh. `name` is the
    // weather-derived name when applicable; otherwise the cached geocoded
    // name is used, or a lookup is started.
    private function store(pos as Position.Location, name as String?) as Boolean {
        var d = pos.toDegrees();
        var lat = Math.round(d[0].toDouble() * 1000.0d) / 1000.0d;
        var lon = Math.round(d[1].toDouble() * 1000.0d) / 1000.0d;
        if (lat.abs() > 90.0d || lon.abs() > 180.0d || (lat == 0.0d && lon == 0.0d)) {
            return false;
        }

        if (name == null) {
            name = cachedGeoName(lat, lon);
            if (name == null) { requestGeocode(lat, lon); }
        }

        var oldLat = Storage.getValue(Model.KEY_AUTO_LAT);
        var oldLon = Storage.getValue(Model.KEY_AUTO_LON);
        var oldName = Storage.getValue(Model.KEY_AUTO_NAME);
        var changed = !(oldLat instanceof Double && oldLon instanceof Double
                        && oldLat == lat && oldLon == lon);
        var nameChanged = !((oldName == null && name == null)
                            || (oldName instanceof String && name != null && oldName.equals(name)));
        if (!changed && !nameChanged) { return false; }
        Storage.setValue(Model.KEY_AUTO_LAT, lat);
        Storage.setValue(Model.KEY_AUTO_LON, lon);
        Storage.setValue(Model.KEY_AUTO_NAME, name);
        Storage.setValue(Model.KEY_AUTO_TIME, Time.now().value());
        if (changed) { Model.invalidate(); }
        return true;
    }

    private function cachedGeoName(lat as Double, lon as Double) as String? {
        var gLat = Storage.getValue(Model.KEY_GEO_LAT);
        var gLon = Storage.getValue(Model.KEY_GEO_LON);
        var gName = Storage.getValue(Model.KEY_GEO_NAME);
        if (gLat instanceof Double && gLon instanceof Double && gName instanceof String
            && distanceKm(lat, lon, gLat, gLon) < GEO_CACHE_KM) {
            return gName;
        }
        return null;
    }

    // Reverse geocode through the phone. At most one request in flight, and
    // the same spot is not retried more often than GEO_RETRY_SECONDS (a
    // failure here usually means no phone connection).
    private function requestGeocode(lat as Double, lon as Double) as Void {
        if (_geoPending || !(Toybox has :Communications)) { return; }
        var now = Time.now().value();
        if (_geoTryLat != null && _geoTryLon != null
            && distanceKm(lat, lon, _geoTryLat as Double, _geoTryLon as Double) < GEO_CACHE_KM
            && now - _geoTryTime < GEO_RETRY_SECONDS) {
            return;
        }
        _geoTryLat = lat;
        _geoTryLon = lon;
        _geoTryTime = now;
        _geoPending = true;

        var lang = (System.getDeviceSettings().systemLanguage == System.LANGUAGE_TUR) ? "tr" : "en";
        Communications.makeWebRequest(
            "https://api.bigdatacloud.net/data/reverse-geocode-client",
            {
                "latitude" => lat.format("%.4f"),
                "longitude" => lon.format("%.4f"),
                "localityLanguage" => lang
            },
            {
                :method => Communications.HTTP_REQUEST_METHOD_GET,
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
            },
            method(:onGeocode));
    }

    function onGeocode(code as Number, data as Dictionary or String or Null) as Void {
        _geoPending = false;
        if (code != 200 || !(data instanceof Dictionary)) { return; }

        var name = null;
        var keys = ["locality", "city", "principalSubdivision"];
        for (var i = 0; i < keys.size() && name == null; i++) {
            var v = data[keys[i]];
            if (v instanceof String && v.length() > 0) { name = v; }
        }
        if (name == null || _geoTryLat == null || _geoTryLon == null) { return; }

        Storage.setValue(Model.KEY_GEO_LAT, _geoTryLat);
        Storage.setValue(Model.KEY_GEO_LON, _geoTryLon);
        Storage.setValue(Model.KEY_GEO_NAME, name);

        // Apply to the current fix if it is still the spot we asked about.
        var lat = Storage.getValue(Model.KEY_AUTO_LAT);
        var lon = Storage.getValue(Model.KEY_AUTO_LON);
        if (lat instanceof Double && lon instanceof Double
            && distanceKm(lat, lon, _geoTryLat as Double, _geoTryLon as Double) < GEO_CACHE_KM) {
            Storage.setValue(Model.KEY_AUTO_NAME, name);
            WatchUi.requestUpdate();
        }
    }
}
