import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Time;
import Toybox.Timer;
import Toybox.WatchUi;

// Glance, three lines:
//   Fajr 04:56          <- next prayer and its time
//   ████████░░░░░░░░    <- how far we are between the previous prayer and it
//   in 7h 15m           <- time left
(:glance)
class PrayerGlanceView extends WatchUi.GlanceView {

    private var _timer as Timer.Timer?;

    function initialize() {
        GlanceView.initialize();
    }

    function onShow() as Void {
        _timer = new Timer.Timer();
        (_timer as Timer.Timer).start(method(:onTick), 30000, true);
    }

    function onHide() as Void {
        if (_timer != null) {
            (_timer as Timer.Timer).stop();
            _timer = null;
        }
    }

    function onTick() as Void {
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var now = Time.now();
        var s = Model.schedule(now);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);

        if (s == null) {
            dc.drawText(0, h * 0.25, Graphics.FONT_GLANCE, L10n.s(L10n.APP_NAME),
                Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.drawText(0, h * 0.75, Graphics.FONT_GLANCE, L10n.s(L10n.NO_LOCATION),
                Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }

        var nextIdx = s[:nextIdx] as Number;
        var nextAt = s[:nextAt] as Number;
        var prevAt = s[:prevAt] as Number;
        var nowSec = now.value();

        // Line 1: "Fajr 04:56"
        dc.drawText(0, h * 0.24, Graphics.FONT_GLANCE,
            Lang.format("$1$ $2$", [Fmt.prayerName(nextIdx), Fmt.clock(nextAt)]),
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        // Line 2: progress through the current interval.
        var barH = 6;
        var barY = h / 2 - barH / 2;
        var span = nextAt - prevAt;
        var frac = (span > 0) ? (nowSec - prevAt).toFloat() / span : 0.0;
        if (frac < 0.0) { frac = 0.0; }
        if (frac > 1.0) { frac = 1.0; }
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(0, barY, w, barH, barH / 2);
        var filled = (w * frac).toNumber();
        if (filled > 0) {
            dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(0, barY, filled < barH ? barH : filled, barH, barH / 2);
        }

        // Line 3: "in 7h 15m"
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(0, h * 0.76, Graphics.FONT_GLANCE, Fmt.timeLeft(nextAt - nowSec),
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}
