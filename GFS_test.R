# -------------------------------------------------------------------
# - NAME:        GFS_test.R
# - AUTHOR:      Reto Stauffer
# - DATE:        2018-11-05
# -------------------------------------------------------------------
# - DESCRIPTION:
# -------------------------------------------------------------------
# - EDITORIAL:   2018-11-05, RS: Created file on thinkreto.
# -------------------------------------------------------------------
# - L@ST MODIFIED: 2018-12-09 18:55 on marvin
# -------------------------------------------------------------------

    rm(list = ls())
    library("zoo")
    library("mospack")


    library("devtools")
    load_all("mospack")

# --------------------------------------------------------------
# --------------------------------------------------------------
# --------------------------------------------------------------
# --------------------------------------------------------------
# --------------------------------------------------------------


    # Loading GFS data (once)
    station <- "IBK"
    cached_file <- sprintf("rds/prepared_GFS_%s.rds", station)
    if ( file.exists(cached_file) ) {
        cat(sprintf("[!] Reading cached file \"%s\"\n", cached_file))
        GFS <- readRDS(cached_file)
    } else {
        cat("[!] Prepare GFS (takes some seconds)\n")
        GFS <- GFS_load(station)
        cat(sprintf("    Save prepared file as \"%s\"\n", cached_file))
        saveRDS(GFS, cached_file)
    }
    # Kill those I don't want to have
    take <- sprintf("step_%02d", seq(18, 84, by = 3))
    GFS <- GFS[which(names(GFS) %in% take)]

    # Latest GFS Forecast
    files  <- list.files("rds")
    files  <- files[grep("^GFS_[0-9]{8}_0000.rds", files)]
    latest <- max(as.Date(strptime(files, "GFS_%Y%m%d_%H%M.rds")))
    cat(sprintf("Latest GFS forecast interpolated and available: %s\n", latest))
    GFS_latest <- GFS_load(station, dates = latest) 
    GFS_latest <- GFS_latest[which(names(GFS_latest) %in% take)]

# --------------------------------------------------------------
# --------------------------------------------------------------
# --------------------------------------------------------------
# --------------------------------------------------------------
# --------------------------------------------------------------


    library("devtools")
    load_all("mospack")

    TTm <- get_observations("TTm", 11120)
    #TTm_pers <- lag(TTm, -2)
    #head(merge(TTm, TTm_pers))
    prep <- lapply(GFS, combine_obs_GFS, obs = TTm, killneighbours = TRUE, scale = FALSE)

    # The steps for which we need the prediction(s)
    TTm_steps  <- c(24 + c(9, 12, 15, 18), 48 + c(9, 12, 15, 18))
    TTm_steps  <- setNames(TTm_steps, sprintf("step_%02d", TTm_steps))

    modelfun <- function(stp, prep, result = "forecast") {
        stabsel(obs ~ ., data = prep[[sprintf("step_%02d", stp)]], n = 20, q = 30, train = .8, result = result)
    }
    TTm_mods <- lapply(TTm_steps, modelfun, prep = prep, result = "both")

    sc <- do.call(rbind, lapply(TTm_mods, function(x) unlist(x$scores)))
    print(round(sc, 4))

    # Kommt nicht wirklich an die stability selection ran
    ##library("devtools")
    ##load_all("mospack")
    ##x <- stepwise_lm(obs ~ ., data = prep$step_36, result = "both")

    fcst <- matrix(NA, ncol = 2, nrow = 6, dimnames = list(NULL, c("day1", "day2")))
    fcst[1,"day1"] <- predict(TTm_mods$step_33$model, newdata = GFS_latest$step_33)
    fcst[2,"day1"] <- predict(TTm_mods$step_36$model, newdata = GFS_latest$step_36)
    fcst[3,"day1"] <- predict(TTm_mods$step_39$model, newdata = GFS_latest$step_39)
    fcst[4,"day1"] <- predict(TTm_mods$step_42$model, newdata = GFS_latest$step_42)
    fcst[5,"day1"] <- mean(fcst[1:4,"day1"])
    fcst[6,"day1"] <- max(fcst[1:4,"day1"])

    fcst[1,"day2"] <- predict(TTm_mods$step_57$model, newdata = GFS_latest$step_57)
    fcst[2,"day2"] <- predict(TTm_mods$step_60$model, newdata = GFS_latest$step_60)
    fcst[3,"day2"] <- predict(TTm_mods$step_63$model, newdata = GFS_latest$step_63)
    fcst[4,"day2"] <- predict(TTm_mods$step_66$model, newdata = GFS_latest$step_66)
    fcst[5,"day2"] <- mean(fcst[1:4,"day2"])
    fcst[6,"day2"] <- max(fcst[1:4,"day2"])



