import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Sensor;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.Timer;
import Toybox.WatchUi;

// Full view: one page per day (today and the next two), each an imsakiye
// table with the date on top, then a Qibla compass page. The row matching
// the next prayer is highlighted on whichever page it falls. Geometry is
// relative to the screen size so it fits any round display.
class PrayerView extends WatchUi.View {

    const PAGES = 4;
    const QIBLA_PAGE = 3;
    // Redraw period: slow for the tables, fast while the compass is showing.
    const TICK_MS = 10000;
    const COMPASS_TICK_MS = 250;

    private var _timer as Timer.Timer?;
    private var _page as Number = 0;
    private var _heading as Float? = null;
    var locationProvider as LocationProvider;

    function initialize() {
        View.initialize();
        locationProvider = new LocationProvider();
    }

    function onShow() as Void {
        refreshLocation();
        applyPageMode();
    }

    function onHide() as Void {
        stopTimer();
        setCompass(false);
        locationProvider.stopGps();
    }

    private function stopTimer() as Void {
        if (_timer != null) {
            (_timer as Timer.Timer).stop();
            _timer = null;
        }
    }

    // Timer rate and compass power follow the page being shown.
    private function applyPageMode() as Void {
        stopTimer();
        var compass = (_page == QIBLA_PAGE);
        setCompass(compass);
        _timer = new Timer.Timer();
        (_timer as Timer.Timer).start(method(:onTick), compass ? COMPASS_TICK_MS : TICK_MS, true);
    }

    private function setCompass(on as Boolean) as Void {
        if (on) {
            Sensor.enableSensorEvents(method(:onSensor));
        } else {
            Sensor.enableSensorEvents(null);
            _heading = null;
        }
    }

    function onSensor(info as Sensor.Info) as Void {
        if (info.heading != null) { _heading = info.heading; }
    }

    function onTick() as Void {
        if (_page == QIBLA_PAGE) {
            // Sensor events arrive at 1 Hz; getInfo often has a fresher value.
            var info = Sensor.getInfo();
            if (info.heading != null) { _heading = info.heading; }
        } else {
            refreshLocation();
        }
        WatchUi.requestUpdate();
    }

    private function refreshLocation() as Void {
        if (Model.locationIndex() == Model.LOC_AUTO) {
            locationProvider.refreshPassive();
        }
    }

    function nextPage() as Void {
        _page = (_page + 1) % PAGES;
        applyPageMode();
        WatchUi.requestUpdate();
    }

    function previousPage() as Void {
        _page = (_page + PAGES - 1) % PAGES;
        applyPageMode();
        WatchUi.requestUpdate();
    }

    // START/SELECT: get a fresh GPS fix (auto mode only).
    function requestGps() as Void {
        if (Model.locationIndex() != Model.LOC_AUTO) { return; }
        locationProvider.startGps();
        WatchUi.requestUpdate();
    }

    // Shorten `text` with "..." until it fits maxWidth in `font`.
    private function fit(dc as Dc, text as String, font as Graphics.FontDefinition, maxWidth as Number) as String {
        if (dc.getTextWidthInPixels(text, font) <= maxWidth) { return text; }
        var t = text;
        while (t.length() > 1) {
            t = t.substring(0, t.length() - 1) as String;
            var candidate = t + "...";
            if (dc.getTextWidthInPixels(candidate, font) <= maxWidth) { return candidate; }
        }
        return t;
    }

