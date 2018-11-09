# -------------------------------------------------------------------
# - NAME:        GFS_test.R
# - AUTHOR:      Reto Stauffer
# - DATE:        2018-11-05
# -------------------------------------------------------------------
# - DESCRIPTION:
# -------------------------------------------------------------------
# - EDITORIAL:   2018-11-05, RS: Created file on thinkreto.
# -------------------------------------------------------------------
# - L@ST MODIFIED: 2018-11-08 23:54 on marvin
# -------------------------------------------------------------------

    Sys.setenv("TZ" = "UTC")
    rm(list = ls())
    library("zoo")


# -------------------------------------------------------------------
# Checking wt bets RMSE
# -------------------------------------------------------------------
    get_wetterturnier_obs <- function(param, station) {
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
        # Getting observations
        res <- dbSendQuery(con, paste("SELECT betdate, value FROM wp_wetterturnier_obs WHERE ",
                                      sprintf("station = %d AND paramID = %d", station, paramID)))
        obs <- fetch(res, -1); dbClearResult(res)
        obs <- zoo(data.frame(obs = obs$value / 10), as.Date(obs$betdate, origin = "1970-01-01"))
        # Getting forecasts
        dbDisconnect(con)
        options(warn = 0)
        # Renaming
        if ( nrow(obs) == 0 ) return(NULL)
        # Invisible return
        return(obs[,1])
    
    }

    compare <- function(obs, WT, jitter = FALSE) {
        stopifnot(inherits(obs, "zoo"))
        stopifnot(inherits(WT, "zoo"))
        stopifnot(is.null(dim(obs)))
        stopifnot(is.null(dim(WT)))
        index(obs) <- as.Date(index(obs))
        x <- zoo(na.omit(merge(obs, WT)))
        names(x) <- c("ogimet", "wt")
        if ( nrow(x) == 0 ) stop("no data left after combining them")
        if ( jitter ) {
            plot(jitter(ogimet) ~ jitter(wt), data = x)
        } else {
            plot(ogimet ~ wt, data = x)
        }
        abline(0, 1, col = 2)
        invisible(x)
    }