# --------------------------------------------------------------
# --------------------------------------------------------------
# --------------------------------------------------------------
# --------------------------------------------------------------
# --------------------------------------------------------------

    library("devtools")
    load_all("mospack")

    TEMP <- get_observations_raw("t", 11120)

    prep <- lapply(GFS, combine_obs_GFS_hourly, obs = TEMP, killneighbours = TRUE, scale = FALSE)

    # Subsetting data
    ydays <- as.POSIXlt(latest)$yday + seq(-40, 40)
    ydays[ydays <   0] <- ydays[ydays <   0] + 365
    ydays[ydays > 365] <- ydays[ydays > 365] - 365

    subsetfun <- function(x, ydays) {
        tmp <- as.POSIXlt(index(x))$yday
        x[which(tmp %in% ydays),]
    }
    prep <- lapply(prep, subsetfun, ydays = ydays)


    # The steps for which we need the prediction(s)
    TEMP_steps  <- structure(seq(18, 84, by = 3), names = sprintf("step_%02d", seq(18, 84, by = 3)))
    modelfun <- function(stp, prep, result = "forecast") {
        stabsel(obs ~ ., data = prep[[sprintf("step_%02d", stp)]], n = 20, q = 30, train = .8, result = result)
    }
    TEMP_mods <- lapply(TEMP_steps, modelfun, prep = prep, result = "both")

    sc <- do.call(rbind, lapply(TEMP_mods, function(x) unlist(x$scores)))
    print(round(sc, 4))
    print(apply(sc, 2, mean))


    # Prediction
    fcstfun <- function(x, mods, latest) {
        zoo(predict(mods[[x]]$model, newdata = latest[[x]]), index(latest[[x]]))
    }
    TEMP_fcst <- lapply(names(TEMP_mods), fcstfun, mods = TEMP_mods, latest = GFS_latest)
    TEMP_fcst <- do.call(rbind, TEMP_fcst)

    tmp_gfs <- do.call(rbind, lapply(GFS_latest, function(x) x$C.t2m)) - 273.15
    x <- merge(TEMP, TEMP_fcst, tmp_gfs, all = FALSE)
    plot(x, screen = 1, col = c(2,1,4))



# --------------------------------------------------------------
# --------------------------------------------------------------
# --------------------------------------------------------------
# --------------------------------------------------------------
# --------------------------------------------------------------

    library("devtools")
    load_all("mospack")

    PRES <- get_observations_raw("pmsl", 11120)
    PRES <- subset(PRES, PRES < 1000)

    prep <- lapply(GFS, combine_obs_GFS_hourly, obs = PRES, killneighbours = TRUE, scale = FALSE)

    # Subsetting data
    ydays <- as.POSIXlt(latest)$yday + seq(-40, 40)
    ydays[ydays <   0] <- ydays[ydays <   0] + 365
    ydays[ydays > 365] <- ydays[ydays > 365] - 365

    subsetfun <- function(x, ydays) {
        tmp <- as.POSIXlt(index(x))$yday
        x[which(tmp %in% ydays),]
    }
    prep <- lapply(prep, subsetfun, ydays = ydays)



    # The steps for which we need the prediction(s)
    PRES_steps  <- structure(seq(18, 84, by = 3), names = sprintf("step_%02d", seq(18, 84, by = 3)))
    modelfun <- function(stp, prep, result = "forecast") {
        stabsel(obs ~ ., data = prep[[sprintf("step_%02d", stp)]], n = 20, q = 30, train = .8, result = result)
    }
    PRES_mods <- lapply(PRES_steps, modelfun, prep = prep, result = "both")

    sc <- do.call(rbind, lapply(PRES_mods, function(x) unlist(x$scores)))
    print(round(sc, 4))
    print(apply(sc, 2, mean))

    # Prediction
    fcstfun <- function(x, mods, latest) {
        zoo(predict(mods[[x]]$model, newdata = latest[[x]]), index(latest[[x]]))
    }
    PRES_fcst <- lapply(names(PRES_mods), fcstfun, mods = PRES_mods, latest = GFS_latest)
    PRES_fcst <- do.call(rbind, PRES_fcst)

    tmp_gfs <- do.call(rbind, lapply(GFS_latest, function(x) x$C.pmsl)) / 100
    x <- merge(PRES, PRES_fcst, tmp_gfs, all = FALSE)
    plot(x, screen = 1, col = c(2,1,4))



