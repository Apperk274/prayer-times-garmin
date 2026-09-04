// Command fixtures prints reference prayer times computed with adhango, the
// library the desktop app uses, for a fixed set of dates, places and
// methods. Its output is pasted into source/PrayerCalcTest.mc (Monkey C
// unit tests, run in the Connect IQ simulator) and read by
// tools/verify/mirror.py.
//
//	go run . > ../verify/fixtures.txt
//
// Output lines: <case> <year> <month> <day> <lat> <lon> <method> <madhab> <6 epoch seconds>
package main

import (
	"fmt"
	"time"

	calc "github.com/mnadev/adhango/pkg/calc"
	data "github.com/mnadev/adhango/pkg/data"
	util "github.com/mnadev/adhango/pkg/util"
)

// Same order as the desktop app's methodOrder and Methods.mc.
var methods = []string{
	"diyanet", "mwl", "isna", "umm_al_qura", "egyptian", "karachi",
	"moonsighting", "kuwait", "qatar", "singapore", "uoif", "dubai",
}

func diyanet() *calc.CalculationParameters {
	return calc.NewCalculationParametersBuilder().
		SetFajrAngle(18.0).
		SetIshaAngle(17.0).
		SetMethodAdjustments(calc.PrayerAdjustments{
			FajrAdj: -2, SunriseAdj: -7, DhuhrAdj: 7, AsrAdj: 4, MaghribAdj: 9, IshaAdj: 2,
		}).
		Build()
}

func params(idx int, madhab calc.AsrJuristicMethod) *calc.CalculationParameters {
	var p *calc.CalculationParameters
	switch methods[idx] {
	case "diyanet":
		p = diyanet()
	case "mwl":
		p = calc.GetMethodParameters(calc.MUSLIM_WORLD_LEAGUE)
	case "isna":
		p = calc.GetMethodParameters(calc.NORTH_AMERICA)
	case "umm_al_qura":
		p = calc.GetMethodParameters(calc.UMM_AL_QURA)
	case "egyptian":
		p = calc.GetMethodParameters(calc.EGYPTIAN)
	case "karachi":
		p = calc.GetMethodParameters(calc.KARACHI)
	case "moonsighting":
		p = calc.GetMethodParameters(calc.MOON_SIGHTING_COMMITTEE)
	case "kuwait":
		p = calc.GetMethodParameters(calc.KUWAIT)
	case "qatar":
		p = calc.GetMethodParameters(calc.QATAR)
	case "singapore":
		p = calc.GetMethodParameters(calc.SINGAPORE)
	case "uoif":
		p = calc.GetMethodParameters(calc.UOIF)
	case "dubai":
		p = calc.GetMethodParameters(calc.DUBAI)
	}
	p.Madhab = madhab
	return p
}

type place struct {
	name     string
	lat, lon float64
}

var places = []place{
	{"Istanbul", 41.0082, 28.9784},
	{"Ankara", 39.9334, 32.8597},
	{"Izmir", 38.4237, 27.1428},
	{"Mecca", 21.4225, 39.8262},
	{"London", 51.5074, -0.1278},
	{"NewYork", 40.7128, -74.0060},
	{"Oslo", 59.9139, 10.7522},
	{"Sydney", -33.8688, 151.2093},
}

var dates = [][3]int{
	{2026, 1, 15}, {2026, 2, 28}, {2026, 3, 1}, {2026, 6, 21},
	{2026, 9, 4}, {2026, 12, 21}, {2028, 2, 29}, {2030, 12, 31},
}

func main() {
	n := 0
	for _, d := range dates {
		for _, pl := range places {
			for mi := range methods {
				for _, madhab := range []calc.AsrJuristicMethod{calc.SHAFI_HANBALI_MALIKI, calc.HANAFI} {
					// Keep the set manageable: Hanafi only for Diyanet
					// and Karachi (the two where it is plausible).
					if madhab == calc.HANAFI && mi != 0 && mi != 5 {
						continue
					}
					// Every method for Istanbul; the others exercise the
					// geographic edge cases with a few methods.
					if pl.name != "Istanbul" && mi != 0 && mi != 1 && mi != 3 && mi != 6 {
						continue
					}
					date := data.NewDateComponents(time.Date(d[0], time.Month(d[1]), d[2], 0, 0, 0, 0, time.UTC))
					coords, err := util.NewCoordinates(pl.lat, pl.lon)
					if err != nil {
						panic(err)
					}
					pt, err := calc.NewPrayerTimes(coords, date, params(mi, madhab))
					if err != nil {
						fmt.Printf("# %s %d-%02d-%02d %s: %v\n", pl.name, d[0], d[1], d[2], methods[mi], err)
						continue
					}
					fmt.Printf("%s_%d%02d%02d_%s_%d %d %d %d %.4f %.4f %d %d %d %d %d %d %d %d\n",
						pl.name, d[0], d[1], d[2], methods[mi], madhab,
						d[0], d[1], d[2], pl.lat, pl.lon, mi, madhab,
						pt.Fajr.Unix(), pt.Sunrise.Unix(), pt.Dhuhr.Unix(), pt.Asr.Unix(), pt.Maghrib.Unix(), pt.Isha.Unix())
					n++
				}
			}
		}
	}
	fmt.Printf("# %d cases\n", n)
}
