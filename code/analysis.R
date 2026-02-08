#installing and loading packages
install.packages(c("tidyverse", "lubridate", "tidyr", "ggplot2", "viridis","stringr"))

library(tidyverse)
library(lubridate)
library(tidyr)
library(ggplot2)
library(viridis)
library(stringr)
library(patchwork)

#loading datasets
pm_raw <- read_csv("sheffieldpm2.5.csv", show_col_types = FALSE)
meteo_raw <- read_csv("openmeteo_tempandwind.csv", show_col_types = FALSE)

names(pm_raw)
names(meteo_raw)

#creating a date column (filter and summarise by day)
pm_raw <- pm_raw %>%
  mutate(date = as.Date(DatetimeUtc))

meteo_raw <- meteo_raw %>%
  mutate(date = as.Date(datetime_utc))

range(pm_raw$date)
range(meteo_raw$date)

#keeping only the study period (1 Jun 2023 to 31 May 2024)
start_date <- as.Date("2023-06-01")
end_date   <- as.Date("2024-05-31")

pm_period <- pm_raw %>%
  filter(date >= start_date, date <= end_date)

meteo_period <- meteo_raw %>%
  filter(date >= start_date, date <= end_date)

range(pm_period$date)
range(meteo_period$date)

#convert PM2.5 into daily values (daily mean + daily maximum)
pm_daily <- pm_period %>%
  group_by(date) %>%
  summarise(
    pm25_mean = mean(Value, na.rm = TRUE),
    pm25_max1h = max(Value, na.rm = TRUE),
    .groups = "drop"
  )

nrow(pm_daily)

#convert hourly weather into daily values and join with PM2.5
meteo_daily <- meteo_period %>%
  group_by(date) %>%
  summarise(
    temp_c = mean(temperature_c, na.rm = TRUE),
    wind_kmh = mean(wind_speed_kmh, na.rm = TRUE),
    wind_dir_deg = mean(wind_direction_deg, na.rm = TRUE),
    .groups = "drop"
  )

df_daily <- tibble(date = seq(as.Date("2023-06-01"), as.Date("2024-05-31"), by = "day")) %>%
  left_join(pm_daily, by = "date") %>%
  left_join(meteo_daily, by = "date")

nrow(df_daily)
sum(is.na(df_daily$pm25_mean))

#visualisation 1 (calendar heatmap)
month_order <- c("Jun","Jul","Aug","Sep","Oct","Nov","Dec","Jan","Feb","Mar","Apr","May")

cal_df <- df_daily %>%
  filter(date >= as.Date("2023-06-01"), date <= as.Date("2024-05-31")) %>%
  mutate(
    month = factor(format(date, "%b"), levels = month_order),
    day   = as.integer(format(date, "%d"))
  )

p1 <- ggplot(cal_df, aes(x = day, y = 1, fill = pm25_mean)) +
  geom_tile(color = "white", linewidth = 0.35) +
  facet_wrap(~ month, ncol = 3) +
  scale_fill_gradientn(
    colours  = c("#DEEBF7", "#9ECAE1", "#4292C6", "#2171B5", "#084594"),
    na.value = "grey85",
    limits   = c(0, 40),
    breaks   = seq(0, 40, 10),
    oob      = scales::squish
  ) +
  scale_y_continuous(expand = c(0, 0)) +
  scale_x_continuous(breaks = c(1, 10, 20, 31)) +
  labs(
    title    = "Daily mean PM2.5 by day of month — Sheffield Devonshire Green",
    subtitle = "Study period: 1 Jun 2023 – 31 May 2024 (grey tiles = missing PM2.5 day)",
    x        = "Day of month",
    y        = NULL,
    fill     = "PM2.5 (µg/m³)"
  ) +
  theme_minimal(base_size = 12) +
  theme(
    axis.text.y  = element_blank(),
    axis.ticks.y = element_blank(),
    panel.grid   = element_blank(),
    strip.background = element_rect(fill = "grey92", colour = NA),
    strip.text = element_text(face = "bold"),
    legend.key.height = unit(12, "mm")
  )

p1

#visualisation 2
df_temp <- df_daily %>%
  filter(date >= as.Date("2023-06-01"), date <= as.Date("2024-05-31")) %>%
  filter(!is.na(temp_c), !is.na(pm25_mean))

n_days <- nrow(df_temp)

p2 <- ggplot(df_temp, aes(x = temp_c, y = pm25_mean)) +
  geom_point(alpha = 0.25, size = 1.1) +
  geom_smooth(method = "loess", se = TRUE, linewidth = 1, alpha = 0.15) +
  coord_cartesian(ylim = c(0, 30)) +
  labs(
    title = "Temperature and daily mean PM2.5",
    subtitle = paste0(
      "1 Jun 2023 – 31 May 2024 (n = ", n_days,
      " days; LOESS smooth with 95% CI; days with missing PM2.5 or temperature excluded)"
    ),
    x = "Daily mean temperature (°C)",
    y = "Daily mean PM2.5 (µg/m³)"
  ) +
  theme_minimal(base_size = 12)

