import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;

// User-visible strings, selectable independently of the watch language.
//
// Connect IQ's resource strings always follow the device language, so a
// "Language" setting needs its own table. The languages match the desktop
// app minus Arabic, Japanese and Chinese: the watch draws with its firmware
// fonts, which lack those glyphs on most regional firmwares.
(:glance)
module L10n {

    // Values of the "language" setting.
    enum { DEVICE = 0, EN = 1, TR = 2, RU = 3, ES = 4, FR = 5 }
    const COUNT = 6;

    // String keys. FAJR..ISHA must stay first and in prayer order.
    enum {
        FAJR = 0, SUNRISE, DHUHR, ASR, MAGHRIB, ISHA,
        NO_LOCATION, PRESS_FOR_GPS, ACQUIRING, SET_CUSTOM_HINT,
        TIME_LEFT_HM, TIME_LEFT_M,
        SETTINGS, LOCATION, CALC_METHOD, MADHAB, MADHAB_STANDARD, MADHAB_HANAFI,
        LOCATION_AUTO, LOCATION_CUSTOM, SELECTED, LANGUAGE, LANG_DEVICE, APP_NAME, TODAY,
        QIBLA, NO_COMPASS, DIR_N, DIR_E, DIR_S, DIR_W
    }

    var _lang as Number = -1;
    var _table as Array<String>? = null;

    // Forget the cached table (settings changed).
    function reset() as Void {
        _lang = -1;
        _table = null;
    }

    // The language in effect: the setting, or the device language mapped to
    // one we have (English otherwise).
    function current() as Number {
        var setting = Model.language();
        if (setting != DEVICE) { return setting; }
        var sys = System.getDeviceSettings().systemLanguage;
        if (sys == System.LANGUAGE_TUR) { return TR; }
        if (sys == System.LANGUAGE_RUS) { return RU; }
        if (sys == System.LANGUAGE_SPA) { return ES; }
        if (sys == System.LANGUAGE_FRE) { return FR; }
        return EN;
    }

    function s(key as Number) as String {
        var lang = current();
        if (_table == null || lang != _lang) {
            _lang = lang;
            _table = table(lang);
        }
        return (_table as Array<String>)[key];
    }

    // Names for the language picker, each in its own language.
    function languageName(idx as Number) as String {
        switch (idx) {
            case EN: return "English";
            case TR: return "Türkçe";
            case RU: return "Русский";
            case ES: return "Español";
            case FR: return "Français";
            default: return s(LANG_DEVICE);
        }
    }

