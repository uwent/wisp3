# What's new in WISP 3

What WISP 3 does that WISP 2012 (the version growers used through the 2026 season) didn't, for the grower announcement and the in-person demonstration and training. Grouped by area: how WISP works out the numbers first, then what growers see and use. A 100-word and a 250-word summary follow the list.

## Enhancements over WISP 2012

### Weather and forecast

- **Weather for each irrigation system's own location**, from Open-Meteo, for the grid cell about 9 km across around it. WISP 2012 took its weather from AgWeather, and about half of its pivots never moved from the default location, so their weather came from somewhere else.
- **The National Blend of Models** (NBM) first, from the National Weather Service, with Open-Meteo's best match of other models where it has no value. Of the models tested against AgWeather at 12 Wisconsin locations over two seasons, NBM matched best for both ET and rain.
- **Corrected against Wisconsin weather stations.** Checked against 80 Wisconet stations in 2025 and 2026, the models' solar radiation reads 15–20% high and their humidity runs dry. WISP corrects both hour by hour and works out reference ET itself, which brings it to within about 3% of the stations'.
- **Updated three times a day**, the past week kept up to date as the models revise it, and every past day kept from January 1.
- **A 16-day forecast,** with the 31 runs of the GFS ensemble forecast for the range of outcomes and the chance of rain. WISP 2012 had no forecast: it ran the last few days' water use forward in a straight line.

### Crop water use

