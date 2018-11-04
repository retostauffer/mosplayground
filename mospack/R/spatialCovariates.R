# -------------------------------------------------------------------
# - NAME:        spatialCovariates.R
# - AUTHOR:      Reto Stauffer
# - DATE:        2018-02-24
# -------------------------------------------------------------------
# - DESCRIPTION: Append spatial covariates based on the interpolated
#                DMO data set and its neighbour grid points.
# -------------------------------------------------------------------
# - EDITORIAL:   2018-02-24, RS: Created file on thinkreto.
# -------------------------------------------------------------------
# - L@ST MODIFIED: 2018-10-04 10:14 on marvin
# -------------------------------------------------------------------



spatialCovariates <- function(x, ERA5 = FALSE) {

    if ( ! ERA5 ) {
        data( "spatialcov", package = "foehnpack" )
    } else {
        data( "ERA5_spatialcov", package = "foehnpack" )
        spatialcov <- ERA5_spatialcov
    }
    for ( eqn in as.character(spatialcov$equation) ) {
        eqn <- gsub("\\[q\\]","\"",eqn)
        check <- try(eval(parse(text = eqn)), silent = TRUE)
        if ( inherits(check, "try-error") )
            cat(sprintf("[!SPAT] %s\n", eqn))
    }

    return( x )
}