    function table(lang as Number) as Array<String> {
        switch (lang) {
            case TR: return [
                "İmsak", "Güneş", "Öğle", "İkindi", "Akşam", "Yatsı",
                "Konum yok", "GPS için START'a basın", "GPS...",
                "Koordinatları telefondaki Connect IQ uygulamasından girin",
                "$1$ sa $2$ dk sonra", "$1$ dk sonra",
                "Ayarlar", "Konum", "Hesaplama yöntemi", "İkindi hesabı",
                "Standart (Şafii, Maliki, Hanbeli)", "Hanefi",
                "Mevcut konum", "Özel", "Seçili", "Dil", "Cihaz dili", "Namaz Vakitleri", "Bugün",
                "Kıble", "Pusula yok", "K", "D", "G", "B"];
            case RU: return [
                "Фаджр", "Восход", "Зухр", "Аср", "Магриб", "Иша",
                "Нет местоположения", "Нажмите START для GPS", "GPS...",
                "Введите координаты в приложении Connect IQ",
                "через $1$ ч $2$ мин", "через $1$ мин",
                "Настройки", "Местоположение", "Метод расчёта", "Расчёт Асра",
                "Стандарт (Шафии, Малики, Ханбали)", "Ханафи",
                "Текущее местоположение", "Своё", "Выбрано", "Язык", "Язык устройства", "Время намаза", "Сегодня",
                "Кибла", "Нет компаса", "С", "В", "Ю", "З"];
            case ES: return [
                "Fajr", "Amanecer", "Dhuhr", "Asr", "Magrib", "Isha",
                "Sin ubicación", "Pulsa START para GPS", "GPS...",
                "Introduce las coordenadas en la app Connect IQ",
                "en $1$h $2$m", "en $1$m",
                "Ajustes", "Ubicación", "Método de cálculo", "Método de Asr",
                "Estándar (Shafi, Maliki, Hanbali)", "Hanafi",
                "Ubicación actual", "Personalizada", "Seleccionado", "Idioma", "Idioma del dispositivo", "Horarios de oración", "Hoy",
                "Alquibla", "Sin brújula", "N", "E", "S", "O"];
            case FR: return [
                "Fajr", "Lever du soleil", "Dhohr", "Asr", "Maghreb", "Icha",
                "Pas de position", "Appuyez sur START pour le GPS", "GPS...",
                "Saisissez les coordonnées dans l'app Connect IQ",
                "dans $1$h $2$m", "dans $1$m",
                "Réglages", "Lieu", "Méthode de calcul", "Méthode pour l'Asr",
                "Standard (Chaféite, Malikite, Hanbalite)", "Hanafite",
                "Position actuelle", "Personnalisé", "Sélectionné", "Langue", "Langue de l'appareil", "Horaires de prière", "Aujourd'hui",
                "Qibla", "Pas de boussole", "N", "E", "S", "O"];
            default: return [
                "Fajr", "Sunrise", "Dhuhr", "Asr", "Maghrib", "Isha",
                "No location", "Press START for GPS", "GPS...",
                "Enter coordinates in the Connect IQ phone app",
                "in $1$h $2$m", "in $1$m",
                "Settings", "Location", "Calculation method", "Asr method",
                "Standard (Shafi, Maliki, Hanbali)", "Hanafi",
                "Current location", "Custom", "Selected", "Language", "Device language", "Prayer Times", "Today",
                "Qibla", "No compass", "N", "E", "S", "W"];
        }
    }

    // Short month names (index 1..12) and weekday names (1 = Sunday).
    function months(lang as Number) as Array<String> {
        switch (lang) {
            case TR: return ["", "Oca", "Şub", "Mar", "Nis", "May", "Haz", "Tem", "Ağu", "Eyl", "Eki", "Kas", "Ara"];
            case RU: return ["", "янв", "фев", "мар", "апр", "май", "июн", "июл", "авг", "сен", "окт", "ноя", "дек"];
            case ES: return ["", "ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"];
            case FR: return ["", "janv.", "févr.", "mars", "avr.", "mai", "juin", "juil.", "août", "sept.", "oct.", "nov.", "déc."];
            default: return ["", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
        }
    }

    function weekdays(lang as Number) as Array<String> {
        switch (lang) {
            case TR: return ["", "Paz", "Pzt", "Sal", "Çar", "Per", "Cum", "Cmt"];
            case RU: return ["", "Вс", "Пн", "Вт", "Ср", "Чт", "Пт", "Сб"];
            case ES: return ["", "dom", "lun", "mar", "mié", "jue", "vie", "sáb"];
            case FR: return ["", "dim", "lun", "mar", "mer", "jeu", "ven", "sam"];
            default: return ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
        }
    }

    // "Thu 4 Sep" in the selected language; with the device language the
    // watch's own localized names are used, so unsupported languages still
    // get a native date.
    function dateHeader(moment as Time.Moment) as String {
        if (Model.language() == DEVICE) {
            var info = Gregorian.info(moment, Time.FORMAT_MEDIUM);
            return Lang.format("$1$ $2$ $3$", [info.day_of_week, info.day, info.month]);
        }
        var lang = current();
        var info = Gregorian.info(moment, Time.FORMAT_SHORT);
        var mon = months(lang)[info.month as Number];
        var dow = weekdays(lang)[info.day_of_week as Number];
        return Lang.format("$1$ $2$ $3$", [dow, info.day, mon]);
    }
}
