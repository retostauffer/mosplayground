# -------------------------------------------------------------------
# - NAME:        GFS_test.R
# - AUTHOR:      Reto Stauffer
# - DATE:        2018-11-05
# -------------------------------------------------------------------
# - DESCRIPTION:
# -------------------------------------------------------------------
# - EDITORIAL:   2018-11-05, RS: Created file on thinkreto.
# -------------------------------------------------------------------
# - L@ST MODIFIED: 2018-11-05 10:24 on marvin
# -------------------------------------------------------------------

    Sys.setenv("TZ" = "UTC")
    rm(list = ls())
    library("zoo")


# -------------------------------------------------------------------
# Checking wt bets RMSE
# -------------------------------------------------------------------
    get_wetterturnier_fcst <- function(param, station, user) {
        library("RMySQL")
        library("zoo")
        options(warn =  -1)
        con <- dbConnect(MySQL(), host = "localhost", user = "rouser",
                         password = "readonly", dbname = "wpwt")
        # Getting param
        res <- dbSendQuery(con, sprintf("SELECT paramID FROM wp_wetterturnier_param WHERE paramName = '%s'", param))
        tmp <- fetch(res, 1); dbClearResult(res)
        stopifnot(nrow(tmp) == 1)
        paramID = as.integer(tmp$paramID[1])
        ###cat(sprintf("Parameter ID: %d\n", paramID))
        # Getting city
        res <- dbSendQuery(con, sprintf("SELECT cityID FROM wp_wetterturnier_stations WHERE wmo = %d", station))
        tmp <- fetch(res, 1); dbClearResult(res)
        stopifnot(nrow(tmp) == 1)
        cityID = as.integer(tmp$cityID)[1]
        ###cat(sprintf("Parameter cityID: %d\n", cityID))
        # Getting user
        res <- dbSendQuery(con, sprintf("SELECT ID FROM wp_users WHERE user_login = '%1$s' OR user_nicename = '%1$s'", user))
        tmp <- fetch(res, 1); dbClearResult(res)
        stopifnot(nrow(tmp) == 1)
        userID = as.integer(tmp$ID)[1]
        ###cat(sprintf("Parameter userID: %d\n", userID))
        # Getting observations
        res <- dbSendQuery(con, paste("SELECT betdate, value FROM wp_wetterturnier_obs WHERE ",
                                      sprintf("station = %d AND paramID = %d", station, paramID)))
        obs <- fetch(res, -1); dbClearResult(res)
        obs <- zoo(data.frame(obs = obs$value / 10), as.Date(obs$betdate, origin = "1970-01-01"))
        # Getting forecasts
        res <- dbSendQuery(con, paste("SELECT tdate, betdate, value FROM wp_wetterturnier_bets WHERE ",
                                      sprintf("cityID = %d AND userID = %d AND paramID = %d", cityID, userID, paramID)))
        bet <- fetch(res, -1); dbClearResult(res)
        bet <- zoo(data.frame(bet = bet$value / 10, day = bet$betdate - bet$tdate), as.Date(bet$betdate, origin = "1970-01-01"))
        dbDisconnect(con)
        options(warn = 0)
        # Renaming
        data <- na.omit(cbind(obs, bet))
        if ( nrow(data) == 0 ) return(NULL)
        names(obs) <- param
        names(bet)[1] <- param
        with(subset(data, day == 1),
             cat(sprintf("RMSE day 1:  %5.2f  (%s)\n", sqrt(mean((obs - bet)^2)), user)))
        with(subset(data, day == 2),
             cat(sprintf("RMSE day 2:  %5.2f  (%s)\n", sqrt(mean((obs - bet)^2)), user)))
        # Invisible return
        invisible(list(data = data, bets = bet, obs = obs, user = user, station = station))
    
    }
    

