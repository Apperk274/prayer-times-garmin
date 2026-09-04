import Toybox.Lang;
import Toybox.Math;

// Offline prayer-time calculation.
//
// This is a line-by-line port of the adhan algorithm (Batoul Apps) as
// implemented by adhango, the library the desktop app in ../prayer-times-go
// uses. Times are returned as UTC epoch seconds, which the views format in
// the watch's local time zone.
//
// Everything is computed in Double. Monkey C's Float is single precision
// (~7 significant digits), which is nowhere near enough for Julian-day
// arithmetic (2.46 million days) or the sidereal-time series. Every literal
// therefore carries the "d" suffix; an unsuffixed literal would silently be
// a Float and poison the whole expression.
(:glance)
module PrayerCalc {

    const PI = 3.14159265358979323846d;

    // Asr shadow length: standard (Shafi/Hanbali/Maliki) = 1, Hanafi = 2.
    enum { MADHAB_STANDARD = 0, MADHAB_HANAFI = 1 }

    // High-latitude rules bounding Fajr and Isha when the twilight angle is
    // never reached (or is reached absurdly early/late).
    enum { HL_MIDDLE_OF_THE_NIGHT = 0, HL_SEVENTH_OF_THE_NIGHT = 1, HL_TWILIGHT_ANGLE = 2 }

    // Parameter dictionary keys (see Methods.mc for the presets):
    //   :fajrAngle    Double, degrees below the horizon
    //   :ishaAngle    Double, degrees below the horizon
    //   :ishaInterval Number, minutes after Maghrib (0 = use :ishaAngle)
    //   :adj          Array<Number>, method minute offsets
    //                 [fajr, sunrise, dhuhr, asr, maghrib, isha]
    //   :moonsighting Boolean, Moonsighting Committee's seasonal rules
    //   :madhab       MADHAB_*
    //   :highLat      HL_*

    function rad(d as Double) as Double { return d * (PI / 180.0d); }
    function deg(r as Double) as Double { return r * (180.0d / PI); }

    function normalize(v as Double, max as Double) as Double {
        return v - max * Math.floor(v / max);
    }

    function unwind(a as Double) as Double { return normalize(a, 360.0d); }

    function closestAngle(a as Double) as Double {
        if (a >= -180.0d && a <= 180.0d) { return a; }
        return a - 360.0d * Math.round(a / 360.0d);
    }

    // Julian day at 0h UT of the given civil date.
    function julianDay(year as Number, month as Number, day as Number) as Double {
        var y = year;
        var m = month;
        if (month <= 2) {
            y = year - 1;
            m = month + 12;
        }
        var a = Math.floor(y / 100.0d);
        var b = Math.floor(2.0d - a + a / 4.0d);
        var i0 = Math.floor(365.25d * (y + 4716));
        var i1 = Math.floor(30.6001d * (m + 1));
        return i0 + i1 + b + day - 1524.5d;
    }

    // Unix epoch seconds of 0h UT on the given civil date. The Julian day
    // of a midnight ends in .5, so the subtraction is exact.
    function midnightUtc(year as Number, month as Number, day as Number) as Number {
        return ((julianDay(year, month, day) - 2440587.5d) * 86400.0d).toNumber();
    }

    function isLeapYear(year as Number) as Boolean {
        return year % 4 == 0 && !(year % 100 == 0 && year % 400 != 0);
    }

    function daysInMonth(year as Number, month as Number) as Number {
        if (month == 2) { return isLeapYear(year) ? 29 : 28; }
        if (month == 4 || month == 6 || month == 9 || month == 11) { return 30; }
        return 31;
    }

    // [year, month, day] of the following civil date.
    function nextDay(year as Number, month as Number, day as Number) as Array<Number> {
        if (day < daysInMonth(year, month)) { return [year, month, day + 1]; }
        if (month < 12) { return [year, month + 1, 1]; }
        return [year + 1, 1, 1];
    }

    function dayOfYear(year as Number, month as Number, day as Number) as Number {
        return (julianDay(year, month, day) - julianDay(year, 1, 1)).toNumber() + 1;
    }

