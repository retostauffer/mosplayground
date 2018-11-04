# -------------------------------------------------------------------
# - NAME:        interpolate.R
# - AUTHOR:      Reto Stauffer
# - DATE:        2018-10-03
# -------------------------------------------------------------------
# - DESCRIPTION: Small method to interpolate GFS based on NetCDF.
# -------------------------------------------------------------------
# - EDITORIAL:   2018-10-03, RS: Created file on thinkreto.
# -------------------------------------------------------------------
# - L@ST MODIFIED: 2018-11-04 19:07 on marvin
# -------------------------------------------------------------------

nc_variable_renaming <- function(name) {

    # Reading the conversion/renaming data set
    # Manual renaming of variables.
    data("GFS_renaming", package = "mospack")
    idx    <- which(GFS_renaming$shortName == name)
    name   <- ifelse(length(idx) != 1,   name, as.character(GFS_renaming$newName[idx]))

    # Else (or based on manually renamed variable), automatically
    # generate variable name.
    # (1) Extract variable name and level
    if ( grepl("_", name) ) {
        tmp_name  <- regmatches(name, regexpr("^[^_.]+", name))
        tmp_level <- regmatches(name, regexpr("[^_.]+$", name))
    } else { tmp_name <- name; tmp_level = "" }
    if ( length(tmp_level) == 0 ) tmp_level = ""
    tmp_level <- ifelse(grepl("^surface$", tmp_level), "", tmp_level)
    if ( grepl("^[0-9]+mabovemeansealevel$", tmp_level) )
        tmp_level <- sprintf("%smmsl", regmatches(tmp_level, regexpr("^[0-9]+", tmp_level)))

    # (2) Rename
    # UGRD to u
    # VGRD to v
    # VVEL to w
    # TMP to t
    tmp_name <- gsub("^VGRD$", "v", gsub("^UGRD", "u", tmp_name))
    tmp_name <- gsub("^VVEL$", "w", tmp_name)
    tmp_name <- gsub("^TMP$", "t", tmp_name)

    # (3) Manipulate level representation
    tmp_level <- sub("mb$", "", tmp_level)
    if ( grepl("maboveground", tmp_level) ) {
        tmp_level <- sprintf("%sm", regmatches(tmp_level, regexpr("^[0-9]+", tmp_level)))
    }

    # (4) Create new name
    newname <- trimws(sprintf("%s%s", tolower(tmp_name), tolower(tmp_level)))
    ##cat(sprintf(" ------ %-20s   :   %s  -  %s   %s\n", newname, name, tmp_name, tmp_level))

    # Return
    return(newname)
}

