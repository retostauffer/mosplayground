# -------------------------------------------------------------------
# - NAME:        Read_Obs.R
# - AUTHOR:      Reto Stauffer
# - DATE:        2018-11-03
# -------------------------------------------------------------------
# - DESCRIPTION:
# -------------------------------------------------------------------
# - EDITORIAL:   2018-11-03, RS: Created file on thinkreto.
# -------------------------------------------------------------------
# - L@ST MODIFIED: 2018-11-04 17:32 on marvin
# -------------------------------------------------------------------


    #station <- 10384
    #station <- 10385
    #station <- 10469
    #station <- 10471
    station <- 11120

    dbfile  <- sprintf("obs_sqlite3/obs_%d.sqlite3", station)
    stopifnot(file.exists(dbfile))

    library("RSQLite")

    con <- RSQLite::dbConnect(SQLite(), dbfile)

    res <- dbSendQuery(con, "SELECT * FROM obs;")
    data <- fetch(res,  -1)

    library("zoo")

    data <- zoo(subset(data, select = -c(datumsec)), as.POSIXct(data$datumsec, origin = "1970-01-01"))
    #plot(x, type = "p", pch = ".")

    get_wt <- function(station) {
        library("RMySQL")
        mysql <- RMySQL::dbConnect(MySQL(), host = "localhost", user = "root", password = "suchti", dbname ="obs")
        res <- dbSendQuery(mysql, sprintf("SELECT * FROM archive WHERE statnr = %d", station))
        data <- fetch(res,  -1)
        RMySQL::dbClearResult(res)
        RMySQL::dbDisconnect(mysql)
        print(head(data))
        drop <- c("statnr", "datum", "datumsec", "stdmin", "msgtyp", "stint", "utime", "ucount")
        data <- zoo(data[,which(! names(data) %in% drop)], as.POSIXct(data$datumsec, origin = "1970-01-01"))
        return(data)
    }

    mysql <- get_wt(station)
    mysql$ww <- ifelse(mysql$ww > 120, NA, mysql$ww)

    test <- function(data, mysql, col) {
        tmp <- merge(data[,col], mysql[,col])
        tmp <- na.omit(tmp)
        if ( nrow(tmp) == 0 ) return();
        names(tmp) <- c("ogimet", "mysql")
        plot(tmp$ogimet, tmp$mysql, main = col)
    }

    par(mfrow=c(2,2))
    test(data, mysql, "t")
    test(data, mysql, "tmax12")
    test(data, mysql, "dd")
    test(data, mysql, "w1")

    dbDisconnect(con)













