library(shiny)
library(leaflet)
library(ggplot2)
library(DT)

raw <- read.csv('data/AB_NYC.csv', stringsAsFactors = FALSE)
raw$reviews_per_month[is.na(raw$reviews_per_month)] <- 0
d <- raw[is.finite(raw$price) & raw$price > 0 & raw$price < 1000, ]
d$neighbourhood_group <- factor(d$neighbourhood_group)
d$room_type <- factor(d$room_type)
d$log_price <- log(d$price)
model <- lm(log_price ~ room_type + neighbourhood_group + reviews_per_month, data = d)
money <- function(x) paste0('$', format(round(x), big.mark = ',', trim = TRUE))
boros <- levels(d$neighbourhood_group)
rooms <- levels(d$room_type)
theme_set(theme_minimal(base_size = 13))

ui <- fluidPage(
  tags$head(tags$style(HTML('
    body {background:#f3f5f8;color:#172b40;font-family:Arial,sans-serif;}
    .hero {background:#132d46;color:white;padding:28px 32px;border-radius:16px;margin:20px 0;}
    .hero h1 {font-weight:700;margin-top:0;} .hero p {color:#c7d6e4;}
    .well {background:white;border:0;border-radius:14px;box-shadow:0 3px 16px #152b4010;}
    .metric {background:white;padding:20px;border-radius:12px;margin-bottom:20px;}
    .metric strong {display:block;font-size:29px;color:#087f8c;}
    .nav-tabs {margin-bottom:18px;} .tab-content {background:white;padding:20px;border-radius:12px;}
    .btn {border-radius:8px;} .help-block {font-size:12px;}
  '))),
  div(class='hero', h1('NYC Airbnb Explorer'),
      p('Explore neighbourhoods. Compare prices. Understand listing patterns.'),
      tags$small('A data portfolio project by Tobi Adenola • Historical listings; not live booking inventory')),
  sidebarLayout(
    sidebarPanel(width=3,
      h4('Find your slice of the city'),
      selectInput('borough', 'Borough', boros, selected=boros, multiple=TRUE),
      selectInput('room', 'Room type', rooms, selected=rooms, multiple=TRUE),
      selectInput('hood', 'Neighbourhood', 'All'),
      sliderInput('price', 'Nightly price (USD)', 1, 999, c(1,999)),
      sliderInput('nights', 'Maximum minimum stay (nights)', 1, max(d$minimum_nights), max(d$minimum_nights)),
      checkboxInput('available', 'At least one available day in snapshot', FALSE),
      textInput('search', 'Search listing title'),
      actionButton('reset', 'Reset filters'), br(), br(),
      downloadButton('download', 'Download filtered listings'),
      helpText('Availability is reported in the historical dataset and does not establish current availability.')
    ),
    mainPanel(width=9,
      uiOutput('metrics'),
      tabsetPanel(
        tabPanel('Map', p('Click a cluster to zoom; click a listing for details.'),
                 leafletOutput('map', height='580px'), textOutput('map_note')),
        tabPanel('Price insights', plotOutput('distribution'), plotOutput('comparison')),
        tabPanel('Listings', DTOutput('table')),
        tabPanel('Price estimator',
          p('Explore the regression from the original project. This model uses the full cleaned snapshot and does not change with explorer filters.'),
          fluidRow(column(4, selectInput('pred_boro','Borough',boros,'Manhattan')),
                   column(4, selectInput('pred_room','Room type',rooms)),
                   column(4, numericInput('pred_reviews','Reviews per month',1,0,max(d$reviews_per_month),0.1))),
          uiOutput('prediction'),
          p('The displayed estimate is exp(predicted log price), an estimate of conditional median price. The interval is a 95% prediction interval transformed from log scale. It describes historical variation, not a current quote.'),
          verbatimTextOutput('model_info')),
        tabPanel('About',
          h3('From analysis to exploration'),
          p('Built from Tobi’s AB_NYC.csv and May 2026 NYC Airbnb analysis.'),
          p(sprintf('The input contains %s listings. The explorer retains %s listings with prices above $0 and below $1,000, following the original analysis.',
                    format(nrow(raw),big.mark=','),format(nrow(d),big.mark=','))),
          p('Missing reviews per month are replaced with zero. Missing review dates remain missing. Prices represent listing prices; fees and taxes are not modeled.'),
          p('Map points require valid NYC-area coordinates. All eligible listings are clustered on the map; charts and downloads use the complete filtered set.'),
          p('Regression: log(price) ~ room_type + neighbourhood_group + reviews_per_month. Coefficients are associations and do not establish causes. No held-out predictive performance is claimed.'),
          p('No Mapbox token is required. Map tiles use OpenStreetMap and require an internet connection.'),
          tags$a(href='https://github.com/adenolatobi/nyc-airbnb-predictive-analytics', 'Original project on GitHub', target='_blank'))
      )
    )
  )
)

server <- function(input, output, session) {
  observeEvent(input$borough, {
    choices <- sort(unique(d$neighbourhood[d$neighbourhood_group %in% input$borough]))
    updateSelectInput(session,'hood',choices=c('All',choices),selected='All')
  }, ignoreNULL=FALSE)
  observeEvent(input$reset, {
    updateSelectInput(session,'borough',selected=boros)
    updateSelectInput(session,'room',selected=rooms)
    updateSelectInput(session,'hood',selected='All')
    updateSliderInput(session,'price',value=c(1,999))
    updateSliderInput(session,'nights',value=max(d$minimum_nights))
    updateCheckboxInput(session,'available',value=FALSE)
    updateTextInput(session,'search',value='')
  })
  filtered <- reactive({
    req(input$price,input$nights)
    keep <- d$neighbourhood_group %in% input$borough & d$room_type %in% input$room &
      d$price >= input$price[1] & d$price <= input$price[2] & d$minimum_nights <= input$nights
    if (!is.null(input$hood) && input$hood != 'All') keep <- keep & d$neighbourhood == input$hood
    if (isTRUE(input$available)) keep <- keep & d$availability_365 > 0
    if (nzchar(input$search)) keep <- keep & !is.na(d$name) & grepl(tolower(input$search),tolower(d$name),fixed=TRUE)
    d[which(keep), ]
  })
  output$metrics <- renderUI({
    x <- filtered()
    metric <- function(label,value) column(4,div(class='metric',label,tags$strong(value)))
    fluidRow(metric('Matching listings',format(nrow(x),big.mark=',')),
             metric('Median nightly price',if(nrow(x)) money(median(x$price)) else '—'),
             metric('Neighbourhoods',length(unique(x$neighbourhood))))
  })
  mapped <- reactive({
    x <- filtered()
    x[which(is.finite(x$latitude) & is.finite(x$longitude) & x$latitude>=40.4 & x$latitude<=41 & x$longitude>=-74.3 & x$longitude<=-73.6), ]
  })
  output$map <- renderLeaflet({
    leaflet(options=leafletOptions(preferCanvas=TRUE)) |> addTiles() |> setView(-73.95,40.73,10)
  })
  observe({
    x <- mapped()
    proxy <- leafletProxy('map',session=session) |> clearMarkers()
    if(nrow(x)) {
      popup <- paste0('<b>',htmltools::htmlEscape(ifelse(is.na(x$name),'Untitled listing',x$name)),
                      '</b><br>',htmltools::htmlEscape(x$neighbourhood),'<br>',
                      htmltools::htmlEscape(as.character(x$room_type)), '<br>',money(x$price),
                      ' / night<br>Minimum stay: ',x$minimum_nights,' nights')
      proxy |> addMarkers(lng=x$longitude,lat=x$latitude,popup=popup,
                          clusterOptions=markerClusterOptions())
    }
  })
  output$map_note <- renderText(sprintf('%s mapped listings; %s excluded for missing or out-of-area coordinates.',
    format(nrow(mapped()),big.mark=','), nrow(filtered())-nrow(mapped())))
  output$distribution <- renderPlot({
    x <- filtered(); validate(need(nrow(x)>0,'No listings match. Widen your filters.'))
    ggplot(x,aes(price)) + geom_histogram(binwidth=25,fill='#087f8c',color='white') +
      labs(title='How nightly prices are distributed',x='Nightly price (USD)',y='Listings')
  })
  output$comparison <- renderPlot({
    x <- filtered(); validate(need(nrow(x)>0,'No listings match. Widen your filters.'))
    ggplot(x,aes(neighbourhood_group,price,fill=room_type)) + geom_boxplot(outlier.shape=NA) +
      scale_fill_brewer(palette='Set2') + labs(title='Price variation by borough and room type',x=NULL,y='Nightly price (USD)',fill='Room type')
  })
  output$table <- renderDT({
    x <- filtered()[,c('id','name','neighbourhood_group','neighbourhood','room_type','price','minimum_nights','number_of_reviews','availability_365')]
    datatable(x,rownames=FALSE,escape=TRUE,options=list(pageLength=10,scrollX=TRUE)) |> formatCurrency('price')
  },server=TRUE)
  output$download <- downloadHandler(filename=function() 'nyc_airbnb_filtered.csv',content=function(file) {
    x <- filtered(); x$log_price <- NULL; write.csv(x,file,row.names=FALSE,na='')
  })
  output$prediction <- renderUI({
    req(input$pred_boro,input$pred_room,input$pred_reviews)
    validate(need(is.finite(input$pred_reviews) && input$pred_reviews>=0 && input$pred_reviews<=max(d$reviews_per_month),'Use reviews per month within the observed range.'))
    new <- data.frame(room_type=factor(input$pred_room,levels=rooms),
                      neighbourhood_group=factor(input$pred_boro,levels=boros),reviews_per_month=input$pred_reviews)
    p <- exp(predict(model,newdata=new,interval='prediction'))
    div(class='metric','Estimated median nightly price',tags$strong(money(p[1,'fit'])),
        paste('95% prediction interval:',money(p[1,'lwr']),'–',money(p[1,'upr'])))
  })
  output$model_info <- renderPrint({
    cat('Observations:',nobs(model),'\nAdjusted R-squared:',round(summary(model)$adj.r.squared,3),
        '\nFit describes this historical dataset; no test-set evaluation is included.\n')
  })
}
shinyApp(ui,server)