# --------------------------------------------------------------
# --------------------------------------------------------------
# --------------------------------------------------------------
# --------------------------------------------------------------
# --------------------------------------------------------------

    library("devtools")
    load_all("mospack")

    rain <- get_observations("RR", 11120)
    pop  <- zoo(as.numeric(rain$rr6 >= 0), index(rain))

    prep <- lapply(GFS, combine_obs_GFS_hourly, obs = pop, killneighbours = TRUE, scale = FALSE)

    ## Subsetting data
    #ydays <- as.POSIXlt(latest)$yday + seq(-40, 40)
    #ydays[ydays <   0] <- ydays[ydays <   0] + 365
    #ydays[ydays > 365] <- ydays[ydays > 365] - 365

    #subsetfun <- function(x, ydays) {
    #    tmp <- as.POSIXlt(index(x))$yday
    #    x[which(tmp %in% ydays),]
    #}
    #prep <- lapply(prep, subsetfun, ydays = ydays)



    # The steps for which we need the prediction(s)
    POP_steps  <- structure(seq(18, 84, by = 6), names = sprintf("step_%02d", seq(18, 84, by = 6)))
    modelfun <- function(stp, prep, result = "forecast") {
        stabsel(obs ~ ., data = prep[[sprintf("step_%02d", stp)]], family = "binomial",
                n = 20, q = 30, train = .8, result = result)
    }
    POP_mods <- lapply(POP_steps, modelfun, prep = prep, result = "both")

#    sc <- do.call(rbind, lapply(PRES_mods, function(x) unlist(x$scores)))
#    print(round(sc, 4))
#    print(apply(sc, 2, mean))
#
#    # Prediction
#    fcstfun <- function(x, mods, latest) {
#        zoo(predict(mods[[x]]$model, newdata = latest[[x]]), index(latest[[x]]))
#    }
#    PRES_fcst <- lapply(names(PRES_mods), fcstfun, mods = PRES_mods, latest = GFS_latest)
#    PRES_fcst <- do.call(rbind, PRES_fcst)
#
#    tmp_gfs <- do.call(rbind, lapply(GFS_latest, function(x) x$C.pmsl)) / 100
#    x <- merge(PRES, PRES_fcst, tmp_gfs, all = FALSE)
#    plot(x, screen = 1, col = c(2,1,4))



# --------------------------------------------------------------
# --------------------------------------------------------------
# --------------------------------------------------------------
# --------------------------------------------------------------
# --------------------------------------------------------------

    library("devtools")
    load_all("mospack")

    PPP <- get_observations("PPP", 11120)
    #TTm_pers <- lag(TTm, -2)
    #head(merge(TTm, TTm_pers))
    prep <- lapply(GFS, combine_obs_GFS, obs = PPP, killneighbours = TRUE, scale = FALSE)

    # The steps for which we need the prediction(s)
    PPP_steps  <- c(33, 36, 39, 57, 60, 63)
    PPP_steps  <- setNames(PPP_steps, sprintf("step_%02d", PPP_steps))

    modelfun <- function(stp, prep, result = "forecast") {
        stabsel(obs ~ ., data = prep[[sprintf("step_%02d", stp)]], n = 20, q = 30, train = .8, result = result)
    }
    PPP_fcst <- lapply(PPP_steps, modelfun, prep = prep, result = "forecast")
    PPP_mods <- lapply(PPP_steps, modelfun, prep = prep, result = "model")

    res <- na.omit(merge(PPP, do.call(merge, PPP_fcst)))
    res$mean_d1 <- apply(res[,grep(".*(33|36|39)$", names(res))], 1, mean)
    res$mean_d2 <- apply(res[,grep(".*(57|60|63)$", names(res))], 1, mean)
    for ( i in 2:ncol(res) ) {
        RMSE <- sqrt(mean((res[,1] - res[,i])^2))
        cat(sprintf("Brier Score %5s:  %10.2f\n", names(res)[i], RMSE))
    }


    fcst <- matrix(NA, ncol = 2, nrow = 4, dimnames = list(NULL, c("day1", "day2")))
    fcst[1,"day1"] <- predict(PPP_mods$step_33, newdata = GFS_latest$step_33)
    fcst[2,"day1"] <- predict(PPP_mods$step_36, newdata = GFS_latest$step_36)
    fcst[3,"day1"] <- predict(PPP_mods$step_39, newdata = GFS_latest$step_39)
    fcst[4,"day1"] <- mean(fcst[1:3,"day1"])

    fcst[1,"day2"] <- predict(PPP_mods$step_57, newdata = GFS_latest$step_57)
    fcst[2,"day2"] <- predict(PPP_mods$step_60, newdata = GFS_latest$step_60)
    fcst[3,"day2"] <- predict(PPP_mods$step_63, newdata = GFS_latest$step_63)
    fcst[4,"day2"] <- mean(fcst[1:3,"day2"])



    stop(" --------- devel stop ------------ ")