    // Declination, right ascension and apparent sidereal time of the sun
    // for a Julian day, as [declination, rightAscension, siderealTime].
    function solarCoordinates(jd as Double) as Array<Double> {
        var T = (jd - 2451545.0d) / 36525.0d;
        var T2 = T * T;
        var T3 = T2 * T;

        var L0 = unwind(280.4664567d + 36000.76983d * T + 0.0003032d * T2);
        var Lp = unwind(218.3165d + 481267.8813d * T);
        var Om = unwind(125.04452d - 1934.136261d * T + 0.0020708d * T2 + T3 / 450000.0d);
        var M = unwind(357.52911d + 35999.05029d * T - 0.0001537d * T2);

        var Mr = rad(M);
        var C = (1.914602d - 0.004817d * T - 0.000014d * T2) * Math.sin(Mr)
              + (0.019993d - 0.000101d * T) * Math.sin(2.0d * Mr)
              + 0.000289d * Math.sin(3.0d * Mr);

        var OmRaw = 125.04d - 1934.136d * T;
        var lambda = rad(unwind(L0 + C - 0.00569d - 0.00478d * Math.sin(rad(OmRaw))));

        var JD = T * 36525.0d + 2451545.0d;
        var theta0 = unwind(280.46061837d + 360.98564736629d * (JD - 2451545.0d)
                            + 0.000387933d * T2 - T3 / 38710000.0d);

        var dPsi = (-17.2d / 3600.0d) * Math.sin(rad(Om))
                 - (1.32d / 3600.0d) * Math.sin(2.0d * rad(L0))
                 - (0.23d / 3600.0d) * Math.sin(2.0d * rad(Lp))
                 + (0.21d / 3600.0d) * Math.sin(2.0d * rad(Om));
        var dEps = (9.2d / 3600.0d) * Math.cos(rad(Om))
                 + (0.57d / 3600.0d) * Math.cos(2.0d * rad(L0))
                 + (0.10d / 3600.0d) * Math.cos(2.0d * rad(Lp))
                 - (0.09d / 3600.0d) * Math.cos(2.0d * rad(Om));

        var eps0 = 23.439291d - 0.013004167d * T - 0.0000001639d * T2 + 0.0000005036d * T3;
        var epsApp = rad(eps0 + 0.00256d * Math.cos(rad(OmRaw)));

        var declination = deg(Math.asin(Math.sin(epsApp) * Math.sin(lambda)));
        var rightAscension = unwind(deg(Math.atan2(Math.cos(epsApp) * Math.sin(lambda), Math.cos(lambda))));
        var siderealTime = theta0 + dPsi * Math.cos(rad(eps0 + dEps));

        return [declination, rightAscension, siderealTime];
    }

    function interpolate(y2 as Double, y1 as Double, y3 as Double, n as Double) as Double {
        var a = y2 - y1;
        var b = y3 - y2;
        var c = b - a;
        return y2 + (n / 2.0d) * (a + b + n * c);
    }

    function interpolateAngles(y2 as Double, y1 as Double, y3 as Double, n as Double) as Double {
        var a = unwind(y2 - y1);
        var b = unwind(y3 - y2);
        var c = b - a;
        return y2 + (n / 2.0d) * (a + b + n * c);
    }

    function altitude(lat as Double, dec as Double, H as Double) as Double {
        var term1 = Math.sin(rad(lat)) * Math.sin(rad(dec));
        var term2 = Math.cos(rad(lat)) * Math.cos(rad(dec)) * Math.cos(rad(H));
        return deg(Math.asin(term1 + term2));
    }

    // Solar events of one day at one place, in fractional hours UT.
    class SolarTime {
        var transit as Double;
        var sunrise as Double?;
        var sunset as Double?;

        private var _lat as Double;
        private var _lon as Double;
        private var _m0 as Double;
        private var _sol as Array<Double>;
        private var _prev as Array<Double>;
        private var _next as Array<Double>;

        function initialize(year as Number, month as Number, day as Number, lat as Double, lon as Double) {
            _lat = lat;
            _lon = lon;
            var jd = julianDay(year, month, day);
            _prev = solarCoordinates(jd - 1.0d);
            _sol = solarCoordinates(jd);
            _next = solarCoordinates(jd + 1.0d);

            // Approximate transit: (alpha + Lw - theta0) / 360 with Lw = -L.
            _m0 = normalize((_sol[1] - lon - _sol[2]) / 360.0d, 1.0d);

            transit = correctedTransit();
            var h0 = -50.0d / 60.0d;
            sunrise = hourAngle(h0, false);
            sunset = hourAngle(h0, true);
        }

        private function correctedTransit() as Double {
            var Lw = -_lon;
            var theta = unwind(_sol[2] + 360.985647d * _m0);
            var alpha = unwind(interpolateAngles(_sol[1], _prev[1], _next[1], _m0));
            var H = closestAngle(theta - Lw - alpha);
            var dm = H / -360.0d;
            return (_m0 + dm) * 24.0d;
        }

