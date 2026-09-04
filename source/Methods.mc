import Toybox.Lang;

// Calculation method presets, in the same order as the desktop app's
// methodOrder. The index is what the "method" setting stores.
(:glance)
module Methods {

    enum {
        DIYANET = 0,
        MWL = 1,
        ISNA = 2,
        UMM_AL_QURA = 3,
        EGYPTIAN = 4,
        KARACHI = 5,
        MOONSIGHTING = 6,
        KUWAIT = 7,
        QATAR = 8,
        SINGAPORE = 9,
        UOIF = 10,
        DUBAI = 11
    }

    const COUNT = 12;

    // Display names are proper nouns and stay unlocalized.
    function name(index as Number) as String {
        switch (index) {
            case MWL:          return "Muslim World League";
            case ISNA:         return "ISNA (North America)";
            case UMM_AL_QURA:  return "Umm al-Qura (Makkah)";
            case EGYPTIAN:     return "Egyptian General Authority";
            case KARACHI:      return "Univ. of Islamic Sciences, Karachi";
            case MOONSIGHTING: return "Moonsighting Committee";
            case KUWAIT:       return "Kuwait";
            case QATAR:        return "Qatar";
            case SINGAPORE:    return "Singapore (MUIS)";
            case UOIF:         return "UOIF (France)";
            case DUBAI:        return "Dubai";
            default:           return "Diyanet (Türkiye)";
        }
    }

    // Parameters for PrayerCalc.compute. Unknown indexes fall back to
    // Diyanet, like the desktop app.
    function params(index as Number, madhab as Number) as Dictionary {
        var fajr = 18.0d;
        var isha = 17.0d;
        var interval = 0;
        var adj = [0, 0, 0, 0, 0, 0];
        var moon = false;

        switch (index) {
            case MWL:
                adj = [0, 0, 1, 0, 0, 0];
                break;
            case ISNA:
                fajr = 15.0d; isha = 15.0d;
                adj = [0, 0, 1, 0, 0, 0];
                break;
            case UMM_AL_QURA:
                fajr = 18.5d; isha = 0.0d; interval = 90;
                break;
            case EGYPTIAN:
                fajr = 19.5d; isha = 17.5d;
                adj = [0, 0, 1, 0, 0, 0];
                break;
            case KARACHI:
                fajr = 18.0d; isha = 18.0d;
                adj = [0, 0, 1, 0, 0, 0];
                break;
            case MOONSIGHTING:
                fajr = 18.0d; isha = 18.0d; moon = true;
                adj = [0, 0, 5, 0, 3, 0];
                break;
            case KUWAIT:
                fajr = 18.0d; isha = 17.5d;
                break;
            case QATAR:
                fajr = 18.0d; isha = 0.0d; interval = 90;
                break;
            case SINGAPORE:
                fajr = 20.0d; isha = 18.0d;
                adj = [0, 0, 1, 0, 0, 0];
                break;
            case UOIF:
                fajr = 12.0d; isha = 12.0d;
                break;
            case DUBAI:
                fajr = 18.2d; isha = 18.2d;
                adj = [0, -3, 3, 3, 3, 0];
                break;
            default:
                // Diyanet (Türkiye): 18°/17° plus Diyanet's fixed "temkin"
                // (precaution) offsets. This is what the store apps get
                // wrong: without these offsets the times are off by several
                // minutes.
                adj = [-2, -7, 7, 4, 9, 2];
                break;
        }

        return {
            :fajrAngle => fajr,
            :ishaAngle => isha,
            :ishaInterval => interval,
            :adj => adj,
            :moonsighting => moon,
            :madhab => madhab,
            :highLat => PrayerCalc.HL_MIDDLE_OF_THE_NIGHT
        };
    }
}
