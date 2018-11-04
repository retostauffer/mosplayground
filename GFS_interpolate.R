
rm(list=ls())

file <- "netcdf/GFS_20170502_0000_combined.nc"
library("devtools")
load_all("mospack")


# --------------------------------------------------------------
# --------------------------------------------------------------
library("sp")
stations <- SpatialPointsDataFrame(data.frame(lon = c(8.4,11.8), lat = c(46.4,47.5)),
                                   data = data.frame(statnr = c(1234,11120)))
stations <- neighbours(stations)
#print(stations)
#plot(stations, col = stations$col)
#text(coordinates(stations)[,1], coordinates(stations)[,2], 
#     as.character(stations$statnr), col = stations$col)

init_from_filename <- function(x)
    as.POSIXct(strptime(regmatches(ncfiles, regexpr("[0-9]{8}_[0-9]{4}", ncfiles)), "%Y%m%d_%H%M"))


# --------------------------------------------------------------
# --------------------------------------------------------------
ncfiles <- list.files("netcdf")
ncfiles <- sort(sprintf("netcdf/%s", ncfiles[grep("^GFS_[0-9]{8}_[0-9]{2}00_combined.nc$", ncfiles)]))
# Make named list, nicer for mclapply
ncfiles <- setNames(ncfiles, strftime(init_from_filename(ncfiles)))

ipfun <- function(file, stations, rdsdir = "rds") {
    if ( ! dir.exists(rdsdir) ) dir.create(rdsdir)
    rdsfile <- sprintf("%s/%s", rdsdir, sub("nc$", "rds", basename(file)))
    if ( file.exists(rdsfile) ) return(readRDS(rdsfile))

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
        return(unique(as.integer(regmatches(x, regexpr("[0-9]+$", x)))))
    }
    unique_stations <- unique_stations(stations)
    x <- lapply(unique_stations, function(stn, x) do.call(merge, x[grep(sprintf("%d$", stn), names(x))] ), x = x)
    x <- setNames(x, as.character(unique_stations))

    # Compute derived variables
    x <- lapply(x, mospack::computeDerivedVars)

    # Compute temporal differences
    x <- lapply(x, computeTemporalDifferences)

    # Append forecast step
    add_step <- function(x, init)
        merge(zoo(data.frame(step = as.numeric(index(x) - init, unit = "hours")), index(x)), x)
    x <- lapply(x, add_step, init = init)
    
    # Save and return
    saveRDS(x, file = rdsfile)
    return(x)
}

library("parallel")
library("zoo")
warning("Taking only first 3 netcdf files here")
x <- mclapply(ncfiles[1:3], FUN = ipfun, stations = stations, mc.cores = 3)


combine_zoo <- function(stn, x, step) {
    x <- do.call(rbind, lapply(x, function(x, stn, stp) subset(x[[stn]], step == stp), stn = stn, stp = step))
    # Delete empty cols
    idx <- which(colSums(!is.na(x)) == 0)
    if ( length(idx) > 0 ) x <- x[,-idx]
    return(x)
}
data18 <- lapply(setNames(names(x[[1]]), names(x[[1]])), combine_zoo, x = x, step = 18)



