- **Reference ET by FAO-56 Penman-Monteith**, the international standard, in its second edition (FAO, 2025), worked out hourly from the corrected weather.
- **Crop coefficients for each crop from FAO-56** (second edition, 2025), adjusted each day for wind and humidity. WISP 2012 used one percent cover table for every crop, fitted to AgWeather's ET.
- **Evaporation from wet soil counted separately** from the crop's own water use (FAO-56's dual crop coefficient), so water use is right while the canopy is small, after rain or irrigation, and after vine kill.
- **Water use eases toward harvest** as the crop matures, rather than staying at its peak until the season ends.
- **Water stress:** below the irrigation point a crop uses less water, as crops do (FAO-56's water stress coefficient). A field that falls behind dries more slowly than WISP 2012 had it, and WISP says how much of its normal water use the crop is managing.

### Checked against measurements

- **Flux towers in Central Sands potato fields:** six seasons (2018–2023) of eddy covariance towers run by UW–Madison researchers and funded in part by the WPVGA, which measure a crop's water use directly. WISP 3 comes within 3% of the towers at full canopy and 4% over the season. On the same comparison, WISP 2012's AgWeather ET ran 13% high.
- **Corn towers:** WISP's field corn water use agrees with a dryland corn tower's at full canopy.
- **Wisconet stations** for the weather corrections and reference ET (above).
- The analysis, data and scripts are public in WISP's source code, and summarized on WISP's About page.

### Crops and canopy

- **33 crops**, from potato, corn, soybean and snap bean to vegetables, small grains, sugar beet, sorghum, alfalfa and mint.
- **A typical canopy curve for each crop** (26 crops of their own, the rest following a similar crop's shape), from AquaCrop, FAO-56 and published Wisconsin trials, checked against the percent cover readings growers entered in WISP 2012. WISP 2012 had no curves: a crop with no readings had bare soil's water use all season.
- **Your cover readings correct the curve,** passing through each one and keeping the curve's shape between them, and WISP points out readings that don't fit.
- **Potato's canopy grows by growing degree days** (AquaCrop's method) at the field's location, so an early planting or a cool spring shifts it as the crop would.
- **Leaf area index (LAI) only where there's a real curve** (field corn). WISP 2012 applied the field corn curve to every crop set to LAI, and its sweet corn curve added water instead of using it.
- **Cuttings** for alfalfa and other perennials, each regrowing from stubble, and **vine kill** for potato.
- Each crop's curve, sources and notes are shown on the About page.

### Soils

- **11 soil types, up from 7**, adding loamy sand, sandy clay loam, silty clay loam and muck, with values from Wisconsin soil survey medians and published soil research.
- **The USDA soil survey on the map:** WISP suggests each field's soil from the survey, and the map can show the survey's soil types.
- Each field can still set its own field capacity and wilting point.

### Irrigation systems, fields and plantings

- **Every kind of irrigation system:** center pivots (with partial circles), linears, travelers, solid set and drip, and a plain location for a field with no irrigation.
- **Rainfed crops** followed alongside irrigated ones, with their water stress in place of irrigation advice.
- **Several plantings on a field:** plots side by side, each with its own balance and page, and one crop after another in a season.
- **Field outlines,** drawn on the map or read from a shapefile, KML or GeoJSON file, matched to fields automatically.
- **Irrigation groups:** systems that share a rain gauge, entered once.
- **An irrigation calculator** that turns run hours (from pump capacity) or a pivot's percent timer into inches.

### Dashboard and outlook

- **Every field at a glance,** as cards or a list, by system or with those needing water first, and a search by field name or crop.
- **An outlook for each planting:** "Irrigate by" a date, how much would refill it, and how sure the forecast is.
- **Rain ahead:** the week's chance and amount of rain for each part of the operation.
- **Log irrigation** for a whole system from the dashboard in a few taps, with the last irrigation and next rain shown.
- **Reminders** of readings that are due, and a check when a field has been below its irrigation point for two days with no irrigation entered.

### Charts

- **Interactive charts of each field's season:** soil water, rain and irrigation, crop water use and canopy, with the forecast and its range of outcomes ahead. Tap or hover for each day's values.
- **A weather page for each location,** with charts of rain, temperature, ET, growing degree days, soil moisture and temperature, sun, wind and humidity since January 1, zoomed together with one slider, and the data behind each one.
- **Any earlier day of a season** can be shown as it stood then, with what happened next.

### Maps

- **A map of the whole operation** on satellite imagery or a street map, with each system drawn to scale, each field's outline, and each planting's status.
- **Map layers:** radar now, measured rain over the last 24 and 72 hours, forecast rain for the next 1, 3 and 7 days, the U.S. Drought Monitor, soil types, and the weather zones with their past and coming week.
- **Find a place** by name, or go to your phone's location; a system's location can be typed or pasted in any common coordinate format.

### Daily entry

- **One page for the whole operation's day:** rain once per rain gauge, irrigation once per system, filling its fields.
- **A week view** to enter a week of rain and irrigation in one grid.
- **"Same as yesterday"** to repeat the day before's irrigation.
- **Your rain gauge or the model's rain,** set per farm or irrigation group, with the modeled rain always shown beside what you enter.

### Email

- **A morning email** of the fields needing water, the readings due and each location's weather, daily, every day of the year, or only when something needs water.
- **Sign in by email** with a one-time link or code, or with a password.

### Design and everyday use

- **A modern, clean design**, with a dark mode.
- **Works on a phone:** every page fits a small screen, and WISP can be added to the home screen like an app.
- **Metric units** for anyone who prefers them (millimeters, °C, hectares).
- **Seasons kept** from year to year, with last season's setup copied forward. WISP 2012 cleared every February.
- **Operations shared** with family, staff or a consultant, as owners or members.
- **CSV downloads** of a planting's season, the operation's season report, irrigation by system and the weather.
- **Help where it's needed:** an explanation beside each setting, a glossary of terms, and an About page on how WISP works.
- **An example farm** anyone can explore before signing up.
- **Accessible** to people using a screen reader or keyboard (WCAG 2.1 AA).

## In 100 words

WISP 3, the new Wisconsin Irrigation Scheduling Program, is ready for the 2027 season. It keeps WISP's familiar checkbook and rebuilds everything around it. Weather comes for each irrigation system's location, corrected against Wisconet stations, with a 16-day forecast showing when each field will need water and how sure that is. Crop water use follows international FAO-56 methods and has been checked against flux towers in Central Sands potato fields. A dashboard, map, interactive charts and a morning email work on your phone as well as your computer. Join us for a hands-on demonstration and training at [place] on [date].

## In 250 words

WISP 3, the new Wisconsin Irrigation Scheduling Program from UW–Madison, is ready for the 2027 season. It keeps the checkbook water balance method growers know and rebuilds everything around it.

How it works: Weather is fetched three times a day for each field from a high-resolution hourly gridded dataset, corrected against 80 Wisconet stations and flux towers so it fits Wisconsin best. WISP runs each field's water balance through the 16-day forecast and its range of scenarios, so you see which fields will need water, when, how much, and how sure the forecast is. Crop water use follows FAO-56, the international standard, with coefficients for 33 crops, evaporation from wet soil, and less water use when water runs short and crop growth slows down. Each crop follows a typical canopy curve that your cover readings correct. Checked against six seasons of flux towers measuring water use in Central Sands potato fields, WISP 3's tuned evapotranspiration estimates came within 4% over the season.

Every kind of irrigation system is supported, from center pivots and linears to travelers, solid set and drip, along with rainfed crops, plots within a field, and 11 soil types suggested from the USDA soil survey. A dashboard shows every field at a glance. The map adds field outlines, radar, measured and forecast rain, and the Drought Monitor. Interactive charts show each field's season and each location's weather, one page takes the whole operation's daily entries, and a morning email says what needs water. It all works on your phone, tablet, or computer.

Join us for a hands-on demonstration and training at [place] on [date].
