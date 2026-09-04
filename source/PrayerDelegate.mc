import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// Full-view input: UP/DOWN page through days, START/SELECT refreshes GPS,
// MENU opens the settings.
class PrayerDelegate extends WatchUi.BehaviorDelegate {

    private var _view as PrayerView;

    function initialize(view as PrayerView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onSelect() as Boolean {
        _view.requestGps();
        return true;
    }

    // DOWN / swipe up: next day. UP / swipe down: previous day.
    function onNextPage() as Boolean {
        _view.nextPage();
        return true;
    }

    function onPreviousPage() as Boolean {
        _view.previousPage();
        return true;
    }

    function onMenu() as Boolean {
        var menu = new WatchUi.Menu2({ :title => L10n.s(L10n.SETTINGS) });
        menu.addItem(new WatchUi.MenuItem(L10n.s(L10n.LOCATION),
            Model.presetName(Model.locationIndex()), :location, null));
        menu.addItem(new WatchUi.MenuItem(L10n.s(L10n.CALC_METHOD),
            Methods.name(Model.methodIndex()), :method, null));
        menu.addItem(new WatchUi.MenuItem(L10n.s(L10n.MADHAB),
            madhabName(Model.madhab()), :madhab, null));
        menu.addItem(new WatchUi.MenuItem(L10n.s(L10n.LANGUAGE),
            L10n.languageName(Model.language()), :language, null));
        WatchUi.pushView(menu, new SettingsMenuDelegate(), WatchUi.SLIDE_UP);
        return true;
    }
}

function madhabName(idx as Number) as String {
    return L10n.s(idx == PrayerCalc.MADHAB_HANAFI ? L10n.MADHAB_HANAFI : L10n.MADHAB_STANDARD);
}

// Top-level settings menu: each entry opens a picker.
class SettingsMenuDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        var key;
        var title;
        var count;
        var current;
        if (id == :location) {
            key = "location"; title = L10n.LOCATION; count = Model.LOC_COUNT; current = Model.locationIndex();
        } else if (id == :method) {
            key = "method"; title = L10n.CALC_METHOD; count = Methods.COUNT; current = Model.methodIndex();
        } else if (id == :madhab) {
            key = "madhab"; title = L10n.MADHAB; count = 2; current = Model.madhab();
        } else if (id == :language) {
            key = "language"; title = L10n.LANGUAGE; count = L10n.COUNT; current = Model.language();
        } else {
            return;
        }
        var selected = L10n.s(L10n.SELECTED);
        var menu = new WatchUi.Menu2({ :title => L10n.s(title) });
        for (var i = 0; i < count; i++) {
            var label;
            if (id == :location) {
                label = Model.presetName(i);
            } else if (id == :method) {
                label = Methods.name(i);
            } else if (id == :madhab) {
                label = madhabName(i);
            } else {
                label = L10n.languageName(i);
            }
            menu.addItem(new WatchUi.MenuItem(label, i == current ? selected : null, i, null));
        }
        WatchUi.pushView(menu, new PickerDelegate(key, item), WatchUi.SLIDE_LEFT);
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

// Writes the chosen index to the app property, so the phone-side settings
// and the on-watch menu stay one source of truth.
class PickerDelegate extends WatchUi.Menu2InputDelegate {

    private var _key as String;
    private var _parent as WatchUi.MenuItem;

    function initialize(key as String, parent as WatchUi.MenuItem) {
        Menu2InputDelegate.initialize();
        _key = key;
        _parent = parent;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var value = item.getId() as Number;
        try {
            Application.Properties.setValue(_key, value);
        } catch (e) {
            // Read-only properties would throw; nothing more to do.
        }
        Model.invalidate();
        _parent.setSubLabel(item.getLabel());
        // A language change relabels the whole settings menu; simplest is to
        // close it along with the picker.
        if (_key.equals("language")) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        }
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        WatchUi.requestUpdate();
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}