# -------------------------------------------------------------------
# Observations from OGIMET
# -------------------------------------------------------------------
    get_observations <- function(param, station) {

        param <- match.arg(param, c("TTm", "TTn", "N", "Sd", "dd", "ff", "fx",
                                    "Wv", "Wn", "PPP", "TTd", "RR"))

        # ----------------------------
        # Define what to load from the sqlite3 tables (translate
        # wetterturnier parameter to sqlite3 columns)
        scale <- 10
        if      ( param == "TTm" ) { obshour <-   18;   obsparam <- "tmax12" }
        else if ( param == "TTn" ) { obshour <-    6;   obsparam <- "tmin12" }
        else if ( param == "TTd" ) { obshour <-   12;   obsparam <- "td" }
        else if ( param == "PPP" ) { obshour <-   12;   obsparam <- "pmsl" }
        else if ( param == "dd"  ) { obshour <-   12;   obsparam <- "dd"; scale <- 0.1 }
        else if ( param == "ff"  ) { obshour <-   12;   obsparam <- "ff"; scale <- 1. / 1.943844 }
        else if ( param == "N"   ) { obshour <-   12;   obsparam <- "N";  scale <- 1 }
        else if ( param == "RR"  ) { obshour <- NULL;   obsparam <- c("rr6", "rr12", "rr24") }
        else if ( param == "Sd"  ) { obshour <- NULL;   obsparam <- c("sun", "sunday"); scale <- 3600 }
        else if ( param == "fx"  ) { obshour <- NULL;   obsparam <- c("ffx", "ffinst"); scale <- 1. / 1.943844 }
        else if ( param == "Wv" | param == "Wn" ) { scale <- 1; obshour <- NULL; obsparam <- c("W1", "WW") }

        # ----------------------------
        library("RMySQL")
        con <- dbConnect(RSQLite::SQLite(), "obs_sqlite3/obs_11120.sqlite3")
        res <- dbSendQuery(con, sprintf("SELECT datumsec, %s FROM obs;", paste(obsparam, collapse = ",")))
        obs <- fetch(res, -1)
        dbClearResult(res)
        dbDisconnect(con)
        obs <- zoo(obs[,-1] / scale, as.POSIXct(obs[,1], origin = "1970-01-01"))
        if ( is.numeric(obshour) )
            obs <- subset(obs, as.POSIXlt(index(obs))$hour == obshour)

        print(head(obs))
        # ----------------------------
        if ( param == "fx" ) {

            timefun <- function(x)
                as.POSIXct(ceiling((as.numeric(x) - 6*3600) / 86400) * 86400 + 6*3600, origin = "1970-01-01")
            aggfun <- function(x) {
                if ( sum(!is.na(x)) == 0 ) return(NA)
                max(x, na.rm = TRUE)
            }
            warning("Am wind ist noch was faul, fx vor allem")
            obs <- aggregate(obs, timefun, aggfun) 
            return(obs$ffx)
            maxfun <- function(x) { if ( sum(!is.na(x)) == 0 ) NA else max(x, na.rm = TRUE) }
            obs <- zoo(apply(obs, 1, maxfun), index(obs))

        } else if ( param == "RR" ) {

            # Subsetting hours
            obs <- subset(obs, as.POSIXlt(index(obs))$hour %in% c(0, 6, 12, 18))

            # If we have no rr6: assume it was -3.0
            idx <- which(as.POSIXlt(index(obs))$hour %in% c(0, 6, 12, 18) & is.na(obs$rr6))
            if ( length(idx) > 0 ) obs$rr6[idx] <- -3.0

            # Drop all columns with no values at all
            idx <- which(apply(obs, 1, function(x) sum(!is.na(x)) > 0))
            if ( length(idx) == 0 ) {
                warning("No valid RR observation at all")
                return(NULL)
            }
            obs <- obs[idx,]

            # Deaccumulate rr12 to rr6
            tmp <- obs$rr6; index(tmp) <- index(tmp) + 6*3600
            tmp <- cbind(obs, tmp)
            tmp$tmp <- tmp$rr12 - tmp$tmp
            idx <- which(!is.na(tmp$tmp))
            if ( length(idx) > 0 ) {
                tmp$rr6[idx] <- tmp$tmp[idx]
                obs <- subset(tmp, select = -tmp)
            }

            # Aggregate rr6 to rr12 and check if they match
            timefun <- function(x) 
                as.POSIXct(ceiling((as.numeric(x) - 6*3600) / 43200) * 43200 + 6*3600, origin = "1970-01-01")
            aggfun  <- function(x) {
                if ( length(na.omit(x)) != 2 ) return(NA)
                print(x)
                if ( all(x <= -3.0) ) return(-3.0)
                sum(x[x>=0])
            }
            obs$rr12_calc <- aggregate(obs$rr6, timefun, aggfun)

        } else if ( param == "Wv" ) {

            # Conversion table
            wmo_ww <- read.table("wmo_ww.csv", header = TRUE, sep = ";")
            wmo_ww$result <- as.character(wmo_ww$result)
            wmo_ww$result <- ifelse(wmo_ww$result == "NA", NA, as.numeric(as.character(wmo_ww$result)))

            # Helper function
            convert_wmo_ww <- function(x, conv) {
                if ( length(x) == 0 ) return(NULL)
                res <- conv$result[match(x, conv$obs)]
                merge(x, res)
            }

            # ww_n is the "Nachwetter"
            ww_n <- subset(obs, ww %in% 20:29 & as.POSIXlt(index(obs))$hour %in% 7:12, select = ww)
            ww_n <- convert_wmo_ww(ww_n, subset(wmo_ww, type == "past"))

            # ww_c is the "current weather"
            ww_c <- subset(obs, ! ww %in% 20:29 & as.POSIXlt(index(obs))$hour %in% 6:12, select = ww)
            ww_c <- convert_wmo_ww(ww_c, subset(wmo_ww, type == "present"))

            # Weather
            w1   <- subset(obs, as.POSIXlt(index(obs))$hour %in% 7:12, select = w1)

            # Aggregating on a daily level
            aggfun <- function(x) {
                if ( sum(!is.na(x)) == 0 ) return(NA)
                return(max(x, na.rm = TRUE))
            }
            if ( length(ww_n) > 0 ) ww_n <- aggregate(ww_n$res, as.Date, aggfun)
            if ( length(ww_c) > 0 ) ww_c <- aggregate(ww_c$res, as.Date, aggfun)
            if ( length(w1) > 0 )   w1   <- aggregate(w1, as.Date, aggfun)

            res <- list()
            for ( rec in list(ww_n, ww_c, w1) ) {
                if ( inherits(rec, "zoo") ) res[[length(res)+1]] <- rec
            }
            res <- do.call(merge, res)
            res <- apply(res, 1, aggfun)

        } else if ( param == "N" ) {
            obs[obs == 9] <- NA
        }

        cat("-----------------------\n")
        cat("Observations loaded ...\n")
        print(head(obs))
        return(obs)

    }

    # Looks good ...
    #PPP <- get_observations("PPP", 11120)
    #WT_PPP <- get_wetterturnier_obs("PPP", 11120)
    #compare(PPP, WT_PPP)
    #TTm <- get_observations("TTm", 11120)
    #WT_TTm <- get_wetterturnier_obs("TTm", 11120)
    #compare(TTm, WT_TTm)
    #TTn <- get_observations("TTn", 11120)
    #WT_TTn <- get_wetterturnier_obs("TTn", 11120)
    #compare(TTn, WT_TTn)
    #TTd <- get_observations("TTd", 11120)
    #WT_TTd <- get_wetterturnier_obs("TTd", 11120)
    #compare(TTd, WT_TTd)
    #N <- get_observations("N", 11120)
    #WT_N <- get_wetterturnier_obs("N", 11120)
    #x <- compare(N, WT_N) #, jitter = TRUE)

    # -------------- !!!!!!!!!!!!!!!! ---------------
    # A lot of shit with 000/990
    #dd <- get_observations("dd", 11120)
    #WT_dd <- get_wetterturnier_obs("dd", 11120)
    #x <- compare(dd, WT_dd)

    # -------------- !!!!!!!!!!!!!!!! ---------------
    ## Some smaller troubles when ... dd == 000?
    #ff <- get_observations("ff", 11120)
    #WT_ff <- get_wetterturnier_obs("ff", 11120)
    #x <- compare(ff, WT_ff, jitter = TRUE)

    # -------------- !!!!!!!!!!!!!!!! ---------------
    #WT_fx <- get_wetterturnier_obs("fx", 11120)
    #index(WT_fx) <- as.POSIXct(index(WT_fx)) + 6 * 3600 - 8640
    #fx <- get_observations("fx", 11120)
    #WT_fx <- get_wetterturnier_obs("fx", 11120)
    #WT_fx <- lag(WT_fx, -1)
    #x <- compare(fx, WT_fx)

    Wv <- get_observations("Wv", 11120)
    WT_Wv <- get_wetterturnier_obs("Wv", 11120)
    x <- compare(Wv, WT_Wv) #, jitter = TRUE)


    stop()

    RR  <- get_observations("RR", 11120)

    Sd  <- get_observations("Sd", 11120)