# Perform bilineare interpolation
# \item{file}{\code{character} string, name of the netCDF file to be processed.}
# \item{stations}{\code{SpatialPointsDataFrame} with station locations (or points)
#           which should be interpolated. Have to contain the coordinates named
#           as \code{lon} and \code{lat} and at least one data column
#           named \code{statnr} which will be used as the name of the station.
#           Have to be unique.}
# \item{ndays}{\code{NULL} or posivie integer. If an integer is provided only
#           the first \code{ndays} days will be processed.
#           Only for development purposes.}
nc_bilinear_on_file <- function(file, stations, ndays = NULL) {

    if ( ! inherits(stations, "SpatialPointsDataFrame") )
        stop("\"stations\" object has to be of type \"SpatialPointsDataFrame\"")
    if ( ! "statnr" %in% names(stations) )
        stop("\"stations\" object requires a column \"statnr\" (int or character)")
    if ( any(duplicated(as.character(stations$statnr))) )
        stop("\"statnr\" on object \"stations\" have to be unique!")
    if ( is.numeric(ndays) )
        if ( as.integer(ndays) == 0 ) stop("ndays canoot be 0!")

    # Helper function to find neighbor grid points.
    find_gp <- function(lons, lats, stations, direction) {
        # Allowed directions
        direction <- match.arg(direction, c("NW", "NE", "SW", "SE"))
        # Result
        res <- as.data.frame(matrix(NA, ncol = 4, nrow = nrow(stations),
                             dimnames = list(stations$statnr, c("j", "lon", "i", "lat"))))
        fun <- function(x, y, g) {
            if ( g == ">" ) {
                idx <- which(y > x)
                if ( length(idx) == 0 ) return(NA)
                idx[which.min(y[idx] - x)]
            } else {
                idx <- which(y <= x)
                if ( length(idx) == 0 ) return(NA)
                idx[which.max(y[idx] - x)]
            }
        }
        stn_lon <- coordinates(stations)[,"lon"]
        stn_lat <- coordinates(stations)[,"lat"]
        if ( direction == "NW" ) {
            res$i <- sapply(stn_lat, fun, y = lats, g = ">")
            res$j <- sapply(stn_lon, fun, y = lons, g = "<=")
        } else if ( direction == "NE" ) {
            res$i <- sapply(stn_lat, fun, y = lats, g = ">")
            res$j <- sapply(stn_lon, fun, y = lons, g = ">")
        } else if ( direction == "SW" ) {
            res$i <- sapply(stn_lat, fun, y = lats, g = "<=")
            res$j <- sapply(stn_lon, fun, y = lons, g = "<=")
        } else {
            res$i <- sapply(stn_lat, fun, y = lats, g = "<=")
            res$j <- sapply(stn_lon, fun, y = lons, g = ">")
        }
        res$lon <- lons[res$j]; res$lat <- lats[res$i]
        # Calculate distance in i (latitude) and j (longitude)
        res$di  <- abs(res$lat - coordinates(stations)[,"lat"])
        res$dj  <- abs(res$lon - coordinates(stations)[,"lon"])
        return(res)
    }

    # Open netCDF file
    require("ncdf4")
    nc <- nc_open(file)

    # Longitudes
    lons <- ncvar_get(nc, "longitude")
    if ( lons[1L] > lons[length(lons)] ) {
        warning("Correcting longitudes, not yet tested.")
        lons[lons >= lons[1L]] <- lons[lons >= lons[1L]] - 360.
    }
    # Latitudes
    lats <- ncvar_get(nc, "latitude")

    # Get neighbouring stations
    stations$NW <- find_gp(lons, lats, stations, "NW")
    stations$NE <- find_gp(lons, lats, stations, "NE")
    stations$SE <- find_gp(lons, lats, stations, "SE")
    stations$SW <- find_gp(lons, lats, stations, "SW")

    # Calculate the weights for the interpolation
    weights <- data.frame(N = 1 - stations$NW$di / (stations$NW$di + stations$SW$di),
                          S = 1 - stations$SW$di / (stations$NW$di + stations$SW$di),
                          W = 1 - stations$NW$dj / (stations$NW$dj + stations$NE$dj),
                          E = 1 - stations$NE$dj / (stations$NW$dj + stations$NE$dj))
    rownames(weights) <- stations$statnr
    if ( ! all(rowSums(weights) %in% c(2, NA)) )
        stop("Something wrong with interpolation (weights do not sum up to 2!)")
    weights <- weights

    # Helper function
    # Convert interpolated to data.frames
    data2zoo <- function(x, shortName, times) {
        if ( is.null(x) ) return(NULL)
        zoo( as.data.frame(matrix(x, ncol = 1, dimnames = list(NULL, shortName))), times)
    }
    data2df <- function(x, shortName, times) {
        if ( is.null(x) ) return(NULL)
        x <- data.frame(datetime = times, shortName = rep(shortName, length(x)), value = x)
        return(x)
    }

    # Loading times
    Sys.setenv("TZ" = "UTC")
    if ( grepl("^hours\\ssince\\s1900-01-01 00.*$", nc$dim$tim$units) ) {
        times <- as.POSIXct(ncvar_get(nc, "time") * 3600, origin = "1900-01-01 00:00")
    } else if ( grepl("^seconds\\ssince\\s1970-01-01 00.*$", nc$dim$tim$units) ) {
        times <- as.POSIXct(ncvar_get(nc, "time"), origin = "1970-01-01 00:00")
    } else {
        stop("the \"time\" dimension has unexpected units.")
    }
    # If input ndays is set: take first N
    if ( is.numeric(ndays) ) {
        ndays <- as.integer(ndays)
        if ( ndays < 0 ) {
            tstart    <- min(which(times >= as.POSIXct(as.Date(max(times)) + ndays + 1)))
            tend      <- length(times)
        } else {
            tstart    <- 1
            tend      <- max(which(times <= as.POSIXct(as.Date(min(times)) + ndays)))
        }
    } else { tstart <- 1; tend <- length(times) }
    times <- times[tstart:tend]

    # Helper function
    # Loading data from grid
    load_gp <- function(nc, shortName, gp) {
        # Getting data for grid point (i,j) (latitude,longitude)
        fun <- function(x, nc, shortName) {
            if ( any(is.na(x)) ) return(NULL)
            #                                 lon   lat  t 
            ncvar_get(nc, shortName, start = c(x$j, x$i, tstart), count = c(1, 1, length(times)))
        }
        # gp to list (for lapply)
        lst <- lapply(rownames(gp), function(x, gp) list(i = gp[x, "i"], j = gp[x, "j"]), gp = gp)
        names(lst) <- rownames(gp)
        lapply(lst, fun, nc = nc, shortName = shortName)
    }

    # Calculate bilinear interpolated value
    calc_ip <- function(x, w, NW, NE, SW, SE) {
        if ( any(is.na(w[x,])) ) return(NULL)
        A = NW[[x]] * w[x,"W"] + NE[[x]] * w[x,"E"]
        B = SW[[x]] * w[x,"W"] + SE[[x]] * w[x,"E"]
        A * w[x,"N"] + B * w[x,"S"]
    }

    # Interpolate netcdf file
    require("zoo")
    res <- list()
    for ( shortName in names(nc$var) ) {
        shortName <- as.character(shortName)
        dims <- sapply(nc$var[[shortName]]$dim, function(x) x$name)
        # Expecting dimensions c("longitude", "latitude", "time"). If order or
        # dimensions do not match: stop (would require a more general check here).
        if ( ! identical(c("longitude", "latitude", "time"), dims) )
            stop(sprintf("variable \"%s\" has wrong dimensions or dimension order!", shortName))
        # Loading data from netCDF file
        NW <- load_gp(nc, shortName, stations$NW)
        NE <- load_gp(nc, shortName, stations$NE)
        SW <- load_gp(nc, shortName, stations$SW)
        SE <- load_gp(nc, shortName, stations$SE)
        # Interpolate
        VV <- lapply(names(NW), calc_ip, w = weights, NW = NW, NE = NE, SW = SW, SE = SE)

        # Convert interpolated data  to data.rame
        newName <- nc_variable_renaming(shortName)
        res[[newName]]        <- lapply(VV, data2df, shortName = newName, times = times)
        names(res[[newName]]) <- stations$statnr
    }
    nc_close(nc)

    # Merge data.frames
    res <- lapply(stations$statnr, function(x, res) {
        ##x <- do.call(merge, lapply(res, function(res, stn) res[[stn]], stn = x))
        x <- do.call(rbind, lapply(res, function(res, stn) res[[stn]], stn = as.character(x)))
        rownames(x) <- NULL; return(x)
    }, res = res)
    names(res) <- stations$statnr

    # Return list of possibly multivariate zoo objects, each list element
    # contains the bilinearely interpolated values for one specific station.
    return(res)
}


nc_bilinear <- function(files, stations, ...) {

    # Interpolate all files to all required locations in 'stations'
    cat("Interpolate GFS netCDF files\n")
    fun <- function(file, stations) nc_bilinear_on_file(file, stations, ...)
    x <- lapply(files, fun, stations = stations)
    
    # Combine interpolated data.frames
    cat("Combine interpolated GFS data\n")
    x <- lapply(stations$statnr, function(stn, x) {
        do.call(rbind, lapply(x, function(x, stn) {
                tmp <- x[[stn]]; tmp$statnr <- as.character(stn); tmp}, stn = as.character(stn)))
    }, x = x)
    x <- do.call(rbind, x)

    # Create wide format
    cat("Rearrange (reshape) data\n")
    x <- reshape(x, timevar = "statnr", idvar = c("datetime", "shortName"), direction = "wide")
    names(x) <- gsub("^value\\.", "", names(x))

    names(x)[which(names(x) == "datetime")] <- "valid"

    # Return interpolated data data.frame (wide format)
    return(x)
}





