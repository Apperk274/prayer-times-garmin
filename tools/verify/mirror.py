#!/usr/bin/env python3
"""Statement-for-statement Python mirror of source/PrayerCalc.mc.

Monkey C cannot run outside the Connect IQ simulator, so this file mirrors
the Monkey C port (same function names, same operation order, same integer
truncation points) and is checked against the adhango reference output in
fixtures.txt:

    cd tools/fixtures && go run . > ../verify/fixtures.txt
    python3 tools/verify/mirror.py tools/verify/fixtures.txt

Python floats are IEEE doubles, like Monkey C's Double, so an exact match
here validates the algorithm transcription. What it cannot validate is the
Monkey C compiler/runtime itself; source/PrayerCalcTest.mc covers that in
the simulator with the same fixtures.
"""
import math
import sys

PI = 3.14159265358979323846
MADHAB_STANDARD, MADHAB_HANAFI = 0, 1
HL_MIDDLE_OF_THE_NIGHT, HL_SEVENTH_OF_THE_NIGHT, HL_TWILIGHT_ANGLE = 0, 1, 2


def to_number(x):
    """Monkey C Double.toNumber(): truncation toward zero."""
    return int(x)


def mc_round(x):
    """Monkey C Math.round: nearest integer, halves away from zero."""
    return math.floor(abs(x) + 0.5) * (1 if x >= 0 else -1)


def rad(d): return d * (PI / 180.0)
def deg(r): return r * (180.0 / PI)
def normalize(v, mx): return v - mx * math.floor(v / mx)
def unwind(a): return normalize(a, 360.0)


def closest_angle(a):
    if -180.0 <= a <= 180.0:
        return a
    return a - 360.0 * mc_round(a / 360.0)


def julian_day(year, month, day):
    y, m = year, month
    if month <= 2:
        y = year - 1
        m = month + 12
    a = math.floor(y / 100.0)
    b = math.floor(2.0 - a + a / 4.0)
    i0 = math.floor(365.25 * (y + 4716))
    i1 = math.floor(30.6001 * (m + 1))
    return i0 + i1 + b + day - 1524.5


def midnight_utc(year, month, day):
    return to_number((julian_day(year, month, day) - 2440587.5) * 86400.0)


def is_leap_year(year):
    return year % 4 == 0 and not (year % 100 == 0 and year % 400 != 0)


def days_in_month(year, month):
    if month == 2:
        return 29 if is_leap_year(year) else 28
    if month in (4, 6, 9, 11):
        return 30
    return 31


def next_day(year, month, day):
    if day < days_in_month(year, month):
        return [year, month, day + 1]
    if month < 12:
        return [year, month + 1, 1]
    return [year + 1, 1, 1]


def day_of_year(year, month, day):
    return to_number(julian_day(year, month, day) - julian_day(year, 1, 1)) + 1


