import Toybox.Lang;
import Toybox.Math;

// Direction and distance to the Kaaba from a point on Earth.
module Qibla {

    const KAABA_LAT = 21.4225d;
    const KAABA_LON = 39.8262d;
    const EARTH_RADIUS_KM = 6371.0088d;

    function rad(d as Double) as Double { return d * (PrayerCalc.PI / 180.0d); }
    function deg(r as Double) as Double { return r * (180.0d / PrayerCalc.PI); }

    // Initial great-circle bearing from (lat, lon) to the Kaaba, in degrees
    // clockwise from true north, 0..360.
    function bearing(lat as Double, lon as Double) as Double {
        var phi1 = rad(lat);
        var phi2 = rad(KAABA_LAT);
        var dLambda = rad(KAABA_LON - lon);
        var y = Math.sin(dLambda) * Math.cos(phi2);
        var x = Math.cos(phi1) * Math.sin(phi2) - Math.sin(phi1) * Math.cos(phi2) * Math.cos(dLambda);
        return PrayerCalc.unwind(deg(Math.atan2(y, x)));
    }

    // Great-circle distance to the Kaaba in kilometres (haversine).
    function distanceKm(lat as Double, lon as Double) as Double {
        var phi1 = rad(lat);
        var phi2 = rad(KAABA_LAT);
        var dPhi = phi2 - phi1;
        var dLambda = rad(KAABA_LON - lon);
        var sinDPhi = Math.sin(dPhi / 2.0d);
        var sinDLambda = Math.sin(dLambda / 2.0d);
        var a = sinDPhi * sinDPhi + Math.cos(phi1) * Math.cos(phi2) * sinDLambda * sinDLambda;
        return 2.0d * EARTH_RADIUS_KM * Math.atan2(Math.sqrt(a), Math.sqrt(1.0d - a));
    }
}