        // Time the sun reaches altitude h0 (degrees) before or after
        // transit, or null when it never does (the reference returns NaN
        // there and lets the caller substitute a safe value).
        function hourAngle(h0 as Double, afterTransit as Boolean) as Double? {
            var Lw = -_lon;
            var dec2 = _sol[0];
            var term1 = Math.sin(rad(h0)) - Math.sin(rad(_lat)) * Math.sin(rad(dec2));
            var term2 = Math.cos(rad(_lat)) * Math.cos(rad(dec2));
            var cosH0 = term1 / term2;
            if (cosH0 > 1.0d || cosH0 < -1.0d) { return null; }
            var H0 = deg(Math.acos(cosH0));
            var m = afterTransit ? _m0 + H0 / 360.0d : _m0 - H0 / 360.0d;
            var theta = unwind(_sol[2] + 360.985647d * m);
            var alpha = unwind(interpolateAngles(_sol[1], _prev[1], _next[1], m));
            var delta = interpolate(_sol[0], _prev[0], _next[0], m);
            var H = theta - Lw - alpha;
            var h = altitude(_lat, delta, H);
            var term3 = h - h0;
            var term4 = 360.0d * Math.cos(rad(delta)) * Math.cos(rad(_lat)) * Math.sin(rad(H));
            var dm = term3 / term4;
            return (m + dm) * 24.0d;
        }

        // Asr: when an object's shadow equals `shadow` times its length plus
        // its shadow at noon.
        function afternoon(shadow as Number) as Double? {
            var tangent = (_lat - _sol[0]).abs();
            var inverse = shadow + Math.tan(rad(tangent));
            var angle = deg(Math.atan(1.0d / inverse));
            return hourAngle(angle, true);
        }
    }

    // Fractional hours -> whole seconds, truncating the way the reference
    // does (hours, then minutes, then seconds, each floored).
    function toSeconds(hours as Double) as Number {
        var h = Math.floor(hours);
        var m = Math.floor((hours - h) * 60.0d);
        var s = Math.floor((hours - (h + m / 60.0d)) * 3600.0d);
        return (h * 3600.0d + m * 60.0d + s).toNumber();
    }

    // Nearest minute, halves rounding up (as math.Round on seconds/60).
    function roundToMinute(t as Number) as Number {
        var r = t + 30;
        return r - (r % 60);
    }

    function seasonAdjusted(lat as Double, doy as Number, year as Number,
                            a as Double, b as Double, c as Double, d as Double) as Double {
        var dyy = daysSinceSolstice(doy, year, lat);
        var adjustment;
        if (dyy < 91) {
            adjustment = a + (b - a) / 91.0d * dyy;
        } else if (dyy < 137) {
            adjustment = b + (c - b) / 46.0d * (dyy - 91);
        } else if (dyy < 183) {
            adjustment = c + (d - c) / 46.0d * (dyy - 137);
        } else if (dyy < 229) {
            adjustment = d + (c - d) / 46.0d * (dyy - 183);
        } else if (dyy < 275) {
            adjustment = c + (b - c) / 46.0d * (dyy - 229);
        } else {
            adjustment = b + (a - b) / 91.0d * (dyy - 275);
        }
        return adjustment;
    }

    // Moonsighting Committee: Fajr no earlier than a season-dependent
    // number of minutes before sunrise.
    function seasonAdjustedMorningTwilight(lat as Double, doy as Number, year as Number, sunrise as Number) as Number {
        var abs = lat.abs();
        var a = 75.0d + (28.65d / 55.0d) * abs;
        var b = 75.0d + (19.44d / 55.0d) * abs;
        var c = 75.0d + (32.74d / 55.0d) * abs;
        var d = 75.0d + (48.10d / 55.0d) * abs;
        var adjustment = seasonAdjusted(lat, doy, year, a, b, c, d);
        return sunrise - Math.round(adjustment * 60.0d).toNumber();
    }

    // Moonsighting Committee: Isha no later than a season-dependent number
    // of minutes after sunset.
    function seasonAdjustedEveningTwilight(lat as Double, doy as Number, year as Number, sunset as Number) as Number {
        var abs = lat.abs();
        var a = 75.0d + (25.60d / 55.0d) * abs;
        var b = 75.0d + (2.050d / 55.0d) * abs;
        var c = 75.0d - (9.210d / 55.0d) * abs;
        var d = 75.0d + (6.140d / 55.0d) * abs;
        var adjustment = seasonAdjusted(lat, doy, year, a, b, c, d);
        return sunset + Math.round(adjustment * 60.0d).toNumber();
    }