def solar_coordinates(jd):
    T = (jd - 2451545.0) / 36525.0
    T2 = T * T
    T3 = T2 * T
    L0 = unwind(280.4664567 + 36000.76983 * T + 0.0003032 * T2)
    Lp = unwind(218.3165 + 481267.8813 * T)
    Om = unwind(125.04452 - 1934.136261 * T + 0.0020708 * T2 + T3 / 450000.0)
    M = unwind(357.52911 + 35999.05029 * T - 0.0001537 * T2)
    Mr = rad(M)
    C = ((1.914602 - 0.004817 * T - 0.000014 * T2) * math.sin(Mr)
         + (0.019993 - 0.000101 * T) * math.sin(2.0 * Mr)
         + 0.000289 * math.sin(3.0 * Mr))
    OmRaw = 125.04 - 1934.136 * T
    lam = rad(unwind(L0 + C - 0.00569 - 0.00478 * math.sin(rad(OmRaw))))
    JD = T * 36525.0 + 2451545.0
    theta0 = unwind(280.46061837 + 360.98564736629 * (JD - 2451545.0)
                    + 0.000387933 * T2 - T3 / 38710000.0)
    dPsi = ((-17.2 / 3600.0) * math.sin(rad(Om))
            - (1.32 / 3600.0) * math.sin(2.0 * rad(L0))
            - (0.23 / 3600.0) * math.sin(2.0 * rad(Lp))
            + (0.21 / 3600.0) * math.sin(2.0 * rad(Om)))
    dEps = ((9.2 / 3600.0) * math.cos(rad(Om))
            + (0.57 / 3600.0) * math.cos(2.0 * rad(L0))
            + (0.10 / 3600.0) * math.cos(2.0 * rad(Lp))
            - (0.09 / 3600.0) * math.cos(2.0 * rad(Om)))
    eps0 = 23.439291 - 0.013004167 * T - 0.0000001639 * T2 + 0.0000005036 * T3
    epsApp = rad(eps0 + 0.00256 * math.cos(rad(OmRaw)))
    declination = deg(math.asin(math.sin(epsApp) * math.sin(lam)))
    right_ascension = unwind(deg(math.atan2(math.cos(epsApp) * math.sin(lam), math.cos(lam))))
    sidereal = theta0 + dPsi * math.cos(rad(eps0 + dEps))
    return [declination, right_ascension, sidereal]


def interpolate(y2, y1, y3, n):
    a = y2 - y1
    b = y3 - y2
    c = b - a
    return y2 + (n / 2.0) * (a + b + n * c)


def interpolate_angles(y2, y1, y3, n):
    a = unwind(y2 - y1)
    b = unwind(y3 - y2)
    c = b - a
    return y2 + (n / 2.0) * (a + b + n * c)


def altitude(lat, dec, H):
    term1 = math.sin(rad(lat)) * math.sin(rad(dec))
    term2 = math.cos(rad(lat)) * math.cos(rad(dec)) * math.cos(rad(H))
    return deg(math.asin(term1 + term2))


class SolarTime:
    def __init__(self, year, month, day, lat, lon):
        self._lat = lat
        self._lon = lon
        jd = julian_day(year, month, day)
        self._prev = solar_coordinates(jd - 1.0)
        self._sol = solar_coordinates(jd)
        self._next = solar_coordinates(jd + 1.0)
        self._m0 = normalize((self._sol[1] - lon - self._sol[2]) / 360.0, 1.0)
        self.transit = self._corrected_transit()
        h0 = -50.0 / 60.0
        self.sunrise = self.hour_angle(h0, False)
        self.sunset = self.hour_angle(h0, True)

    def _corrected_transit(self):
        Lw = -self._lon
        theta = unwind(self._sol[2] + 360.985647 * self._m0)
        alpha = unwind(interpolate_angles(self._sol[1], self._prev[1], self._next[1], self._m0))
        H = closest_angle(theta - Lw - alpha)
        dm = H / -360.0
        return (self._m0 + dm) * 24.0

    def hour_angle(self, h0, after_transit):
        Lw = -self._lon
        dec2 = self._sol[0]
        term1 = math.sin(rad(h0)) - math.sin(rad(self._lat)) * math.sin(rad(dec2))
        term2 = math.cos(rad(self._lat)) * math.cos(rad(dec2))
        cosH0 = term1 / term2
        if cosH0 > 1.0 or cosH0 < -1.0:
            return None
        H0 = deg(math.acos(cosH0))
        m = self._m0 + H0 / 360.0 if after_transit else self._m0 - H0 / 360.0
        theta = unwind(self._sol[2] + 360.985647 * m)
        alpha = unwind(interpolate_angles(self._sol[1], self._prev[1], self._next[1], m))
        delta = interpolate(self._sol[0], self._prev[0], self._next[0], m)
        H = theta - Lw - alpha
        h = altitude(self._lat, delta, H)
        term3 = h - h0
        term4 = 360.0 * math.cos(rad(delta)) * math.cos(rad(self._lat)) * math.sin(rad(H))
        dm = term3 / term4
        return (m + dm) * 24.0

    def afternoon(self, shadow):
        tangent = abs(self._lat - self._sol[0])
        inverse = shadow + math.tan(rad(tangent))
        angle = deg(math.atan(1.0 / inverse))
        return self.hour_angle(angle, True)


