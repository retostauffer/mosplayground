
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



# --------------------------------------------------------------
# --------------------------------------------------------------
ncfiles <- list.files("netcdf")
ncfiles <- sprintf("netcdf/%s", ncfiles[grep("^GFS_[0-9]{8}_[0-9]{2}00_combined.nc$", ncfiles)])
# Make named list, nicer for mclapply
ncfiles <- setNames(ncfiles, regmatches(ncfiles, regexpr("[0-9]{8}_[0-9]{4}", ncfiles)))

ipfun <- function(file, stations, rdsdir = "rds") {
    if ( ! dir.exists(rdsdir) ) dir.create(rdsdir)
    rdsfile <- sprintf("%s/%s", rdsdir, sub("nc$", "rds", basename(file)))
    if ( file.exists(rdsfile) ) return(readRDS(rdsfile))

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
    saveRDS(x, file = rdsfile)
    return(x)
}

library("parallel")
library("zoo")
x <- mclapply(ncfiles, FUN = ipfun, stations = stations, mc.cores = 3)

testfun <- function(x, param, stn = "C.11120") {
    x <- x[[stn]]
    if ( ! param %in% names(x) ) stop("cannot find ", param)
    x[,param]
}
testplot <- function(x, params) {
    par(mfrow = c(length(params), 1), mar = rep(0, 4), oma = c(1,5,1,1))
    for ( param in params ) {
        cat(sprintf(" ---- %s\n", param))
        test <- lapply(x, testfun, param = param)
        xlim <- range(sapply(test, function(x) range(index(x))))
        ylim <- range(sapply(test, function(x) range(x)), na.rm = TRUE)

        plot(NA, xlim = xlim, ylim = ylim, xaxt = "n",
             xlab = NA, ylab = NA)
        mtext(side = 2, line = 2, param)
        library("colorspace")
        cols <- rainbow_hcl(length(test))
        for ( i in seq_along(test) ) lines(test[[i]], col = cols[i])
    }
}
#testplot(x, sample(names(x[[1]][[1]]), 5))




# --------------------------------------------------------------
# --------------------------------------------------------------
data <- list()
unique_stations <- function(x) {
    x <- as.character(x$statnr)
    return(unique(as.integer(regmatches(x, regexpr("[0-9]+$", x)))))
}
unique_stations <- unique_stations(stations)
for ( stn in unique_stations ) {
    tmp <- lapply(x, function(x, stn) do.call(merge, x[grep(sprintf("%d$", stn), names(x))] ), stn = stn)
}


load_all("mospack")
d <- mospack::computeDerivedVars(tmp[[1]]) #x[[1]])

load_all("mospack")
d2 <- computeTemporalDifferences(d)
d2 <- d2[,grep("^C\\.", names(d2))]
print(head(names(d2),100))


##par(ask = TRUE)
##n <- 21
##for ( i in seq(1, ncol(d), by = n + 1) ) {
##    idx <- seq(i, min(ncol(d), i+n))
##    plot(d[,idx], ncol = 1)
##}
#idx <- grep("C.ffshear", names(d))
#plot(d[,idx], screen = 1)




















