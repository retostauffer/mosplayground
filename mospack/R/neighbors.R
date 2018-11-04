# -------------------------------------------------------------------
# - NAME:        neighbours.R
# - AUTHOR:      Reto Stauffer
# - DATE:        2018-10-03
# -------------------------------------------------------------------
# - DESCRIPTION: Adapted simpler version from foehnpack routine.
# -------------------------------------------------------------------
# - EDITORIAL:   2018-02-23, RS: Created file on thinkreto.
# -------------------------------------------------------------------
# - L@ST MODIFIED: 2018-02-25 21:58 on marvin
# -------------------------------------------------------------------


neighbours <- function(stations) {
    data("neighbourmask", package = "mospack")
    C <- coordinates(stations)
    res <- list()
    for ( i in 1:nrow(stations) ) {
        tmp <- subset(neighbourmask, select = c(lon,lat)) + rep(as.numeric(C[i,]), each = nrow(neighbourmask))
        stn <- sprintf("%s.%s", neighbourmask$name, stations$statnr[i])
        res[[i]] <- SpatialPointsDataFrame(tmp, data = data.frame(statnr = stn, col = i))
    }
    return(do.call(rbind, res))
}