def to_seconds(hours):
    h = math.floor(hours)
    m = math.floor((hours - h) * 60.0)
    s = math.floor((hours - (h + m / 60.0)) * 3600.0)
    return to_number(h * 3600.0 + m * 60.0 + s)


def round_to_minute(t):
    r = t + 30
    return r - (r % 60)


def season_adjusted(lat, doy, year, a, b, c, d):
    dyy = days_since_solstice(doy, year, lat)
    if dyy < 91:
        return a + (b - a) / 91.0 * dyy
    if dyy < 137:
        return b + (c - b) / 46.0 * (dyy - 91)
    if dyy < 183:
        return c + (d - c) / 46.0 * (dyy - 137)
    if dyy < 229:
        return d + (c - d) / 46.0 * (dyy - 183)
    if dyy < 275:
        return c + (b - c) / 46.0 * (dyy - 229)
    return b + (a - b) / 91.0 * (dyy - 275)


def season_adjusted_morning_twilight(lat, doy, year, sunrise):
    ab = abs(lat)
    a = 75.0 + (28.65 / 55.0) * ab
    b = 75.0 + (19.44 / 55.0) * ab
    c = 75.0 + (32.74 / 55.0) * ab
    d = 75.0 + (48.10 / 55.0) * ab
    adjustment = season_adjusted(lat, doy, year, a, b, c, d)
    return sunrise - to_number(mc_round(adjustment * 60.0))


def season_adjusted_evening_twilight(lat, doy, year, sunset):
    ab = abs(lat)
    a = 75.0 + (25.60 / 55.0) * ab
    b = 75.0 + (2.050 / 55.0) * ab
    c = 75.0 - (9.210 / 55.0) * ab
    d = 75.0 + (6.140 / 55.0) * ab
    adjustment = season_adjusted(lat, doy, year, a, b, c, d)
    return sunset + to_number(mc_round(adjustment * 60.0))


def days_since_solstice(doy, year, lat):
    leap = is_leap_year(year)
    days_in_year = 366 if leap else 365
    if lat >= 0.0:
        n = doy + 10
        if n >= days_in_year:
            n -= days_in_year
        return n
    s = doy - (173 if leap else 172)
    if s < 0:
        s += days_in_year
    return s


def night_portions(p):
    rule = p["highLat"]
    if rule == HL_SEVENTH_OF_THE_NIGHT:
        return [1.0 / 7.0, 1.0 / 7.0]
    if rule == HL_TWILIGHT_ANGLE:
        return [p["fajrAngle"] / 60.0, p["ishaAngle"] / 60.0]
    return [0.5, 0.5]


def mc_int_div(a, b):
    """Monkey C Number division truncates toward zero."""
    q = abs(a) // abs(b)
    return q if (a >= 0) == (b > 0) else -q