# --------------------------------------------------------------
# --------------------------------------------------------------
# --------------------------------------------------------------
# --------------------------------------------------------------
# --------------------------------------------------------------

    library("devtools")
    load_all("mospack")

    TTd <- get_observations("TTd", 11120)
    #TTm_pers <- lag(TTm, -2)
    #head(merge(TTm, TTm_pers))
    prep <- lapply(GFS, combine_obs_GFS, obs = TTd, killneighbours = TRUE, scale = FALSE)

    # The steps for which we need the prediction(s)
    TTd_steps  <- c(36, 60)
    TTd_steps  <- setNames(TTd_steps, sprintf("step_%02d", TTd_steps))

    modelfun <- function(stp, prep, result = "forecast") {
        stabsel(obs ~ ., data = prep[[sprintf("step_%02d", stp)]], n = 20, q = 30, train = .8, result = result)
    }
    TTd_fcst <- lapply(TTd_steps, modelfun, prep = prep, result = "forecast")
    TTd_mods <- lapply(TTd_steps, modelfun, prep = prep, result = "model")

    res <- na.omit(merge(TTd, do.call(merge, TTd_fcst)))
    for ( i in 2:ncol(res) ) {
        RMSE <- sqrt(mean((res[,1] - res[,i])^2))
        cat(sprintf("Brier Score %5s:  %10.2f\n", names(res)[i], RMSE))
    }


    fcst <- matrix(NA, ncol = 2, nrow = 1, dimnames = list(NULL, c("day1", "day2")))
    fcst[1,"day1"] <- predict(TTd_mods$step_36, newdata = GFS_latest$step_36)
    fcst[1,"day2"] <- predict(TTd_mods$step_60, newdata = GFS_latest$step_60)

    print(fcst)


