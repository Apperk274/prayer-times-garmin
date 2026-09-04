import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.Timer;
import Toybox.WatchUi;

// Full view: one page per day (today and the next two), each an imsakiye
// table with the date on top. The row matching the next prayer is
// highlighted on whichever page it falls. Geometry is relative to the
// screen size so it fits any round display.
class PrayerView extends WatchUi.View {

    const PAGES = 3;

    private var _timer as Timer.Timer?;
    private var _page as Number = 0;
    var locationProvider as LocationProvider;

    function initialize() {
        View.initialize();
        locationProvider = new LocationProvider();
    }

    function onShow() as Void {
        refreshLocation();
        _timer = new Timer.Timer();
        (_timer as Timer.Timer).start(method(:onTick), 10000, true);
    }

    function onHide() as Void {
        if (_timer != null) {
            (_timer as Timer.Timer).stop();
            _timer = null;
        }
        locationProvider.stopGps();
    }

    function onTick() as Void {
        refreshLocation();
        WatchUi.requestUpdate();
    }

    private function refreshLocation() as Void {
        if (Model.locationIndex() == Model.LOC_AUTO) {
            locationProvider.refreshPassive();
        }
    }

    function nextPage() as Void {
        _page = (_page + 1) % PAGES;
        WatchUi.requestUpdate();
    }

    function previousPage() as Void {
        _page = (_page + PAGES - 1) % PAGES;
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

        var dayMoment = now.add(new Time.Duration(_page * Gregorian.SECONDS_PER_DAY));
        var times = Model.dayTimes(dayMoment, loc);
        var s = Model.schedule(now);
        var nextAt = (s != null) ? s[:nextAt] as Number : -1;
        var nowSec = now.value();

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

        // Page dots.
        var dotY = h * 0.94;
        var gap = 12;
        var x0 = cx - gap * (PAGES - 1) / 2;
        for (var p = 0; p < PAGES; p++) {
            dc.setColor(p == _page ? Graphics.COLOR_WHITE : Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(x0 + p * gap, dotY, 3);
        }
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