def compute(year, month, day, lat, lon, p):
    midnight = midnight_utc(year, month, day)
    st = SolarTime(year, month, day, lat, lon)
    if st.sunrise is None or st.sunset is None:
        return None
    tm = next_day(year, month, day)
    st_tomorrow = SolarTime(tm[0], tm[1], tm[2], lat, lon)
    if st_tomorrow.sunrise is None:
        return None

    transit = midnight + to_seconds(st.transit)
    sunrise = midnight + to_seconds(st.sunrise)
    sunset = midnight + to_seconds(st.sunset)
    tomorrow_sunrise = midnight + 86400 + to_seconds(st_tomorrow.sunrise)
    night = tomorrow_sunrise - sunset

    shadow = 2 if p["madhab"] == MADHAB_HANAFI else 1
    asr_hours = st.afternoon(shadow)
    if asr_hours is None:
        return None
    asr = midnight + to_seconds(asr_hours)

    moon = p["moonsighting"] is True
    portions = night_portions(p)
    doy = day_of_year(year, month, day)

    fajr = None
    fajr_hours = st.hour_angle(-p["fajrAngle"], False)
    if fajr_hours is not None:
        fajr = midnight + to_seconds(fajr_hours)
    if moon and lat >= 55.0:
        fajr = sunrise - mc_int_div(night, 7)

    if moon:
        safe_fajr = season_adjusted_morning_twilight(lat, doy, year, sunrise)
    else:
        safe_fajr = sunrise - to_number(portions[0] * night)
    if fajr is None or fajr < safe_fajr:
        fajr = safe_fajr

    interval = p["ishaInterval"]
    if interval > 0:
        isha = sunset + interval * 60
    else:
        isha = None
        isha_hours = st.hour_angle(-p["ishaAngle"], True)
        if isha_hours is not None:
            isha = midnight + to_seconds(isha_hours)
        if moon and lat >= 55.0:
            isha = sunset + mc_int_div(night, 7)
        if moon:
            safe_isha = season_adjusted_evening_twilight(lat, doy, year, sunset)
        else:
            safe_isha = sunset + to_number(portions[1] * night)
        if isha is None or isha > safe_isha:
            isha = safe_isha

    adj = p["adj"]
    return [
        round_to_minute(fajr + adj[0] * 60),
        round_to_minute(sunrise + adj[1] * 60),
        round_to_minute(transit + adj[2] * 60),
        round_to_minute(asr + adj[3] * 60),
        round_to_minute(sunset + adj[4] * 60),
        round_to_minute(isha + adj[5] * 60),
    ]


# Mirror of Methods.params.
def method_params(index, madhab):
    fajr, isha, interval, adj, moon = 18.0, 17.0, 0, [0, 0, 0, 0, 0, 0], False
    if index == 1:
        adj = [0, 0, 1, 0, 0, 0]
    elif index == 2:
        fajr, isha, adj = 15.0, 15.0, [0, 0, 1, 0, 0, 0]
    elif index == 3:
        fajr, isha, interval = 18.5, 0.0, 90
    elif index == 4:
        fajr, isha, adj = 19.5, 17.5, [0, 0, 1, 0, 0, 0]
    elif index == 5:
        fajr, isha, adj = 18.0, 18.0, [0, 0, 1, 0, 0, 0]
    elif index == 6:
        fajr, isha, moon, adj = 18.0, 18.0, True, [0, 0, 5, 0, 3, 0]
    elif index == 7:
        fajr, isha = 18.0, 17.5
    elif index == 8:
        fajr, isha, interval = 18.0, 0.0, 90
    elif index == 9:
        fajr, isha, adj = 20.0, 18.0, [0, 0, 1, 0, 0, 0]
    elif index == 10:
        fajr, isha = 12.0, 12.0
    elif index == 11:
        fajr, isha, adj = 18.2, 18.2, [0, -3, 3, 3, 3, 0]
    else:
        adj = [-2, -7, 7, 4, 9, 2]
    return {"fajrAngle": fajr, "ishaAngle": isha, "ishaInterval": interval,
            "adj": adj, "moonsighting": moon, "madhab": madhab,
            "highLat": HL_MIDDLE_OF_THE_NIGHT}


def main(path):
    total = failed = 0
    with open(path) as f:
        for line in f:
            if line.startswith("#") or not line.strip():
                continue
            parts = line.split()
            name = parts[0]
            y, m, d = int(parts[1]), int(parts[2]), int(parts[3])
            lat, lon = float(parts[4]), float(parts[5])
            mi, madhab = int(parts[6]), int(parts[7])
            expected = [int(x) for x in parts[8:14]]
            got = compute(y, m, d, lat, lon, method_params(mi, madhab))
            total += 1
            if got != expected:
                failed += 1
                diff = [g - e for g, e in zip(got, expected)] if got else None
                print(f"FAIL {name}: expected {expected} got {got} diff(s) {diff}")
    print(f"{total - failed}/{total} cases match adhango")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "tools/verify/fixtures.txt"))