# --------------------------------------------------------------
# --------------------------------------------------------------
# --------------------------------------------------------------
# --------------------------------------------------------------
# --------------------------------------------------------------

    library("devtools")
    load_all("mospack")

    N <- get_observations("N", 11120)
    #TTm_pers <- lag(TTm, -2)
    #head(merge(TTm, TTm_pers))
    prep <- lapply(GFS, combine_obs_GFS, obs = N, killneighbours = TRUE, scale = FALSE)

    # The steps for which we need the prediction(s)
    N_steps  <- c(36, 60)
    N_steps  <- setNames(N_steps, sprintf("step_%02d", N_steps))

    modelfun <- function(stp, prep, result = "forecast") {
        stabsel(obs ~ ., data = prep[[sprintf("step_%02d", stp)]], n = 20, q = 30, train = .8, result = result)
    }
    N_fcst <- lapply(N_steps, modelfun, prep = prep, result = "forecast")
    N_mods <- lapply(N_steps, modelfun, prep = prep, result = "model")

    fcst <- matrix(NA, ncol = 2, nrow = 1, dimnames = list(NULL, c("day1", "day2")))
    fcst[1,"day1"] <- predict(N_mods$step_36, newdata = GFS_latest$step_36)
    fcst[1,"day2"] <- predict(N_mods$step_60, newdata = GFS_latest$step_60)

    print(fcst)

    ##library("crch")
    ##x <- crch(obs ~ ., data = prep[[1]], left = 0, right = 8, control = crch.boost())
    ##f <- predict(x, type = "response")
    ##print( sqrt( mean( (prep[[1]]$obs - f)^2 ) ) )

    ##res <- na.omit(merge(N, do.call(merge, N_fcst)))
    ##for ( i in 2:ncol(res) ) {
    ##    RMSE <- sqrt(mean((res[,1] - res[,i])^2))
    ##    cat(sprintf("Brier Score %5s:  %10.2f\n", names(res)[i], RMSE))
    ##}


    ##fcst <- matrix(NA, ncol = 2, nrow = 1, dimnames = list(NULL, c("day1", "day2")))
    ##fcst[1,"day1"] <- predict(N_mods$step_36, newdata = GFS_latest$step_36)
    ##fcst[1,"day2"] <- predict(N_mods$step_60, newdata = GFS_latest$step_60)


    ##library('randomForest')
    ##data <- prep$step_36
    ##rf <- randomForest(factor(obs) ~ ., data = data, mtry = ncol(data))
    ##rf_fcst <- zoo(predict(rf), index(data))


    ##library("party")
    ##control <- cforest_control(ntree = 200, mtry = ncol(data)) #, fraction = .63)
    ##rf <- cforest(factor(obs) ~ ., data = data, controls = control)
    ##rf_fcst <- zoo(predict(rf), index(data))


    ##rf_fcst <- zoo(rep(NA, nrow(data)), index(data))
    ##block <- rep(1:5, each = ceiling(nrow(data) / 5))[1:nrow(data)]
    ##for ( i in 1:5 ) {
    ##    idx <- which(block == i)
    ##    tmp <- cforest(factor(obs) ~ ., data = data[-idx,], controls = control)
    ##    rf_fcst[idx] <- as.numeric(as.character(predict(tmp, newdata = data[idx,])))
    ##}

    ##res <- na.omit(merge(N, rf_fcst, tr_fcst, N_fcst$step_36))
    ##names(res) <- c("N", "rf", "tr", "glm")
    ##display(res)


    ##library("party")
    ##control <- ctree_control(minsplit = 5, minbucket = 5, maxdepth = 10)
    ##tr <- ctree(factor(obs) ~ ., data = data, controls = control)
    ##tr_fcst <- zoo(predict(tr), index(data))
    ##pdf(file = "~/Downloads/Rplots.pdf", width = 16, height = 8)
    ##    plot(tr)
    ##dev.off()

    ##library("devtools")
    ##load_all("mospack")
    ##georg <- get_forecasts_wt("N", 11120, "Georg")
    ##georg <- georg$fcst1
    ##index(georg) <- as.POSIXct(index(georg)) + 12*3600
    ##dwd   <- get_forecasts_wt("N", 11120, "DWD-EZ-MOS")
    ##dwd   <- dwd$fcst1
    ##index(dwd) <- as.POSIXct(index(dwd)) + 12*3600

    ##display <- function(x) {
    ##    for ( i in 2:ncol(x) ) {
    ##        cat(sprintf("RMSE %10s  %10.2f\n", names(x)[i], sqrt(mean((x[,1]-x[,i])^2))))
    ##    }
    ##}

    ##res <- na.omit(merge(N, rf_fcst, tr_fcst, N_fcst$step_36))
    ##names(res) <- c("N", "rf", "tr", "glm")
    ##display(res)

    ##res <- na.omit(merge(N, rf_fcst, tr_fcst, N_fcst$step_36, georg, dwd))
    ##names(res) <- c("N", "rf", "tr", "glm", "georg", "dwd")
    ##display(res)

    ##pdf(file = "~/Downloads/Rplots.pdf", width = 16, height = 8)
    ##    par(mfrow = c(2,3))
    ##    plot(jitter(N) ~ jitter(rf),  data = res, main = "random forest")
    ##    plot(jitter(N) ~ jitter(tr),  data = res, main = "tree")
    ##    plot(jitter(N) ~ jitter(glm), data = res, main = "glmnet")
    ##    plot(jitter(N) ~ jitter(georg),  data = res, main = "georg")
    ##    plot(jitter(N) ~ jitter(dwd),    data = res, main = "dwd")
    ##dev.off()

    ##print(fcst)


# --------------------------------------------------------------
# --------------------------------------------------------------
# --------------------------------------------------------------
# --------------------------------------------------------------
# --------------------------------------------------------------

