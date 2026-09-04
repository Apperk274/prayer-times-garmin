import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

(:glance)
class PrayerTimesApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() {
        var view = new PrayerView();
        return [view, new PrayerDelegate(view)];
    }

    function getGlanceView() {
        return [new PrayerGlanceView()];
    }

    // Settings edited on the phone (or from the on-watch menu, which writes
    // the same properties).
    function onSettingsChanged() as Void {
        Model.invalidate();
        WatchUi.requestUpdate();
    }
}