p2

#visualisation 3
df_wdir8 <- df_daily %>%
  dplyr::filter(!is.na(wind_dir_deg), !is.na(pm25_mean)) %>%
  dplyr::mutate(
    dir_bin = floor(((wind_dir_deg %% 360) + 22.5) / 45) * 45 %% 360,
    dir_lab = factor(
      dir_bin,
      levels = seq(0, 315, 45),
      labels = c("N","NE","E","SE","S","SW","W","NW")
    )
  ) %>%
  dplyr::group_by(dir_lab) %>%
  dplyr::summarise(
    pm25_mean = mean(pm25_mean, na.rm = TRUE),
    n_days    = dplyr::n(),
    .groups   = "drop"
  )

days_caption <- paste0(
  "Days per sector: ",
  paste0(df_wdir8$dir_lab, " (n=", df_wdir8$n_days, ")", collapse = "  "),
  ". N sector has n=1."
)

p3 <- ggplot(df_wdir8, aes(x = dir_lab, y = pm25_mean, fill = pm25_mean)) +
  geom_col(color = "white", linewidth = 0.6) +
  coord_polar(start = -pi/8) +
  scale_fill_gradientn(
    colours = c("#DEEBF7", "#9ECAE1", "#4292C6", "#2171B5", "#084594")
  ) +
  scale_y_continuous(breaks = seq(0, 15, by = 5)) +
  labs(
    title    = "Daily mean PM2.5 by wind direction",
    subtitle = "Wind direction binned to 45° sectors (1 Jun 2023 – 31 May 2024)",
    x        = NULL,
    y        = "Mean daily PM2.5 (µg/m³)",
    fill     = "PM2.5 (µg/m³)",
    caption  = days_caption
  ) +
  theme_minimal() +
  theme(
    axis.text.y        = element_blank(),
    axis.ticks.y       = element_blank(),
    panel.grid.minor   = element_blank(),
    axis.title.y       = element_text(size = 12, margin = margin(r = 10)),
    plot.caption       = element_text(hjust = 0, size = 10, margin = margin(t = 10))
  )

p3

#visualisation 4
df_band <- df_daily %>%
  filter(!is.na(wind_kmh), !is.na(pm25_mean)) %>%
  filter(wind_kmh >= 0, wind_kmh <= 40) %>%
  mutate(
    wind_band = cut(wind_kmh, breaks = seq(0, 40, by = 5), include.lowest = TRUE)
  )

levels(df_band$wind_band) <- c("0–5","5–10","10–15","15–20","20–25","25–30","30–35","35–40")

df_band_sum <- df_band %>%
  group_by(wind_band) %>%
  summarise(
    wind_mid = mean(wind_kmh, na.rm = TRUE),
    pm_mean  = mean(pm25_mean, na.rm = TRUE),
    n_days   = n(),
    .groups  = "drop"
  )

cap_txt <- paste0(
  "Band counts (days): ",
  paste0(df_band_sum$wind_band, " (n=", df_band_sum$n_days, ")", collapse = ", ")
) %>%
  str_wrap(width = 95)

p4 <- ggplot(df_band_sum, aes(x = wind_mid, y = pm_mean)) +
  geom_point(
    aes(size = n_days, colour = pm_mean),
    alpha = 0.9
  ) +
  scale_colour_gradientn(
    colours = c("#DEEBF7", "#9ECAE1", "#4292C6", "#2171B5", "#084594"),
    name = "PM2.5 (µg/m³)"
  ) +
  scale_size_continuous(range = c(2.5, 14), guide = "none") +  
  scale_x_continuous(breaks = seq(5, 35, by = 5)) +            
  scale_y_continuous(breaks = seq(4, 16, by = 2)) +            
  labs(
    title = "Wind speed and daily mean PM2.5",
    subtitle = "Bubbles summarise 5 km/h wind-speed bands (size = number of days)",
    x = "Daily mean wind speed (km/h)",
    y = "Mean daily PM2.5 (µg/m³)",
    caption = cap_txt
  ) +
  theme_minimal() +
  theme(
    panel.grid.minor = element_blank(),     
    plot.caption.position = "plot",
    plot.caption = element_text(hjust = 0.5, margin = margin(t = 10)),
    plot.margin = margin(t = 10, r = 10, b = 40, l = 10)
  )

p4

#saving the visualisations
dir.create("figures", showWarnings = FALSE)

ggsave("figures/fig1_calendar.png", p1, width = 10, height = 6, dpi = 300)
ggsave("figures/fig2_temp.png",     p2, width = 10, height = 6, dpi = 300)
ggsave("figures/fig3_winddir.png",  p3, width = 10, height = 6, dpi = 300)
ggsave("figures/fig4_windspeed.png",p4, width = 10, height = 6, dpi = 300)

combined <- (p1 | p2) / (p3 | p4)

ggsave("figures/composite.png", combined, width = 14, height = 10, dpi = 300)
ggsave("figures/composite.pdf", combined, width = 14, height = 10)



