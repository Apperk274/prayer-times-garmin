import Toybox.Application;
import Toybox.Application.Storage;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;

// Settings access, location resolution and the day's schedule. Shared by
// the glance and the full view, hence (:glance).
(:glance)
module Model {

    // Values of the "location" setting.
    enum {
        LOC_AUTO = 0,
        LOC_ISTANBUL = 1,
        LOC_ANKARA = 2,
        LOC_IZMIR = 3,
        LOC_MECCA = 4,
        LOC_MEDINA = 5,
        LOC_LONDON = 6,
        LOC_NEWYORK = 7,
        LOC_CUSTOM = 8
    }
    const LOC_COUNT = 9;

    // Storage keys for the auto-location fix (written by LocationProvider).
    const KEY_AUTO_LAT = "autoLat";
    const KEY_AUTO_LON = "autoLon";
    const KEY_AUTO_NAME = "autoName";
    const KEY_AUTO_TIME = "autoTime";
    // Last reverse-geocoded name and the coordinates it was resolved for.
    const KEY_GEO_LAT = "geoLat";
    const KEY_GEO_LON = "geoLon";
    const KEY_GEO_NAME = "geoName";

    // Small schedule cache: the full view shows three days and the glance
    // needs today plus a neighbour, so four entries avoid recomputation on
    // every redraw.
    const CACHE_SIZE = 4;
    var _cacheKeys as Array<String?> = [null, null, null, null];
    var _cacheVals as Array<Array<Number>?> = [null, null, null, null];
    var _cacheSlot as Number = 0;

    function invalidate() as Void {
        _cacheKeys = [null, null, null, null];
        _cacheVals = [null, null, null, null];
        L10n.reset();
    }

    // A list setting as a bounded Number, tolerating the String form some
    // settings editors deliver and missing keys.
    function readIndex(key as String, def as Number, count as Number) as Number {
        var v = null;
        try {
            v = Application.Properties.getValue(key);
        } catch (e) {
            return def;
        }
        if (v instanceof String) { v = v.toNumber(); }
        if (v instanceof Number && v >= 0 && v < count) { return v; }
        return def;
    }

    function readDouble(key as String) as Double? {
        var v = null;
        try {
            v = Application.Properties.getValue(key);
        } catch (e) {
            return null;
        }
        if (v instanceof String) { v = v.toFloat(); }
        if (v instanceof Number || v instanceof Float || v instanceof Double || v instanceof Long) {
            return (v as Numeric).toDouble();
        }
        return null;
    }

    function methodIndex() as Number { return readIndex("method", Methods.DIYANET, Methods.COUNT); }
    function madhab() as Number { return readIndex("madhab", PrayerCalc.MADHAB_STANDARD, 2); }
    function locationIndex() as Number { return readIndex("location", LOC_AUTO, LOC_COUNT); }
    function language() as Number { return readIndex("language", L10n.DEVICE, L10n.COUNT); }

    function presetName(idx as Number) as String {
        switch (idx) {
            case LOC_ISTANBUL: return "Istanbul";
            case LOC_ANKARA:   return "Ankara";
            case LOC_IZMIR:    return "İzmir";
            case LOC_MECCA:    return "Mecca";
            case LOC_MEDINA:   return "Medina";
            case LOC_LONDON:   return "London";
            case LOC_NEWYORK:  return "New York";
            case LOC_CUSTOM:   return L10n.s(L10n.LOCATION_CUSTOM);
            default:           return L10n.s(L10n.LOCATION_AUTO);
        }
    }

    // Same coordinates as the desktop app's default places.
    function presetLat(idx as Number) as Double {
        switch (idx) {
            case LOC_ANKARA:  return 39.9334d;
            case LOC_IZMIR:   return 38.4237d;
            case LOC_MECCA:   return 21.4225d;
            case LOC_MEDINA:  return 24.4672d;
            case LOC_LONDON:  return 51.5074d;
            case LOC_NEWYORK: return 40.7128d;
            default:          return 41.0082d; // Istanbul
        }
    }

    function presetLon(idx as Number) as Double {
        switch (idx) {
            case LOC_ANKARA:  return 32.8597d;
            case LOC_IZMIR:   return 27.1428d;
            case LOC_MECCA:   return 39.8262d;
            case LOC_MEDINA:  return 39.6111d;
            case LOC_LONDON:  return -0.1278d;
            case LOC_NEWYORK: return -74.0060d;
            default:          return 28.9784d; // Istanbul
        }
    }

    // The place to calculate for, as {:lat, :lon, :name}, or null when
    // auto mode has no fix yet / custom coordinates are unset.
    function location() as Dictionary? {
        var idx = locationIndex();
        if (idx == LOC_AUTO) {
            var lat = Storage.getValue(KEY_AUTO_LAT);
            var lon = Storage.getValue(KEY_AUTO_LON);
            if (!(lat instanceof Double || lat instanceof Float) || !(lon instanceof Double || lon instanceof Float)) {
                return null;
            }
            var latD = (lat as Numeric).toDouble();
            var lonD = (lon as Numeric).toDouble();
            var name = Storage.getValue(KEY_AUTO_NAME);
            if (!(name instanceof String) || name.length() == 0) {
                // No name (yet): show where we are anyway.
                name = Lang.format("$1$°, $2$°", [latD.format("%.2f"), lonD.format("%.2f")]);
            }
            return { :lat => latD, :lon => lonD, :name => name };
        }
        if (idx == LOC_CUSTOM) {
            var lat = readDouble("customLat");
            var lon = readDouble("customLon");
            if (lat == null || lon == null || (lat == 0.0d && lon == 0.0d)
                || lat > 90.0d || lat < -90.0d || lon > 180.0d || lon < -180.0d) {
                return null;
            }
            var name = null;
            try {
                name = Application.Properties.getValue("customName");
            } catch (e) {
                name = null;
            }
            if (!(name instanceof String) || name.length() == 0) {
                name = L10n.s(L10n.LOCATION_CUSTOM);
            }
            return { :lat => lat, :lon => lon, :name => name };
        }
        return { :lat => presetLat(idx), :lon => presetLon(idx), :name => presetName(idx) };
    }