    function onUpdate(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        var now = Time.now();
        var loc = Model.location();
        if (loc == null) {
            drawNoLocation(dc, w, h);
            return;
        }

        // Place (and GPS status). Sits low enough on the round screen to
        // have ~65% of the width; anything longer is trimmed with "...".
        var header = loc[:name] as String;
        if (locationProvider.acquiring) {
            header = Lang.format("$1$ · $2$", [header, L10n.s(L10n.ACQUIRING)]);
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.13, Graphics.FONT_XTINY,
            fit(dc, header, Graphics.FONT_XTINY, (w * 0.66).toNumber()),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        if (_page == QIBLA_PAGE) {
            drawQibla(dc, w, h, loc[:lat] as Double, loc[:lon] as Double);
            drawPageDots(dc, w, h);
            return;
        }

        var dayMoment = now.add(new Time.Duration(_page * Gregorian.SECONDS_PER_DAY));
        var times = Model.dayTimes(dayMoment, loc);
        var s = Model.schedule(now);
        var nextAt = (s != null) ? s[:nextAt] as Number : -1;
        var nowSec = now.value();

        // "Today", or the date of the future page ("Thu 4 Sep").
        var dateLine = (_page == 0) ? L10n.s(L10n.TODAY) : L10n.dateHeader(dayMoment);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.215, Graphics.FONT_XTINY, dateLine,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // The six rows.
        var left = cx - w * 0.30;
        var right = cx + w * 0.30;
        var rowH = h * 0.105;
        var y0 = h * 0.31;
        for (var i = 0; i < 6; i++) {
            var y = y0 + i * rowH;
            var t = (times != null) ? times[i] : null;
            var color = Graphics.COLOR_WHITE;
            var isNext = (t != null && t == nextAt);
            if (isNext) {
                color = Graphics.COLOR_ORANGE;
            } else if (t != null && t <= nowSec) {
                color = Graphics.COLOR_DK_GRAY;
            }
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            if (isNext) {
                dc.fillCircle(left - w * 0.05, y, 4);
            }
            dc.drawText(left, y, Graphics.FONT_TINY, Fmt.prayerName(i),
                Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.drawText(right, y, Graphics.FONT_TINY, (t != null) ? Fmt.clock(t) : "--:--",
                Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        drawPageDots(dc, w, h);
    }

    private function drawPageDots(dc as Dc, w as Number, h as Number) as Void {
        var cx = w / 2;
        var dotY = h * 0.94;
        var gap = 12;
        var x0 = cx - gap * (PAGES - 1) / 2;
        for (var p = 0; p < PAGES; p++) {
            dc.setColor(p == _page ? Graphics.COLOR_WHITE : Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(x0 + p * gap, dotY, 3);
        }
    }

    // Compass rose rotated by the watch heading, with an arrow to the Kaaba.
    // Without a compass reading the rose stays north-up, which still tells
    // the bearing.
    private function drawQibla(dc as Dc, w as Number, h as Number, lat as Double, lon as Double) as Void {
        var cx = w / 2;
        var cy = (h * 0.55).toNumber();
        var radius = (w * 0.30).toNumber();

        var qibla = Qibla.bearing(lat, lon);           // degrees from north
        var headingDeg = 0.0d;
        var hasCompass = (_heading != null);
        if (hasCompass) { headingDeg = PrayerCalc.unwind(Qibla.deg((_heading as Float).toDouble())); }
        // Screen angle of the arrow: clockwise from "up" on the display.
        var rel = PrayerCalc.unwind(qibla - headingDeg);
        var off = (rel > 180.0d) ? 360.0d - rel : rel;   // how far off we point
        var aligned = hasCompass && off < 5.0d;

        // Ring and ticks.
        dc.setPenWidth(2);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(cx, cy, radius);
        for (var t = 0; t < 360; t += 30) {
            var a = Qibla.rad(t.toDouble() - headingDeg);
            var inner = (t % 90 == 0) ? radius - 12 : radius - 6;
            dc.drawLine(cx + radius * Math.sin(a), cy - radius * Math.cos(a),
                        cx + inner * Math.sin(a), cy - inner * Math.cos(a));
        }
        dc.setPenWidth(1);

        // Cardinal letters, N in red.
        var letters = [L10n.DIR_N, L10n.DIR_E, L10n.DIR_S, L10n.DIR_W];
        for (var i = 0; i < 4; i++) {
            var a = Qibla.rad(i * 90.0d - headingDeg);
            var r = radius - 26;
            dc.setColor(i == 0 ? Graphics.COLOR_RED : Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx + r * Math.sin(a), cy - r * Math.cos(a), Graphics.FONT_XTINY,
                L10n.s(letters[i]), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        // Arrow to the Kaaba.
        var a = Qibla.rad(rel);
        var tipR = radius - 38;
        var tailR = radius * 0.30;
        var halfW = 14.0d;
        var sinA = Math.sin(a);
        var cosA = Math.cos(a);
        var tipX = cx + tipR * sinA;
        var tipY = cy - tipR * cosA;
        var baseX = cx + (tipR - 30) * sinA;
        var baseY = cy - (tipR - 30) * cosA;
        // Perpendicular unit vector for the arrow head width.
        var px = cosA;
        var py = sinA;
        dc.setColor(aligned ? Graphics.COLOR_GREEN : Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([
            [tipX.toNumber(), tipY.toNumber()],
            [(baseX + px * halfW).toNumber(), (baseY + py * halfW).toNumber()],
            [(baseX - px * halfW).toNumber(), (baseY - py * halfW).toNumber()]
        ]);
        dc.setPenWidth(5);
        dc.drawLine(cx - tailR * sinA, cy + tailR * cosA, baseX, baseY);
        dc.setPenWidth(1);
        dc.fillCircle(cx, cy, 5);

        // Bearing and distance, or the missing-compass note.
        var distKm = Qibla.distanceKm(lat, lon);
        var distText;
        if (System.getDeviceSettings().distanceUnits == System.UNIT_STATUTE) {
            distText = Lang.format("$1$ mi", [(distKm * 0.621371d).toNumber()]);
        } else {
            distText = Lang.format("$1$ km", [distKm.toNumber()]);
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.215, Graphics.FONT_XTINY,
            Lang.format("$1$ $2$°", [L10n.s(L10n.QIBLA), Math.round(qibla).toNumber()]),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.875, Graphics.FONT_XTINY,
            hasCompass ? distText : L10n.s(L10n.NO_COMPASS),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function drawNoLocation(dc as Dc, w as Number, h as Number) as Void {
        var cx = w / 2;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.35, Graphics.FONT_SMALL, L10n.s(L10n.APP_NAME),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.50, Graphics.FONT_TINY, L10n.s(L10n.NO_LOCATION),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        var hint;
        if (Model.locationIndex() == Model.LOC_AUTO) {
            hint = L10n.s(locationProvider.acquiring ? L10n.ACQUIRING : L10n.PRESS_FOR_GPS);
        } else {
            hint = L10n.s(L10n.SET_CUSTOM_HINT);
        }
        dc.drawText(cx, h * 0.64, Graphics.FONT_XTINY, fit(dc, hint, Graphics.FONT_XTINY, (w * 0.75).toNumber()),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}
