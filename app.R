library(shiny)
library(shinyjs)
library(shinyWidgets)
library(shinyFeedback)
library(ari)
library(dplyr)
library(readr)
library(pdftools)
library(blastula)
library(googlesheets4)
library(promises)
library(future)
library(ipc)
plan(multisession, workers = 25)
options("future.rng.onMisuse" = "ignore")

# Voice Data
voices_coqui <- read_csv("data/voices-coqui.csv", show_col_types = FALSE) %>% 
  # Remove after testing
  filter(language == "en", 
         dataset %in% c("ljspeech", "jenny"),
         model_name %in% c("tacotron2-DDC_ph", "jenny"))
voices_amazon <- read_csv("data/voices-amazon.csv", show_col_types = FALSE)
voices_google <- read_csv("data/voices-google.csv", show_col_types = FALSE) %>% 
  filter(!is.na(language))
voices_ms <- read_csv("data/voices-ms.csv", show_col_types = FALSE)
names(voices_ms) <- tolower(names(voices_ms))

# images for pickerInput stored in www/i/ from the root app directory
imgs <- c("i/img/coqui.png", "i/img/aws.jpeg", "i/img/google.png", "i/img/ms.jpeg")
img_name <- c("Coqui TTS", "Amazon Polly", 
              "Google Cloud Text-to-Speech", "Microsoft Cognitive Services Text-to-Speech")

select_choice_img <- function(img, text) {
  shiny::HTML(paste(
    tags$img(src=img, width=25, height=22),
    text
  ))
}

# Check if email is valid 
is_valid_email <- function(x) {
  grepl("([_+a-z0-9-]+(\\.[_+a-z0-9-]+)*@[a-z0-9-]+(\\.[a-z0-9-]+)*(\\.[a-z]{2,14}))", x)
}