# -------------------------------------------------------------------
# Loading GFS
# -------------------------------------------------------------------
    load_GFS <- function(stn, stp, param, obshour, persistence = FALSE) {

        files <- list.files("rds")
        files <- sprintf("rds/%s", files[grep(sprintf("%s.rds$", stn), files)])
        
        
        data <- list()
        for ( f in files ) {
            cat(sprintf("Reading %s\r", f))
            tmp <- readRDS(f)
            tmp <- subset(tmp[[stn]], step == stp)
            if ( nrow(tmp) == 0 ) next
            data[[f]] <- tmp
        }; cat("\n")

        require("data.table")
        zoo_index <- sapply(data, index)
        zoo_data  <- data.table::rbindlist(lapply(data, function(x) as.data.frame(coredata(x))),
                                           use.names = TRUE, fill = TRUE)
        # ----------------------------
        data <- zoo(zoo_data, as.POSIXct(zoo_index, origin = "1970-01-01"))
        rm(list = c("zoo_index", "zoo_data"))
        idx <- which(apply(data, 2, function(x) sum(is.na(x))/length(x)) > .2)
        if ( length(idx) > 0 ) data <- data[,-idx]
        cat("Forecasts loaded ...\n")
        print(head(data[,1:5], 3))
        kill <- which(apply(data, 2, function(x) sum(is.na(x))/length(x)) > 0.1)
        if ( length(kill) > 0 ) data[,-kill]
        
        # ----------------------------
        library("RMySQL")
        con <- dbConnect(RSQLite::SQLite(), "obs_sqlite3/obs_11120.sqlite3")
        res <- dbSendQuery(con, sprintf("SELECT datumsec, %s FROM obs;", param))
        obs <- fetch(res, -1)
        dbClearResult(res)
        dbDisconnect(con)
        obs <- zoo(obs[,-1] / 10, as.POSIXct(obs[,1], origin = "1970-01-01"))
        obs <- subset(obs, as.POSIXlt(index(obs))$hour == obshour)
        cat("Observations loaded ...\n")
        print(head(obs, 3))

        # ----------------------------
        # Devel output
        cat("\n-----------------------------\n")
        cat(sprintf("Index range GFS forecasts: %s\n", paste(sprintf("%s", range(index(data))), collapse = " - ")))
        cat(sprintf("Index range observations:  %s\n", paste(sprintf("%s", range(index(obs))), collapse = " - ")))
        cat("-----------------------------\n")
        
        index(obs)  <- as.Date(index(obs))
        index(data) <- as.Date(index(data))

        data <- na.omit(cbind(obs, data))
        cat("Head of combined obs/fcst data ...\n")
        print(head(data[,1:5], 3))

        yday <- as.POSIXlt(index(data))$yday
        data$sin  <- sin(yday / 365 * 2 * pi) 
        data$cos  <- sin(yday / 365 * 2 * pi) 
        data$sin2 <- sin(yday / 365 * 4 * pi) 
        data$cos2 <- sin(yday / 365 * 4 * pi) 

        # Perisstence
        if ( persistence ) {
            cat(sprintf("Adding persistence, lag -%d\n", ceiling(stp/24)))
            pers <- lag(data$obs, -ceiling(stp/24))
            data <- na.omit(merge(data, pers))
            print(tail(subset(data, select = c(obs, pers))))
        }

        return(data)
    }