    function timesFor(year as Number, month as Number, day as Number,
                      loc as Dictionary, method as Number, madhab as Number) as Array<Number>? {
        var key = Lang.format("$1$-$2$-$3$|$4$|$5$|$6$|$7$",
            [year, month, day, loc[:lat], loc[:lon], method, madhab]);
        for (var i = 0; i < CACHE_SIZE; i++) {
            if (key.equals(_cacheKeys[i])) { return _cacheVals[i]; }
        }
        var times = PrayerCalc.compute(year, month, day,
            loc[:lat] as Double, loc[:lon] as Double, Methods.params(method, madhab));
        _cacheKeys[_cacheSlot] = key;
        _cacheVals[_cacheSlot] = times;
        _cacheSlot = (_cacheSlot + 1) % CACHE_SIZE;
        return times;
    }

    // The six times of the local calendar date that `moment` falls on, for
    // the current settings, or null.
    function dayTimes(moment as Time.Moment, loc as Dictionary) as Array<Number>? {
        var info = Gregorian.info(moment, Time.FORMAT_SHORT);
        return timesFor(info.year as Number, info.month as Number, info.day as Number,
            loc, methodIndex(), madhab());
    }

    // The schedule to display at `now`, mirroring the desktop app: today's
    // times, or tomorrow's once Isha has passed so the table never lies
    // entirely in the past. Returns
    //   {:times => Array<Number> (6 epoch seconds),
    //    :nextIdx => Number, :nextAt => Number (epoch seconds),
    //    :prevAt => Number (the prayer before it, for progress bars),
    //    :tomorrow => Boolean, :location => Dictionary}
    // or null when there is no location or no sunrise/sunset that day.
    function schedule(now as Time.Moment) as Dictionary? {
        var loc = location();
        if (loc == null) { return null; }
        var method = methodIndex();
        var md = madhab();
        var nowSec = now.value();

        var info = Gregorian.info(now, Time.FORMAT_SHORT);
        var times = timesFor(info.year as Number, info.month as Number, info.day as Number, loc, method, md);
        if (times == null) { return null; }

        var todayTimes = times;
        var tomorrow = false;
        var tmInfo = Gregorian.info(now.add(new Time.Duration(Gregorian.SECONDS_PER_DAY)), Time.FORMAT_SHORT);
        if (times[5] <= nowSec) {
            var t2 = timesFor(tmInfo.year as Number, tmInfo.month as Number, tmInfo.day as Number, loc, method, md);
            if (t2 != null) {
                times = t2;
                tomorrow = true;
            }
        }

        var nextIdx = -1;
        for (var i = 0; i < 6; i++) {
            if (times[i] > nowSec) {
                nextIdx = i;
                break;
            }
        }
        var nextAt;
        if (nextIdx < 0) {
            // Everything passed and tomorrow could not be computed: count
            // down to tomorrow's Fajr as best we can.
            var t3 = timesFor(tmInfo.year as Number, tmInfo.month as Number, tmInfo.day as Number, loc, method, md);
            nextIdx = 0;
            nextAt = (t3 != null) ? t3[0] : times[0] + Gregorian.SECONDS_PER_DAY;
        } else {
            nextAt = times[nextIdx];
        }

        // The prayer before the next one: the previous row, today's Isha
        // when we rolled to tomorrow, or yesterday's Isha before Fajr.
        var prevAt;
        if (nextIdx > 0) {
            prevAt = times[nextIdx - 1];
        } else if (tomorrow) {
            prevAt = todayTimes[5];
        } else {
            var ydInfo = Gregorian.info(now.subtract(new Time.Duration(Gregorian.SECONDS_PER_DAY)) as Time.Moment, Time.FORMAT_SHORT);
            var yd = timesFor(ydInfo.year as Number, ydInfo.month as Number, ydInfo.day as Number, loc, method, md);
            prevAt = (yd != null) ? yd[5] : nextAt - 8 * 3600;
        }

        return {
            :times => times,
            :nextIdx => nextIdx,
            :nextAt => nextAt,
            :prevAt => prevAt,
            :tomorrow => tomorrow,
            :location => loc
        };
    }
}

// Display formatting shared by both views.
(:glance)
module Fmt {

    function prayerName(idx as Number) as String {
        return L10n.s(L10n.FAJR + idx);
    }

    // Epoch seconds as a wall-clock time in the watch's zone, honouring the
    // 12/24 hour setting.
    function clock(epoch as Number) as String {
        var info = Gregorian.info(new Time.Moment(epoch), Time.FORMAT_SHORT);
        var hour = info.hour as Number;
        if (!System.getDeviceSettings().is24Hour) {
            hour = hour % 12;
            if (hour == 0) { hour = 12; }
        }
        return Lang.format("$1$:$2$", [hour, (info.min as Number).format("%02d")]);
    }

    // Remaining time in words: "in 7h 15m" / "in 15m" (localized).
    function timeLeft(seconds as Number) as String {
        if (seconds < 0) { seconds = 0; }
        var h = seconds / 3600;
        var m = (seconds % 3600) / 60;
        if (h > 0) {
            return Lang.format(L10n.s(L10n.TIME_LEFT_HM), [h, m]);
        }
        return Lang.format(L10n.s(L10n.TIME_LEFT_M), [m]);
    }
}