# Start of Shiny app
ui <- fluidPage(
  useShinyjs(),
  useShinyFeedback(),
  # css
  tags$head(
    tags$link(rel = "stylesheet", type = "text/css", href = "i/hutch_theme.css")
  ),
  # favicon
  tags$head(tags$link(rel="shortcut icon", href="i/img/favicon.ico")),
  # css to center the progress bar
  # https://stackoverflow.com/a/52585505/14804653
  tags$head(
    tags$style(
      HTML(".shiny-notification {
           height: 100px;
           width: 800px;
           position:fixed;
           top: calc(50% - 50px);
           left: calc(50% - 400px);
           font-size: 250%;
           font-family: Times;
           color: #1c3b61;
           text-align: center;
           }
           "
      )
    )
  ),
  titlePanel(tagList(
    "Loqui",
    span(
      actionButton("demo", 
                   label = "Demo",
                   icon = icon("youtube"),
                   onclick ="window.open(`https://youtu.be/wWo1ul_Vyfo`, '_blank')"),
      actionButton("help", 
                   label = "Help",
                   icon = icon("circle-exclamation"),
                   width = "77px",
                   onclick ="window.open(`https://github.com/FredHutch/loqui#getting-help`, '_blank')"),
      actionButton("github",
                   label = "Code",
                   icon = icon("github"),
                   width = "77px",
                   onclick ="window.open(`https://github.com/FredHutch/loqui`, '_blank')"),
      style = "position:absolute;right:2em;"
    )
  ),
  windowTitle = "Loqui"),
  hr(),
  sidebarLayout(
    sidebarPanel(
      textInput("email", "Email Address (where video should be sent)"),
      div(
        prettySwitch("auto_email", "Once video finishes rendering, send email automatically",
                     status = "success", fill = TRUE),
        style = "color: #1c3b61;"
      ),
      textInput("gs_url", 
                label = "Google Slides URL (Enable Link Sharing)",
                value = "",
                placeholder = "Paste a URL"),
      shinyWidgets::pickerInput("service",
                                label = "Text-to-Speech Service", 
                                choices = c("Coqui TTS" = "coqui"),
                                choicesOpt = list(content = purrr::map2(imgs, img_name, select_choice_img)[[1]])),
      # "Amazon Polly" = "amazon",
      # "Google Cloud Text-to-Speech" = "google",
      # "Microsoft Cognitive Services Text-to-Speech" = "ms"),
      # choicesOpt = list(content = purrr::map2(imgs, img_name, select_choice_img))),
      uiOutput("voice_options"),
      actionButton("generate", "Generate", icon = icon("person-running")),
      br(),
      br(),
      h5("Built with",
         img(src = "https://www.rstudio.com/wp-content/uploads/2014/04/shiny.png", height = "30px"),
         "by",
         img(src = "i/img/posit.jpeg", height = "30px")
      ),
      tags$img(src = "i/img/logo.png", width = "90%")
    ),
    mainPanel(
      tabsetPanel(id = "inTabset",
                  tabPanel(
                    title = div("About",
                                style = "font-family: Arial; color: #1c3b61; font-weight: bold"),
                    value = "about",
                    h3("Introducing Loqui: A Shiny app for Creating Automated Courses with ari"),
                    div( 
                      p("Loqui is an open source web application that enables the creation of automated courses using ari,
                        an R package for generating videos from text and images. Loqui takes as input a Google Slides URL,
                        extracts the speaker notes from the slides, and converts them into an audio file. 
                        Then, it converts the Google Slides to images and ultimately,
                        generates an mp4 video file where each image is presented with its corresponding audio."),
                      
                      p("The functionality of Loqui relies on two R packages, namely ari and text2speech, which run in the background.
                        Although  it is certainly possible to go directly to these packages and run their functions for course generation,
                        we realize that not everyone feels comfortable programming in R. This web application offers an intuitive and user-friendly
                        interface allowing individuals to effortlessly create automated courses without the need for programming skills."),
                      h4("Prerequisites"),
                      tags$ul(
                        tags$li("Start from a Google Slides that you wish to generate automated courses from. 
                           Make sure all slides contain speaker notes. A slide without a speaker note will generate a scratchy radio sound."),
                        tags$li("Turn link sharing on. Make sure \"General access\" is set to \"Anyone with the link 
                          (Anyone on the internet with the link can edit)\" 
                           and Role can be set to either Editor, Viewer, or Commenter."),
                        tags$li("For more information, read Section 2 \"How to share a Google Slides presentation via a link\" of this",
                                a(href = "https://www.brightcarbon.com/blog/how-to-share-google-slides-presentation", "blogpost."))
                      ),
                      
                      h4("Instructions"),
                      tags$ul(
                        tags$li("In the left sidebar, please provide a valid email address as this app requires it to function properly."),
                        tags$li("Copy and Paste the Google Slides URL into the text box labeled \"Google Slides URL\"."),
                        tags$li("Choose the Text-to-Speech Service. Please note that as of mid-2023, only the Coqui TTS engine is available 
                          as a free option.
                        However, paid services like Amazon Polly, Google Cloud Text-to-Speech, and Microsoft Azure Text-to-Speech will be introduced in the future."),
                        tags$li("Select the desired voice options for the text-to-speech engine. We have already pre-selected the voice options that sound the most human-like.
                        However, if you prefer alternative voice options, kindly inform us, and we will accommodate your request. 
                        If there is sufficient interest, we may consider expanding the list of voice options to provide more choices."),
                        tags$li("Click the \"Generate\" button to initiate the course generation process.")
                      ),
                      em("Privacy Policy: The data we collect is limited to the date and time of usage, duration of the generated video, and the provided email address."),
                      h5("This initiative is funded by the following grant: National Cancer Institute (NCI) UE5 CA254170"),
                      style = "font-family: Arial; color: #1c3b61"),
                    br(),
                  ),
                  tabPanel(
                    title = div("Rendered Video", 
                                style = "font-family: Arial; color: #1c3b61; font-weight: bold"),
                    value = "rendered_video",
                    br(),
                    uiOutput("video_ui"),
                    br(),
                    fluidRow(column(11, htmlOutput("video_info"))),
                    fluidRow(uiOutput("video_btn")),
                    fluidRow(uiOutput("video_btn_test"))
                  )
      )
    )
  )
)

server <- function(input, output, session) {
  # Disable buttons when email is not provided
  observe({
    toggleState("generate",
                !is.null(input$email) && input$email != "" && is_valid_email(input$email))
    toggleState("download_btn",
                !is.null(input$email) && input$email != "" && is_valid_email(input$email))
    toggleState("send_email",
                !is.null(input$email) && input$email != "" && is_valid_email(input$email))
  })
  # Display feedback message when email address is not valid
  observeEvent(input$email, {
    if (input$email != "" & !is_valid_email(input$email)) {
      showFeedbackWarning(
        inputId = "email",
        text = "Invalid email. Please try again."
      )  
    } else {
      hideFeedback("email")
    }
  })
  
  # Switch tabs when "Get Started" is clicked
  observeEvent(input$generate, {
    updateTabsetPanel(session, "inTabset", selected = "rendered_video")
  })
  
  video_name <- eventReactive(input$generate, {
    # create unique name for video file
    current_time <- Sys.time()
    current_time <- format(current_time, "%Y-%m-%d-%H-%M-%S")
    unique_file_name <- paste0("www/ari-video-", current_time, ".mp4")
    
    unique_file_name
  })
  
  # Voice Options
  output$voice_options <- renderUI({
    if (input$service == "coqui") {
      tagList(
        selectInput("coqui_lang", "Select Language", 
                    choices = unique(voices_coqui$language)),
        selectInput("coqui_dataset", "Select Dataset", choices = NULL),
        selectInput("coqui_model_name", "Select Model Name", choices = NULL),
        selectInput("coqui_vocoder_name", "Select Vocoder Name",
                    choices = NULL)
        # Remove after testing
        # c("libri-tts/wavegrad",
        #   "libri-tts/fullband-melgan",
        #   "ek1/wavegrad",
        #   "ljspeech/multiband-melgan",
        #   "ljspeech/hifigan_v2",
        #   "ljspeech/univnet",
        #   "blizzard2013/hifigan_v2",
        #   "vctk/hifigan_v2",
        #   "sam/hifigan_v2")
      )
      # Remove when paid services are good2go
    } else if (input$service == "amazon") {
      # tagList(
      #   selectInput("amazon_lang", "Select Language", 
      #               choices = unique(voices_amazon$language)),
      #   selectInput("amazon_gender", "Select Gender", choices = NULL),
      #   selectInput("amazon_voice", "Select Voice", choices = NULL)
      # )
    } else if (input$service == "google") {
      # Remove when paid services are good2go
      # tagList(
      #   selectInput("google_lang", "Select Language", 
      #               choices = unique(voices_google$language)),
      #   selectInput("google_gender", "Select Gender", choices = NULL),
      #   selectInput("google_voice", "Select Voice", choices = NULL)
      # )
    } else {
      # Remove when paid services are good2go
      # tagList(
      #   selectInput("ms_locale", "Select Language",
      #               choices = unique(voices_ms$locale)),
      #   selectInput("ms_gender", "Select Gender", choices = NULL),
      #   selectInput("ms_voice", "Select Voice", choices = NULL)
      # )
    }
  })
  
  
  # Coqui
  voices_coqui_reactive <- reactive({
    filter(voices_coqui, language == input$coqui_lang)
  })
  observeEvent(input$coqui_lang, {
    freezeReactiveValue(input, "coqui_dataset")
    choices <- unique(voices_coqui_reactive()$dataset)
    updateSelectInput(inputId = "coqui_dataset", choices = choices)
  })
  voices_coqui_dataset_reactive <- reactive({
    req(input$coqui_dataset)
    filter(voices_coqui_reactive(), dataset == input$coqui_dataset)
  })
  observeEvent(input$coqui_dataset, {
    freezeReactiveValue(input, "coqui_model_name")
    choices <- unique(voices_coqui_dataset_reactive()$model_name)
    updateSelectInput(inputId = "coqui_model_name", choices = choices)
  })
  voices_coqui_model_reactive <- reactive({
    req(input$coqui_model_name)
    filter(voices_coqui_dataset_reactive(), dataset == input$coqui_model_name)
  })
  observeEvent(input$coqui_model_name, {
    freezeReactiveValue(input, "coqui_vocoder_name")
    choices <- ifelse(input$coqui_model_name == "jenny", "jenny", "ljspeech/univnet")
    updateSelectInput(inputId = "coqui_vocoder_name", choices = choices)
  })
  
  # Remove after testing
  # # Amazon
  # voices_amazon_reactive <- reactive({
  #   filter(voices_amazon, language == input$amazon_lang)
  # })
  # observeEvent(input$amazon_lang, {
  #   freezeReactiveValue(input, "amazon_gender")
  #   choices <- unique(voices_amazon_reactive()$gender)
  #   updateSelectInput(inputId = "amazon_gender", choices = choices) 
  # })
  # voices_amazon_gender_reactive <- reactive({
  #   req(input$amazon_gender)
  #   filter(voices_amazon_reactive(), gender == input$amazon_gender)
  # })
  # observeEvent(input$amazon_gender, {
  #   freezeReactiveValue(input, "amazon_voice")
  #   choices <- unique(voices_amazon_gender_reactive()$voice)
  #   updateSelectInput(inputId = "amazon_voice", choices = choices) 
  # })
  # 
  # # Google
  # voices_google_reactive <- reactive({
  #   filter(voices_google, language == input$google_lang)
  # })
  # observeEvent(input$google_lang, {
  #   freezeReactiveValue(input, "google_gender")
  #   choices <- unique(voices_google_reactive()$gender)
  #   updateSelectInput(inputId = "google_gender", choices = choices) 
  # })
  # voices_google_gender_reactive <- reactive({
  #   req(input$google_gender)
  #   filter(voices_google_reactive(), gender == input$google_gender)
  # })
  # observeEvent(input$google_gender, {
  #   freezeReactiveValue(input, "google_voice")
  #   choices <- unique(voices_google_gender_reactive()$voice)
  #   updateSelectInput(inputId = "google_voice", choices = choices) 
  # })
  # 
  # # Microsoft
  # voices_ms_reactive <- reactive({
  #   filter(voices_ms, locale == input$ms_locale)
  # })
  # observeEvent(input$ms_locale, {
  #   freezeReactiveValue(input, "ms_gender")
  #   choices <- unique(voices_ms_reactive()$gender)
  #   updateSelectInput(inputId = "ms_gender", choices = choices) 
  # })
  # voices_ms_gender_reactive <- reactive({
  #   req(input$ms_gender)
  #   filter(voices_ms_reactive(), gender == input$ms_gender)
  # })
  # observeEvent(input$ms_gender, {
  #   freezeReactiveValue(input, "ms_voice")
  #   choices <- unique(voices_ms_gender_reactive()$name)
  #   updateSelectInput(inputId = "ms_voice", choices = choices) 
  # })
  # 
  
  # Main function
  observeEvent(input$generate, {
    # Create a progress bar
    progress <- AsyncProgress$new(message = "Processing...")
    # Inputs used inside future_promise()
    service <- input$service
    coqui_model_name <- input$coqui_model_name
    coqui_vocoder_name <- input$coqui_vocoder_name
    gs_url <- input$gs_url
    user_email <- input$email
    auto_email <- input$auto_email
    video_name <- video_name()
    app_url <- "https://loqui.fredhutch.org"
    
    res <- reactiveVal()
    future_promise({
      progress$inc(amount = 0, message = "Processing takes a few minutes...")
      pptx_path <- download_gs_file(gs_url, out_type = "pptx")
      progress$inc(amount = 1/5, message = "Processing...")
      
      # extract speaker notes
      pptx_notes_vector <- pptx_notes(pptx_path)
      progress$inc(amount = 1/5, message = "Processing...")
      
      # download as pdf
      progress$inc(amount = 0, message = "Processing takes a few minutes...")
      pdf_path <- download_gs_file(gs_url, out_type = "pdf")
      progress$inc(amount = 1/5, message = "Processing...")
      
      # convert to png
      progress$inc(amount = 0, message = "Processing takes a few minutes...")
      image_path <- pdf_to_pngs(pdf_path)
      progress$inc(amount = 1/5, message = "Processing...")
      
      progress$inc(amount = 0, message = "This step requires a few minutes...")
      Sys.sleep(2)
      progress$inc(amount = 0, message = "Processing...")
      switch(service,
             coqui = ari_spin(images = image_path, 
                              paragraphs = pptx_notes_vector,
                              service = "coqui",
                              model_name = coqui_model_name,
                              vocoder_name = coqui_vocoder_name,
                              output = video_name),
             amazon = ari_spin(images = image_path, 
                               paragraphs = pptx_notes_vector,
                               service = "amazon",
                               voice = input$amazon_voice,
                               output = video_name),
             google = ari_spin(images = image_path, 
                               paragraphs = pptx_notes_vector,
                               service = "google",
                               voice = input$google_voice,
                               output = video_name),
             ms = ari_spin(images = image_path, 
                           paragraphs = pptx_notes_vector,
                           service = "microsoft",
                           voice = input$ms_voice,
                           output = video_name)
      )
      progress$inc(amount = 1/5, message = "Processing...Done!", detail = "100%")
      Sys.sleep(2)
      progress$close()
      
      # Email
      if (auto_email) {
        # Video Link
        video_name_processed <- gsub("www/", "", video_name)
        video_link <- paste0(app_url, "/", "i", "/", video_name_processed)
        # Date/Time
        date_time <- add_readable_time()
        # Compose Email
        email <- compose_email(
          body = md(glue::glue(
            "Dear Loqui User,
            
To access the video, simply click on the following link: [{video_link}]({video_link}). To download the video, click the three 
vertical dots and select 'Download'.
            
We also invite you to visit our website at [https://hutchdatascience.org](https://hutchdatascience.org)
to explore a wealth of valuable resources and stay updated on the latest news from
the Fred Hutch Data Science Lab (DaSL). 

Feel free to reach out to us with any questions at howardbaek@fredhutch.org or by filing a [GitHub issue](https://github.com/FredHutch/loqui/issues).
We will respond to your inquiries as soon as possible.
            
Howard Baek
")),
          footer = md(glue::glue("Email automatically sent on {date_time}."))
        )
        # Send email
        email %>% 
          smtp_send(
            from = "loqui-noreply@fredhutch.org",
            to = user_email,
            subject = "Video Generated by Loqui from Fred Hutch Data Science Lab (DaSL)",
            credentials = creds_anonymous(host = "mx.fhcrc.org", port = 25)
          )
      }
      
      # Google Sheets
      ffmpeg_cmd <- paste0("-i", " ", video_name, " ", "2>&1 | grep \"Duration\"")
      duration_raw <- system2("ffmpeg", ffmpeg_cmd, stdout = TRUE)
      duration_raw <- regmatches(duration_raw, regexpr("Duration: (\\d{2}:\\d{2}:\\d{2}\\.\\d{2})", duration_raw))
      video_duration <- sub("Duration: ([0-9:.]+)", "\\1", duration_raw)
      date_time <- add_readable_time()
      # Authorize
      gs4_auth(cache=".secrets", email="howardbaek.fh@gmail.com")
      # Append
      gs_url <- "https://docs.google.com/spreadsheets/d/1G_HTU-bv2k5txExP8EH3ScUfGqtW1P3syThD84Z-g9k/edit?usp=sharing"
      sheet_append(gs_url,
                   data.frame(date_time = date_time,
                              video_duration = video_duration, 
                              email = user_email))
      
      # Final output
      # Replace "www" with "i"
      gsub("www", "i", video_name)
    }) %...>% res
    
    # Show video when "Generate" is clicked
    output$video_ui <- renderUI({
      res <- res()
      tags$video(src = res, 
                 type = "video/mp4",
                 height ="480px", 
                 width="854px",
                 autoplay = TRUE,
                 controls = TRUE)
    })
    # Extract video info
    pdf_path <- download_gs_file(input$gs_url, "pdf")
    video_info_reactive <- pdf_info(pdf = pdf_path)
    # Show video title
    output$video_info <- renderUI({
      span(textOutput("video_title"), 
           style = "font-weight: bold; 
                    font-family: Arial; 
                    font-size: 25px; 
                    color: #1c3b61")
      
      output$video_title <- renderText({
        video_info_reactive$keys$Title
      })
    })
    # Show video buttons (download/send email)
    output$video_btn <- renderUI({
      column(12,
             downloadButton("download_btn"),
             actionButton("send_email", "Email", icon = icon("inbox")),
             align = "left"
      )
    })
  })
  # Download rendered video
  # Source: https://stackoverflow.com/questions/33416557/r-shiny-download-existing-file
  output$download_btn <- downloadHandler(
    filename = "loqui_video.mp4",
    content = function(file) {
      file.copy(video_name(), file)
    },
    contentType = "video/mp4"
  )
  
  # Send email
  observeEvent(input$send_email, {
    # Dialog Box
    showModal(modalDialog(
      title = span(h4("Success message:"), style = "color: #1c3b61;font-family:Times;font-weight: bold;"),
      span(paste0("Email with the video file has been sent to ", input$email, "."), style = "color: #1c3b61;font-family:Arial")
    ))
    
    # Video Link
    video_name_processed <- gsub("www/", "", video_name())
    # Video Link
    app_url <- "https://loqui.fredhutch.org"
    video_link <- paste0(app_url, "/", "i", "/", video_name_processed)
    # Date/Time
    date_time <- add_readable_time()
    # Compose Email
    email <- compose_email(
      body = md(glue::glue(
        "Dear Loqui User,
            
To access the video, simply click on the following link: [{video_link}]({video_link}). To download the video, click the three 
vertical dots and select 'Download'.
            
We also invite you to visit our website at [https://hutchdatascience.org](https://hutchdatascience.org)
to explore a wealth of valuable resources and stay updated on the latest news from
the Fred Hutch Data Science Lab (DaSL). 

Feel free to reach out to us with any questions at howardbaek@fredhutch.org or by filing a [GitHub issue](https://github.com/FredHutch/loqui/issues).
We will respond to your inquiries as soon as possible.
            
Howard Baek
")),
      footer = md(glue::glue("Email sent on {date_time}."))
    )
    # Send email
    email %>% 
      smtp_send(
        from = "loqui-noreply@fredhutch.org",
        to = input$email,
        subject = "Video Generated by Loqui from Fred Hutch Data Science Lab (DaSL)",
        credentials = creds_anonymous(host = "mx.fhcrc.org", port = 25)
      )
  })
}
# Code for Deployment to Hutch servers
addResourcePath("/i", file.path(getwd(), "www"))
options <- list()
if (!interactive()) {
  options$port = 3838
  options$launch.browser = FALSE
  options$host = "0.0.0.0"
  
}
shinyApp(ui, server, options=options)