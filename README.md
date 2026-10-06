# NYC Airbnb Explorer — Tobi Adenola

A Shiny + Leaflet dashboard built with your original AB_NYC.csv. Includes clustered listing map, linked filters, summary metrics, price charts, searchable table, CSV export, and a log-price regression estimator.

## Run in RStudio

1. Extract this folder.
2. Install the packages once in the R console:

```r
install.packages(c("shiny", "leaflet", "ggplot2", "DT"))
```

3. Open app.R and click **Run App**. Alternatively, from the parent directory:

```r
shiny::runApp("nyc-airbnb-shiny")
```

Requires R 4.1 or later. Internet is needed for map tiles. No Mapbox account or key is needed.

## Hosting

This is an R application and needs an R-capable server. To publish on shinyapps.io, configure your own account using its deployment instructions, then run:

```r
install.packages("rsconnect")
rsconnect::deployApp("nyc-airbnb-shiny")
```

The app has not been published. Account setup and deployment require your hosting account.

## Analysis choices

- Original input: 48,895 listings. Prices strictly above 0 and below 1,000 are retained.
- Missing reviews per month are replaced with zero; missing review dates are left missing.
- Regression matches the original report: log(price) ~ room_type + neighbourhood_group + reviews_per_month.
- exp(prediction) estimates conditional median price. A transformed 95% prediction interval is displayed; no held-out accuracy is claimed.
- Filters affect map, charts, listing table, and export. Regression uses the full cleaned dataset.
- These are historical listing prices, not current quotes or verified availability.
- Listing text is escaped in map popups and tables.

## Validation

Input columns, cleaning counts, coordinate eligibility, and the regression design were checked against the supplied CSV and original report. This environment has no R runtime; end-to-end Shiny execution remains to be verified in RStudio. See VALIDATION.txt for data checks.

Official references: https://shiny.posit.co/r/getstarted/shiny-basics/lesson1/ and https://rstudio.github.io/leaflet/
