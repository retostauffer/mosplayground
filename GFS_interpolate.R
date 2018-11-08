# -------------------------------------------------------------------
# - NAME:        GFS_interpolate.R
# - AUTHOR:      Reto Stauffer
# - DATE:        2018-11-04
# -------------------------------------------------------------------
# - DESCRIPTION: Das Chaos in dem Script ist gewollt .. bisher.
# -------------------------------------------------------------------
# - EDITORIAL:   2018-11-04, RS: Created file on thinkreto.
# -------------------------------------------------------------------
# - L@ST MODIFIED: 2018-11-06 17:13 on marvin
# -------------------------------------------------------------------

    rm(list=ls())


# ---------------------------------------------------------------------
# Loading the required libraries.
# ---------------------------------------------------------------------
    #library("devtools"); load_all("mospack")
    library("mospack")
    library("parallel")
    library("zoo")


# ---------------------------------------------------------------------
# Station setup.
# ---------------------------------------------------------------------
    library("sp")
    stations <- SpatialPointsDataFrame(data.frame(
                   lon = c(13.394, 11.365, 8.563, 12.195, 16.425),
                   lat = c(52.514 , 47.257 , 47.418 , 51.447 , 48.193)
                   ), data = data.frame(statnr = c("BER", "IBK", "ZUR", "LEI", "VIE")))
    stations <- neighbours(stations)
    
    ##print(stations)
    ##plot(stations, col = stations$col)
    ##text(coordinates(stations)[,1], coordinates(stations)[,2], 
    ##     as.character(stations$statnr), col = stations$col)
    ##library("maps")
    ##map(add = TRUE)


# ---------------------------------------------------------------------
# Looking for NetCDF files on disc having the expected file names.
# These files contain the deterministic GFS forecasts.
# ---------------------------------------------------------------------
    ncfiles <- list.files("netcdf")
    ncfiles <- sort(sprintf("netcdf/%s", ncfiles[grep("^GFS_[0-9]{8}_[0-9]{2}00_combined.nc$", ncfiles)]))
    
    # Make named list, nicer for mclapply
    init_from_filename <- function(x)
        as.POSIXct(strptime(regmatches(ncfiles, regexpr("[0-9]{8}_[0-9]{4}", ncfiles)), "%Y%m%d_%H%M"))
    ncfiles <- setNames(ncfiles, strftime(init_from_filename(ncfiles)))

    cat(sprintf("In total %d NetCDF files to be considered\n", length(ncfiles)))


# ---------------------------------------------------------------------
# Interpolation function, this thing does the job!
# ---------------------------------------------------------------------
    ipfun <- function(file, stations, rdsdir = "rds", station = NULL, stoponerror = FALSE) {

        # If input "station" is not NULL: only interpolate
        # this one specific station (and their neighbours).
        if ( ! dir.exists(rdsdir) ) dir.create(rdsdir)


        # rds flie suffix
        suffix <- ifelse(is.null(station), ".rds", sprintf("_%s.rds", station))
        rdsfile <- sprintf("%s/%s", rdsdir, sub("_combined\\.nc$", suffix, basename(file)))
        if ( file.exists(rdsfile) ) return(readRDS(rdsfile))

        # Subsetting 'stations' if 'station' is set
        if ( ! is.null(station) )
            stations <- stations[grep(sprintf("%s$", station), stations$statnr),]
        if ( nrow(stations) == 0 ) stop("No stations left!")
    
        # Initial time
        init <- as.POSIXct(strptime(regmatches(file, regexpr("[0-9]{8}_[0-9]{4}", file)), "%Y%m%d_%H%M"))
    
        # Else interpolate and save
        x <- nc_bilinear_on_file(file, stations)
    
        # Conver to zoo
        library("zoo")
        for ( i in seq_along(x) ) {
            nname  <- regmatches(names(x[i]), regexpr("^[A-Za-z]+", names(x[i])))
            tmp    <- reshape(x[[i]], timevar = "shortName", idvar = "datetime", direction = "wide")
            x[[i]] <- zoo(tmp[,-1], tmp[,1])
            names(x[[i]]) <- sprintf("%s.%s", nname, gsub("^value.", "", names(x[[i]])))
        }
    
        # Combine neighbours
        unique_stations <- function(x) {
            x <- as.character(x$statnr)
            return(unique(regmatches(x, regexpr("[^\\..]+$", x))))
        }
        unique_stations <- unique_stations(stations)
        x <- lapply(unique_stations, function(stn, x) {
                do.call(merge, x[grep(sprintf("%s$", stn), names(x))]) }, x = x)
        x <- setNames(x, as.character(unique_stations))
    
        # Compute derived variables
        cat("\n -> Calling derived covariates\n")
        x <- lapply(x, mospack::derivedCovariates, stoponerror = stoponerror)

        # Compute spatial covariates (first time), force stoponerror to FALSE.
        # we need to call this method twice as some rely on temporal differences,
        # while some temporal differences depend on spatial covariates.
        cat("\n -> Calling spatialCovariates 1th time\n")
        x <- lapply(x, mospack::spatialCovariates, stoponerror = FALSE)
    
        # Compute temporal differences
        cat("\n -> Calling temporalCovariates\n")
        x <- lapply(x, mospack::temporalCovariates, stoponerror = stoponerror)

        # Compute spatial covariates
        cat("\n -> Calling spatialCovariates 2nd time\n")
        x <- lapply(x, mospack::spatialCovariates, stoponerror = stoponerror)
    
        # Append forecast step
        add_step <- function(x, init)
            merge(zoo(data.frame(step = as.numeric(index(x) - init, unit = "hours")), index(x)), x)
        x <- lapply(x, add_step, init = init)
        
        # Save and return
        cat(sprintf("- Save %s\n", rdsfile))
        saveRDS(x, file = rdsfile)
        return(x)
    }

# ---------------------------------------------------------------------
# Interpolate data now
# ---------------------------------------------------------------------
    # Testing
    #testfile <- "netcdf/GFS_20181106_0000_combined.nc"
    #message(sprintf("Reading %s\n\n", testfile))
    #x <- ipfun(testfile, stations = stations, station = "IBK", stoponerror = TRUE)
    #stop('-dev-')

    # Interpolate on three cores ...
    x <- mclapply(ncfiles, FUN = ipfun, stations = stations,
                  station = "IBK", mc.cores = 3)
    
    
    combine_zoo <- function(stn, x, step) {
        data <- list()
        for ( rec in x ) {
            stp <- step
            rec <- subset(rec[[stn]], step == stp)
            if ( nrow(rec) == 0 ) next
            data[[length(data)+1]] <- rec
        }
        print(table(sapply(data, ncol)))
        data <- do.call(rbind, data)
        # Delete empty cols
        idx <- which(colSums(!is.na(data)) == 0)
        if ( length(idx) > 0 ) data <- data[,-idx]
        return(data)
    }
    data18 <- lapply(setNames(names(x[[1]]), names(x[[1]])), combine_zoo, x = x, step = 18)
    u <- data18



