# -------------------------------------------------------------------
# TESTING TTm
# -------------------------------------------------------------------
    if ( TRUE ) {

        # Some definitions
        stp   <- 12 + 24*2
        city  <- "IBK"
        stn   <- 11120
        param <- "TTm"
        obsparam <- "Tmax12"
        persistence <- TRUE

        # Some definitions
        stp   <- 12 + 24*1
        city  <- "IBK"
        stn   <- 11120
        param <- "PPP"
        obsparam <- "pmsl"
        obshour <- 12
        persistence <- TRUE

        # Some definitions
        stp   <- 12 + 24*2
        city  <- "IBK"
        stn   <- 11120
        param <- "TTm"
        obsparam <- "tmax12"
        obshour <- 18
        persistence <- TRUE#FALSE

        # Checking wetterturnier RMSE from some good players
        get_wetterturnier_fcst(param, stn, "Georg")
        get_wetterturnier_fcst(param, stn, "adri_der_pinner")
        get_wetterturnier_fcst(param, stn, "DWD-MOS-Mix")
        get_wetterturnier_fcst(param, stn, "DWD-EZ-Mos")

        data <- load_GFS(city, stp, obsparam, obshour, persistence)
        print(head(data[,1:3]))

        x <- data[,grep("^(obs|C.t[0-9]+m?)$", names(data))]
        par(mfrow = c(2,3))
        for ( i in 2:ncol(x) ) {
            cat(sprintf("%-10s  %10.5f\n", names(x)[i], cor(x[,1], x[,i])))
            plot(x[,1], x[,i], main = names(x)[i])
        }
        
        idx <- which(apply(data, 2, function(x) sum(is.na(x)) / length(x)) > .1)
        if ( length(idx) > 0 ) data <- data[,-idx]
        
        
        library("glmnet")
        y <- as.vector(data[,1])
        X <- as.matrix(data[,-1])
        m <- cv.glmnet(X, y, nlambda = 200)
        f <- predict(m, newx = X, s = "lambda.min")
        print(sqrt(mean((f-y)^2)))
        f1 <- zoo(f, index(data))
        print(tail(f1,10))
        stop()
        
        X2  <- X
        idx <- which(apply(X2, 2, sd) == 0)
        X2 <- apply(X2, 2, scale)
        if ( length(idx) > 0 ) X2 <- X2[,-idx]
        m <- cv.glmnet(X2, y, nlambda = 200)
        f <- predict(m, newx = X2, s = "lambda.min")
        print(sqrt(mean((f-y)^2)))
        f1 <- zoo(f, index(data))
        #plot(f, y, xlab = "predicted", ylab = "observed")
        
        library("randomForest")
        
        d <- data[,grep("^(obs|C\\.)", names(data))]
        wald = randomForest(obs ~ . , data = d)
        f <- predict(wald)
        print(sqrt(mean((f-y)^2, na.rm = TRUE)))
        #plot(f, data$obs)
        
        
        
        # Rolling N
        n <- 80
        y <- as.vector(data[,1])
        X <- as.matrix(data[,-1])
        fcst <- rep(NA, length(y))
        pb <- txtProgressBar(0, length(y), style = 3)
        for ( i in seq(n+1, nrow(X)) ) {
            setTxtProgressBar(pb,i)
            idx <- seq(i - n, i - 1)
            m <- glmnet(X[idx,], as.vector(y[idx]), nlambda = 100)
            fcst[i] <- predict(m, X[i+c(-1,0),])
        }; close(pb)
        print(sqrt(mean((fcst-y)^2, na.rm=TRUE)))
        
        
        # Rolling N
        n <- 80
        y <- as.vector(data[,1])
        X <- as.matrix(data[,grep("^C\\.", names(data))])
        fcst <- rep(NA, length(y))
        pb <- txtProgressBar(0, length(y), style = 3)
        for ( i in seq(n+1, nrow(X)) ) {
            setTxtProgressBar(pb,i)
            idx <- seq(i - n, i - 1)
            m <- glmnet(X[idx,], as.vector(y[idx]), nlambda = 100)
            fcst[i] <- predict(m, X[i+c(-1,0),])
        }; close(pb)
        print(sqrt(mean((fcst-y)^2, na.rm=TRUE)))
        
        
        # Rolling N
        fcst <- rep(NA, length(y))
        pb <- txtProgressBar(0, length(y), style = 3)
        for ( i in seq(n+1, nrow(X)) ) {
            setTxtProgressBar(pb,i)
            idx <- seq(i - n, i - 1)
            m0 <- lm(obs ~ C.t2m, data = data[idx,])
            m <- step(m0, list(lower = m0, upper = formula(obs ~ .)), direction = "forward", k = log(n))
            fcst[i] <- predict(m, newdata = data[i,])
        }; close(pb)
        print(sqrt(mean((fcst-y)^2, na.rm=TRUE)))
        
        library("crch")
        data <- data[,apply(data, 2, sd) > 0]
        c <- crch(obs ~ . , data = data, control = crch.boost(mstop = "aic", maxit = 1000))
        f <- predict(c, mstop = c$mstopopt["aic"], newdata = data) 
        print(sqrt(mean((f-data$obs)^2, na.rm=TRUE)))
        
        library("crch")
        d <- data[,grep("^(obs|C\\.)", names(data))]
        c <- crch(obs ~ . , data = d, control = crch.boost(mstop = "aic", maxit = 1000))
        f <- predict(c, mstop = c$mstopopt["aic"], newdata = data) 
        print(sqrt(mean((f-data$obs)^2, na.rm=TRUE)))

    }













