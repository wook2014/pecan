##' Linear Regression Ensemble Simulation
##' Met downscaling function that predicts ensembles of downscaled meteorology 
# ----------------------------------- 
# Description
# -----------------------------------
##' @title lm_ensemble_sims
##' @family tdm - Temporally Downscale Meteorology
##' @author Christy Rollinson, James Simkins
##' @description This function does the heavy lifting in the final
##'              function of the tdm workflow titled predict_subdaily_met(). It uses a linear
##'              regression approach by generating the hourly values from the coarse data of
##'              the file the user selects to downscale based on the hourly models and betas
##'              generated by gen.subdaily.models().  
# ----------------------------------- 
# Parameters
# -----------------------------------
##' @param dat.mod - dataframe to be predicted at the time step of the training data
##' @param n.ens - number of hourly ensemble members to generate
##' @param path.model - path to where the training model & betas is stored
##' @param lags.init - a data frame of initialization parameters to match the data in dat.mod
##' @param dat.train - the training data used to fit the model; needed for night/day in 
##'                    surface_downwelling_shortwave_flux_in_air
##' @export
# -----------------------------------
#----------------------------------------------------------------------
# Begin Function
#----------------------------------------------------------------------

lm_ensemble_sims <- function(dat.mod, n.ens, path.model, lags.list = NULL, 
                                      lags.init = NULL, dat.train) {
  
  # Set progress bar
  pb.index <- 1
  pb <- txtProgressBar(min = 1, max = 8, style = 3)
  setTxtProgressBar(pb, pb.index)
  
  # Figure out if we need to extract the approrpiate
  if (is.null(lags.list) & is.null(lags.init)) {
    logger.error("lags.init & lags.list are NULL, this is a required argument")
  }
  if (is.null(lags.init)) {
    lags.init <- lags.list[[unique(dat.mod$ens.day)]]
  }
  
  
  # Set up the ensemble members in a list so the uncertainty can be
  # propogated
  dat.sim <- list()
  
  # Declare the variables of interest that will be called in the
  # overarching loop
  vars.list <- list("surface_downwelling_shortwave_flux_in_air", "air_temperature", 
                    "precipitation_flux", "surface_downwelling_longwave_flux_in_air", 
                    "air_pressure", "specific_humidity", "wind_speed")
  
  # Data info that will be used to help organize dataframe for
  # downscaling
  dat.info <- c("time.day", "year", "doy", "hour", "air_temperature_max.day", 
                "air_temperature_min.day", "precipitation_flux.day", "surface_downwelling_shortwave_flux_in_air.day", 
                "surface_downwelling_longwave_flux_in_air.day", "air_pressure.day", 
                "specific_humidity.day", "wind_speed.day", "next.air_temperature_max", 
                "next.air_temperature_min", "next.precipitation_flux", "next.surface_downwelling_shortwave_flux_in_air", 
                "next.surface_downwelling_longwave_flux_in_air", "next.air_pressure", 
                "next.specific_humidity", "next.wind_speed")
  # ------ Beginning of Downscaling For Loop
  
  for (v in vars.list) {
    # create column propagation list and betas progagation list
    cols.list <- list()
    rows.beta <- list()
    
    for (c in seq_len(nrow(dat.mod))) {
      cols.tem <- sample(1:n.ens, n.ens, replace = TRUE)
      cols.list[(c * n.ens - n.ens + 1):(c * n.ens)] <- cols.tem
    }
    cols.list <- as.numeric(cols.list)
    
    # Read in the first linear regression model
    first_model <- ncdf4::nc_open(paste0(path.model, "/", v, "/betas_", 
                                         v, "_1.nc"))
    first_beta <- assign(paste0("betas.", v, "_1"), first_model)
    n.beta <- nrow(ncdf4::ncvar_get(first_beta, "1"))
    ncdf4::nc_close(first_model)
    
    # Create beta list so each ensemble for each variable pulls the same
    # betas
    for (c in seq_len(nrow(dat.mod))) {
      betas.tem <- sample(1:n.beta, n.ens, replace = TRUE)
      rows.beta[(c * n.ens - n.ens + 1):(c * n.ens)] <- betas.tem
    }
    rows.beta <- as.numeric(rows.beta)
    
    # fill our dat.sim list
    dat.sim[[v]] <- data.frame(array(dim = c(nrow(dat.mod), n.ens)))
    
    for (i in min(dat.mod$time.day):max(dat.mod$time.day)) {
      day.now <- unique(dat.mod[dat.mod$time.day == i, "doy"])
      rows.now <- which(dat.mod$time.day == i)
      
      # shortwave is different because we only want to model daylight
      if (v == "surface_downwelling_shortwave_flux_in_air") {
        hrs.day <- unique(dat.train[dat.train$doy == day.now & 
                                      dat.train$surface_downwelling_shortwave_flux_in_air > 
                                      quantile(dat.train[dat.train$surface_downwelling_shortwave_flux_in_air > 
                                                           0, "surface_downwelling_shortwave_flux_in_air"], 
                                               0.05), "hour"])
        
        rows.now <- which(dat.mod$time.day == i)
        rows.mod <- which(dat.mod$time.day == i & dat.mod$hour %in% 
                            hrs.day)
        dat.temp <- dat.mod[rows.mod, dat.info]
      } else if (v == "air_temperature") {
        rows.now <- which(dat.mod$time.day == i)
        dat.temp <- dat.mod[rows.now, dat.info]
        # Set up the lags
        if (i == min(dat.mod$time.day)) {
          sim.lag <- stack(lags.init$air_temperature)
          names(sim.lag) <- c("lag.air_temperature", "ens")
          
          sim.lag$lag.air_temperature_min <- stack(lags.init$air_temperature_min)[, 
                                                                                  1]
          sim.lag$lag.air_temperature_max <- stack(lags.init$air_temperature_max)[, 
                                                                                  1]
        } else {
          sim.lag <- stack(data.frame(array(dat.sim[["air_temperature"]][dat.mod$time.day == 
                                                                           (i - 1) & dat.mod$hour == max(unique(dat.mod$hour)), 
                                                                         ], dim = c(1, ncol(dat.sim$air_temperature)))))
          names(sim.lag) <- c("lag.air_temperature", "ens")
          sim.lag$lag.air_temperature_min <- stack(apply(dat.sim[["air_temperature"]][dat.mod$time.day == 
                                                                                        (i - 1), ], 2, min))[, 1]
          sim.lag$lag.air_temperature_max <- stack(apply(dat.sim[["air_temperature"]][dat.mod$time.day == 
                                                                                        (i - 1), ], 2, max))[, 1]
        }
        dat.temp <- merge(dat.temp, sim.lag, all.x = TRUE)
      } else if (v == "precipitation_flux") {
        rows.now <- which(dat.mod$time.day == i)
        dat.temp <- dat.mod[rows.now, dat.info]
        
        dat.temp[[v]] <- 99999
        dat.temp$rain.prop <- 99999
        
        day.now <- unique(dat.temp$doy)
        
        # Set up the lags This is repeated differently because Precipitation
        # dat.temp is merged
        if (i == min(dat.mod$time.day)) {
          sim.lag <- stack(lags.init[[v]])
          names(sim.lag) <- c(paste0("lag.", v), "ens")
          
        } else {
          sim.lag <- stack(data.frame(array(dat.sim[[v]][dat.mod$time.day == 
                                                           (i - 1) & dat.mod$hour == max(unique(dat.mod$hour)), 
                                                         ], dim = c(1, ncol(dat.sim[[v]])))))
          names(sim.lag) <- c(paste0("lag.", v), "ens")
        }
        dat.temp <- merge(dat.temp, sim.lag, all.x = TRUE)
        
        # End Precipitation Flux specifics
      } else {
        
        if (i == min(dat.mod$time.day)) {
          sim.lag <- stack(lags.init[[v]])
          names(sim.lag) <- c(paste0("lag.", v), "ens")
          
        } else {
          sim.lag <- stack(data.frame(array(dat.sim[[v]][dat.mod$time.day == 
                                                           (i - 1) & dat.mod$hour == max(unique(dat.mod$hour)), 
                                                         ], dim = c(1, ncol(dat.sim[[v]])))))
          names(sim.lag) <- c(paste0("lag.", v), "ens")
        }
        dat.temp <- dat.mod[rows.now, dat.info]
        dat.temp <- merge(dat.temp, sim.lag, all.x = TRUE)
      }
      
      # Create dummy value
      dat.temp[[v]] <- 99999
      
      # Load the saved model
      load(file.path(path.model, v, paste0("model_", v, "_", day.now, 
                                           ".Rdata")))
      
      # Pull coefficients (betas) from our saved matrix
      betas_nc <- ncdf4::nc_open(file.path(path.model, v, paste0("betas_", 
                                                                 v, "_", day.now, ".nc")))
      Rbeta <- as.matrix(ncdf4::ncvar_get(betas_nc, paste(day.now))[as.integer(rows.beta[(i * 
                                                                                            n.ens - n.ens + 1):(i * n.ens)]), ], nrow = length(rows.beta), 
                         ncol = ncol(betas_nc))
      ncdf4::nc_close(betas_nc)
      dat.pred <- subdaily_pred(newdata = dat.temp, model.predict = mod.save, 
                                Rbeta = Rbeta, resid.err = FALSE, model.resid = NULL, Rbeta.resid = NULL, 
                                n.ens = n.ens)
      
      #----- Now we do a little quality control per variable
      
      # Make Sure that Shortwave is above 0
      if (v == "surface_downwelling_shortwave_flux_in_air") {
        dat.pred[dat.pred < 0] <- 0
      }
      
      # Precipitation Re-distribute negative probabilities -- add randomly to
      # make more peaky If there's no rain on this day, skip the
      # re-proportioning
      if (v == "precipitation_flux") {
        if (max(dat.pred) > 0) {
          tmp <- 1:nrow(dat.pred)  # A dummy vector of the 
          for (j in 1:ncol(dat.pred)) {
            if (min(dat.pred[, j]) >= 0) 
              next
            rows.neg <- which(dat.pred[, j] < 0)
            rows.add <- sample(tmp[!tmp %in% rows.neg], length(rows.neg), 
                               replace = TRUE)
            
            for (z in 1:length(rows.neg)) {
              dat.pred[rows.add[z], j] <- dat.pred[rows.add[z], 
                                                   j] - dat.pred[rows.neg[z], j]
              dat.pred[rows.neg[z], j] <- 0
            }
          }
          dat.pred <- dat.pred/rowSums(dat.pred)
          dat.pred[is.na(dat.pred)] <- 0
        }
        # Convert precip into real units
        dat.pred <- dat.pred * as.vector((dat.temp$precipitation_flux.day))
      }
      
      # Longwave needs some sanity bounds
      if (v == "surface_downwelling_longwave_flux_in_air") {
        dat.pred <- dat.pred^2  # because squared to prevent negative numbers
        dat.pred[dat.pred < 100] <- 100
        dat.pred[dat.pred > 600] <- 600
      }
      
      # Specific Humidity sometimes ends up with high or infinite values
      if (v == "specific_humidity") {
        dat.pred <- exp(dat.pred)  # because log-transformed
        if (max(dat.pred) > 0.03) {
          specific_humidity.fix <- ifelse(quantile(dat.pred, 0.99) < 
                                            0.03, quantile(dat.pred, 0.99), 0.03)
          dat.pred[dat.pred > specific_humidity.fix] <- specific_humidity.fix
        }
      }
      
      # Wind speed quality control
      if (v == "wind_speed") {
        dat.pred <- dat.pred^2  # because square-rooted to prevent negative
      }
      # ---------- End Quality Control
      
      # ---------- Begin propogating values and saving values Shortwave
      # Radiaiton
      if (v == "surface_downwelling_shortwave_flux_in_air") {
        # Randomly pick which values to save & propogate
        cols.prop <- as.integer(cols.list[(i * n.ens - n.ens + 
                                             1):(i * n.ens)])
        for (j in 1:ncol(dat.sim[[v]])) {
          dat.sim[[v]][rows.mod, j] <- dat.pred[, cols.prop[j]]
        }
        
        dat.sim[[v]][rows.now[!rows.now %in% rows.mod], ] <- 0
      } else if (v == "air_temperature") {
        for (j in 1:ncol(dat.sim$air_temperature)) {
          cols.prop <- as.integer(cols.list[(i * n.ens - n.ens + 
                                               1):(i * n.ens)])
          
          dat.prop <- dat.pred[dat.temp$ens == paste0("X", j), 
                               cols.prop[j]]
          air_temperature_max.ens <- max(dat.temp[dat.temp$ens == 
                                                    paste0("X", j), "air_temperature_max.day"])
          air_temperature_min.ens <- min(dat.temp[dat.temp$ens == 
                                                    paste0("X", j), "air_temperature_min.day"])
          
          dat.prop[dat.prop > air_temperature_max.ens + 2] <- air_temperature_max.ens + 
            2
          dat.prop[dat.prop < air_temperature_min.ens - 2] <- air_temperature_min.ens - 
            2
          
          dat.sim[["air_temperature"]][rows.now, j] <- dat.prop
        }
      } else {
        
        cols.prop <- as.integer(cols.list[(i * n.ens - n.ens + 
                                             1):(i * n.ens)])
        for (j in 1:ncol(dat.sim[[v]])) {
          dat.sim[[v]][rows.now, j] <- dat.pred[dat.temp$ens == 
                                                  paste0("X", j), cols.prop[j]]
        }
      }
      rm(mod.save)  # Clear out the model to save memory
    }
    pb.index <- pb.index + 1
    setTxtProgressBar(pb, pb.index)
  }  # ---------- End of downscaling for loop
  return(dat.sim)
}