###    library("devtools")
###    load_all("mospack")
###
###    temp <- get_observations_raw("T", 11120)
###    prep <- lapply(GFS, combine_obs_GFS_hourly, obs = temp, killneighbours = TRUE, scale = FALSE)
###
###    # The steps for which we need the prediction(s)
###    T_steps  <- seq(18, 84, by = 6)
###    T_steps  <- setNames(T_steps, sprintf("step_%02d", T_steps))
###
###    modelfun <- function(stp, prep, result = "forecast") {
###        stabsel(obs ~ ., data = prep[[sprintf("step_%02d", stp)]], n = 20, q = 30, train = .5, result = result)
###    }
###    T_fcst <- lapply(T_steps, modelfun, prep = prep, result = "forecast")
###
###    # Did not perform well 
###    #boostmodelfun <- function(stp, prep, result = "forecast") {
###    #    cat(sprintf("Compute boosting model %d\n", stp))
###    #    data <- prep[[sprintf("step_%02d", stp)]]
###    #    boosted.crch(obs ~ . , data = data, result = "forecast", ncv = 10)
###    #}
###    #library("parallel")
###    #T_boostfcst <- mclapply(T_steps, boostmodelfun, prep = prep, result = "forecast", mc.cores = 3)
###
###    #RMSEfun <- function(stp, obs, fcst, boost) {
###    #    fcst  <- fcst[[sprintf("step_%02d", stp)]]
###    #    boost <- boost[[sprintf("step_%02d", stp)]]
###    #    x    <- na.omit(merge(obs, fcst, boost))
###    #    RMSE1 <- sqrt(mean((x[,1] - x[,2])^2))
###    #    RMSE2 <- sqrt(mean((x[,1] - x[,3])^2))
###    #    cat(sprintf("RMSE for step +%02d hours (%3d):    %10.2f    boost   %10.2f\n", stp, nrow(x), RMSE1, RMSE2))
###    #}
###    #dead_end <- sapply(T_steps, RMSEfun, obs = temp, fcst = T_fcst, boost = T_boostfcst)
###
###    RMSEfun <- function(stp, obs, fcst) {
###        fcst  <- fcst[[sprintf("step_%02d", stp)]]
###        x    <- na.omit(merge(obs, fcst))
###        RMSE <- sqrt(mean((x[,1] - x[,2])^2))
###        cat(sprintf("RMSE for step +%02d hours (%3d):    %10.2f\n", stp, nrow(x), RMSE, RMSE))
###    }
###    dead_end <- sapply(T_steps, RMSEfun, obs = temp, fcst = T_fcst)
###
###    T_mods <- lapply(T_steps, modelfun, prep = prep, result = "model")
###    fcstfun <- function(stp, latest, models) {
###        mod <- models[[sprintf("step_%02d", stp)]]
###        nd  <- latest[[sprintf("step_%02d", stp)]]
###        zoo(predict(mod, newdata = nd), index(nd))
###    }
###    fcst <- do.call(rbind, lapply(T_steps, fcstfun, latest = GFS_latest, models = T_mods) )
###
###    print(fcst)
###
###
###    stop(" --------- devel stop ------------ ")
# --------------------------------------------------------------
# --------------------------------------------------------------
# --------------------------------------------------------------
# --------------------------------------------------------------
# --------------------------------------------------------------
# --------------------------------------------------------------
# --------------------------------------------------------------
# --------------------------------------------------------------