    function daysSinceSolstice(doy as Number, year as Number, lat as Double) as Number {
        var leap = isLeapYear(year);
        var daysInYear = leap ? 366 : 365;
        if (lat >= 0.0d) {
            var n = doy + 10;
            if (n >= daysInYear) { n -= daysInYear; }
            return n;
        }
        var s = doy - (leap ? 173 : 172);
        if (s < 0) { s += daysInYear; }
        return s;
    }

    // Night fraction used by the high-latitude rules for Fajr/Isha.
    function nightPortions(p as Dictionary) as Array<Double> {
        var rule = p[:highLat];
        if (rule == HL_SEVENTH_OF_THE_NIGHT) { return [1.0d / 7.0d, 1.0d / 7.0d]; }
        if (rule == HL_TWILIGHT_ANGLE) {
            return [(p[:fajrAngle] as Double) / 60.0d, (p[:ishaAngle] as Double) / 60.0d];
        }
        return [0.5d, 0.5d];
    }

    // The six times of one civil date at (lat, lon) using parameters p, as
    // UTC epoch seconds in the order [Fajr, Sunrise, Dhuhr, Asr, Maghrib,
    // Isha]. Returns null when the sun does not rise or set that day
    // (polar regions), which the reference reports as an error.
    function compute(year as Number, month as Number, day as Number,
                     lat as Double, lon as Double, p as Dictionary) as Array<Number>? {
        var midnight = midnightUtc(year, month, day);
        var st = new SolarTime(year, month, day, lat, lon);
        if (st.sunrise == null || st.sunset == null) { return null; }

        var tm = nextDay(year, month, day);
        var stTomorrow = new SolarTime(tm[0], tm[1], tm[2], lat, lon);
        if (stTomorrow.sunrise == null) { return null; }

        var transit = midnight + toSeconds(st.transit);
        var sunrise = midnight + toSeconds(st.sunrise as Double);
        var sunset = midnight + toSeconds(st.sunset as Double);
        var tomorrowSunrise = midnight + 86400 + toSeconds(stTomorrow.sunrise as Double);
        var night = tomorrowSunrise - sunset; // seconds

        var shadow = (p[:madhab] == MADHAB_HANAFI) ? 2 : 1;
        var asrHours = st.afternoon(shadow);
        if (asrHours == null) { return null; }
        var asr = midnight + toSeconds(asrHours);

        var moon = p[:moonsighting] == true;
        var portions = nightPortions(p);
        var doy = dayOfYear(year, month, day);

        // Fajr, bounded by the high-latitude safe value.
        var fajr = null;
        var fajrHours = st.hourAngle(-(p[:fajrAngle] as Double), false);
        if (fajrHours != null) { fajr = midnight + toSeconds(fajrHours); }
        if (moon && lat >= 55.0d) { fajr = sunrise - night / 7; }

        var safeFajr;
        if (moon) {
            safeFajr = seasonAdjustedMorningTwilight(lat, doy, year, sunrise);
        } else {
            safeFajr = sunrise - (portions[0] * night).toNumber();
        }
        if (fajr == null || fajr < safeFajr) { fajr = safeFajr; }

        // Isha: fixed interval after Maghrib, or angle bounded by the safe
        // value.
        var isha;
        var interval = p[:ishaInterval] as Number;
        if (interval > 0) {
            isha = sunset + interval * 60;
        } else {
            isha = null;
            var ishaHours = st.hourAngle(-(p[:ishaAngle] as Double), true);
            if (ishaHours != null) { isha = midnight + toSeconds(ishaHours); }
            if (moon && lat >= 55.0d) { isha = sunset + night / 7; }

            var safeIsha;
            if (moon) {
                safeIsha = seasonAdjustedEveningTwilight(lat, doy, year, sunset);
            } else {
                safeIsha = sunset + (portions[1] * night).toNumber();
            }
            if (isha == null || isha > safeIsha) { isha = safeIsha; }
        }

        var adj = p[:adj] as Array<Number>;
        return [
            roundToMinute(fajr + adj[0] * 60),
            roundToMinute(sunrise + adj[1] * 60),
            roundToMinute(transit + adj[2] * 60),
            roundToMinute(asr + adj[3] * 60),
            roundToMinute(sunset + adj[4] * 60),
            roundToMinute(isha + adj[5] * 60)
        ];
    }
}