# --------------------------------------------------------------
# --------------------------------------------------------------
# --------------------------------------------------------------
# --------------------------------------------------------------
# --------------------------------------------------------------

    library("devtools")
    load_all("mospack")

    ff <- get_observations("ff", 11120)
    prep <- lapply(GFS, combine_obs_GFS, obs = ff, killneighbours = TRUE, scale = FALSE)

    # The steps for which we need the prediction(s)
    ff_steps  <- c(36, 60)
    ff_steps  <- setNames(ff_steps, sprintf("step_%02d", ff_steps))

    modelfun <- function(stp, prep, result = "forecast") {
        stabsel(obs ~ ., data = prep[[sprintf("step_%02d", stp)]], n = 20, q = 30, train = .8, result = result)
    }
    ff_fcst <- lapply(ff_steps, modelfun, prep = prep, result = "forecast")
    ff_mods <- lapply(ff_steps, modelfun, prep = prep, result = "model")

    fcst <- matrix(NA, ncol = 2, nrow = 1, dimnames = list(NULL, c("day1", "day2")))
    fcst[1,"day1"] <- predict(ff_mods$step_36, newdata = GFS_latest$step_36)
    fcst[1,"day2"] <- predict(ff_mods$step_60, newdata = GFS_latest$step_60)

    print(fcst)


    res <- merge(prep$step_36$obs, ff_fcst$step_36)
    names(res) <- c("obs", "ff")
    plot(obs ~ ff, data = res, xlim = c(0,25), ylim = c(0,25))
    abline(0, 1, col = 2)





    library("devtools")
    load_all("mospack")

    fx <- get_observations("fx", 11120)
    prep <- lapply(GFS, combine_obs_GFS, obs = fx, killneighbours = TRUE, scale = FALSE)

    # The steps for which we need the prediction(s)
    fx_steps  <- c(36, 60)
    fx_steps  <- setNames(fx_steps, sprintf("step_%02d", fx_steps))

    modelfun <- function(stp, prep, result = "forecast") {
        stabsel(I(obs >= 25)  ~ ., data = prep[[sprintf("step_%02d", stp)]], family = "binomial",
                n = 20, q = 30, train = .8, result = result)
    }
    fxprob_fcst <- lapply(fx_steps, modelfun, prep = prep, result = "forecast")
    fxprob_mods <- lapply(fx_steps, modelfun, prep = prep, result = "model")

    data <- prep$step_36
    data$obs <- data$obs >= 25

    m0 <- glm(obs ~ 1, data = data, family = "binomial")
    m1 <- glm(obs ~ ., data = data, family = "binomial")
    m <- step(m0, list(lower = m0, upper = m1))
    print(m)

    modelfun <- function(stp, prep, result = "forecast") {
        stabsel(obs ~ ., data = prep[[sprintf("step_%02d", stp)]], n = 20, q = 30, train = .8, result = result)
    }
    fx_fcst <- lapply(fx_steps, modelfun, prep = prep, result = "forecast")
    fx_mods <- lapply(fx_steps, modelfun, prep = prep, result = "model")

    fcst <- matrix(NA, ncol = 2, nrow = 1, dimnames = list(NULL, c("day1", "day2")))
    fcst[1,"day1"] <- predict(fx_mods$step_36, newdata = GFS_latest$step_36)
    fcst[1,"day2"] <- predict(fx_mods$step_60, newdata = GFS_latest$step_60)

    print(fcst)


    res <- merge(prep$step_36$obs, fx_fcst$step_36)
    names(res) <- c("obs", "fx")
    plot(obs ~ fx, data = res, xlim = c(0,25), ylim = c(0,25))
    abline(0, 1, col = 2)

    #f <- boosted.crch(sqrt(obs) ~ ., left = 0, data = data)






    library("devtools")
    load_all("mospack")

    ffx6 <- mps2knots(get_observations_raw("ffx6", 11120, scale = 1))
    timefun <- function(x) as.POSIXct(ceiling(as.numeric(x) / 3600 / 3) * 3600 * 3, origin = "1970-01-01")
    aggfun <- function(x) { if ( sum(!is.na(x)) == 0 ) { return(0) } else { max(x, na.rm = TRUE) } }
    ffx6 <- aggregate(ffx6, timefun, aggfun) 

    prep <- lapply(GFS, combine_obs_GFS_hourly, obs = ffx6, killneighbours = TRUE, scale = FALSE)

    # The steps for which we need the prediction(s)
    fx_steps  <- seq(18, 84, by = 3)
    fx_steps  <- setNames(fx_steps, sprintf("step_%02d", fx_steps))

    modelfun <- function(stp, prep, result = "forecast") {
        #stabsel(I(obs >= 25)  ~ ., data = prep[[sprintf("step_%02d", stp)]], family = "binomial",
        #        n = 20, q = 30, train = .8, result = result)
        data <- prep[[sprintf("step_%02d", stp)]][,1:50]
        cross.glmnet(I(obs >= 25)  ~ ., data = data, family = "binomial",
                     s = "lambda.1se")
    }
    fxprob_fcst <- lapply(fx_steps, modelfun, prep = prep, result = "forecast")
    ##fxprob_mods <- lapply(fx_steps, modelfun, prep = prep, result = "model")

    for ( stp in fx_steps ) {
        o <- prep[[sprintf("step_%02d", stp)]]$obs 
        f <- fxprob_fcst[[sprintf("step_%02d", stp)]]
        x <- xtabs( ~ (f >= .5) + (o >= 25))
        print(x)
        #PC <- (x[1,1]+x[2,2])/sum(x) 
        #PW <- (x[1,2]+x[2,1])/sum(x) 
        #cat(sprintf("                  Step %02d    PC %5.1f    PW %5.1f\n", stp, PC*100, PW*100))
    }













