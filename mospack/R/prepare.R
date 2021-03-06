# -------------------------------------------------------------------
# - NAME:        prepare.R
# - AUTHOR:      Reto Stauffer
# - DATE:        2018-02-24
# -------------------------------------------------------------------
# - DESCRIPTION:
# -------------------------------------------------------------------
# - EDITORIAL:   2018-02-24, RS: Created file on thinkreto.
# -------------------------------------------------------------------
# - L@ST MODIFIED: 2018-11-11 20:30 on marvin
# -------------------------------------------------------------------

### Function to get a vector of accumulated variables
##accumulated <- function( model ) {
##
##    # Loading the data set
##    data( "accumulatedVariables", package = "mospack" )
##    # Take subset
##    x <- accumulatedVariables[ grep(sprintf("^%s$",model),
##                   accumulatedVariables$model, ignore.case = TRUE ), ]
##    # If no accumulted variables defined: return NULL
##    if ( nrow(x) == 0 ) return( NULL )
##    # Else return a character vector of the shortNames specified
##    # in the data set.
##    gsub(" ","",as.character( x$shortName ))
##
##}


# Compute derived variables
derivedCovariates <- function(x, stoponerror = FALSE) {

    stations <- unique(gsub("\\.","",regmatches(names(x),regexpr("[a-zA-Z]+\\.",names(x)))))
    data("derived_covariates", package = "mospack")
    dcov <- derived_covariates
    for ( stn in stations ) {
        for ( i in 1:nrow(dcov) ) {
            if ( nchar(trimws(dcov$equation[i])) == 0 ) next
            cmd <- gsub( "<s>", sprintf("x$%s",stn), dcov$equation[i] )
            check <- try(eval(parse(text = cmd)), silent = TRUE)
            if ( inherits(check, "try-error") ) {
                cat(sprintf("[!DERIV] %s\n", cmd))
                if ( stoponerror ) {
                    message(sprintf("Problems computing the equation\n%s", cmd))
                    browser()
                }
            }
        }
    }

    return( x )

}

# Compute spatial covariates
spatialCovariates <- function(x, stoponerror = TRUE) {

    data("spatial_covariates", package = "mospack" )
    scov <- spatial_covariates
    for ( eqn in as.character(scov$equation) ) {
        if ( nchar(trimws(eqn)) == 0 ) next
        eqn <- gsub("\\[q\\]","\"",eqn)

        # Check if variable exists already
        tmp <- regmatches(eqn, regexpr("\\$[\\S]+", eqn, perl = TRUE))
        if ( length(tmp) == 0 ) stop("Problems with regular expression")
        if ( substr(tmp, 2, nchar(tmp)) %in% names(x) ) next
        
        # Extracting the parameter and check if already existing.
        check <- try(eval(parse(text = eqn)), silent = TRUE)
        if ( inherits(check, "try-error") ) {
            cat(sprintf("[!SPAT] %s\n", eqn))
            if ( stoponerror ) {
                message(sprintf("Problems computing the equation\n%s", eqn))
                browser()
            }
        }
        # If all NA
        if ( sum(!is.na(x[,ncol(x)])) == 0 ) {
            cat(sprintf("Drop column %s again, all NA\n", tail(names(x),1)))
            x <- x[,-ncol(x)]
        }
    }

    return( x )
}


# Compute temporal differences
temporalCovariates <- function(x, stoponerror = FALSE) {

    if ( ! inherits(x, "zoo") ) stop("input has to be of class zoo")

    data("temporal_covariates", package = "mospack")
    tcov <- temporal_covariates
    tcov$varname <- trimws(as.character(tcov$varname))
    tcov$step1   <- as.integer(tcov$step1)
    tcov$step2   <- as.integer(tcov$step2)

    # Checking stations
    stations <- unique(gsub("\\.","",regmatches(names(x),regexpr("[a-zA-Z]+\\.",names(x)))))
    for ( i in 1:nrow(tcov) ) {

        # Extract step1/step2 (definition) for convenience
        step1 <- tcov$step1[i]
        step2 <- tcov$step2[i]

        for ( stn in stations ) {

            # Variable name
            varname <- gsub("^<s>", stn, tcov$varname[i])

            # Getting column. If not found, skip
            cidx <- which(names(x) == varname)
            if ( length(cidx) == 0 ) {
                if ( stoponerror ) {
                    message(sprintf("Problems computing temporal covariate: missing %s\n", varname))
                    browser()
                }
                next
            }

            # Looking for indizes matching the steps we need to
            # compute the differences.
            idx <- cbind(match(index(x) + step2 * 3600, index(x)),
                         match(index(x) + step1 * 3600, index(x))) 
            # No matchings (due to misspecification) skip
            if ( all(is.na(idx)) ) next

            # Else compute spatial differences
            newname <- sprintf("%s_%s%dh%s%dh", varname,
                        ifelse( sign(step2) < 0, "m", "p" ), abs(step2),
                        ifelse( sign(step1) < 0, "m", "p" ), abs(step1) )

            # As we have a zoo we have to take care of the indizes
            eval(parse(text=sprintf("x$%s <- NA", newname)))
            naidx  <- which(rowSums(is.na(idx)) == 0)
            idx    <- na.omit(idx)
            tmp    <- as.numeric(x[idx[,1], cidx]) - as.numeric(x[idx[,2], cidx])
            eval(parse(text=paste(sprintf("x$%s[naidx] <- tmp", newname))))

        }

    }

    return( x )
}



#### Prepare DMO (interpolated data)
###prepareGFS <- function(station, neighbours = NULL,
###                        deaccumulate = NULL,
###                        dir = "netcdf", limit = NULL,
###                        dropneighbours = TRUE,
###                        pattern = "^GFS_[0-9]{8}_[0-9]{2}00_combined.nc$", mc.cores = 1,
###                        stoponerror = FALSE) {
###
###    # 'station' is the name of the center grid point, neighbours
###    # the ones of the surrounding grid points. If not set the same
###    # name as for the center station is assumed.
###    if ( is.null(neighbours) ) neighbours <- station
###
###    # Searching for files
###    files <- list.files(dir)
###    files <- sort( sprintf("%s/%s",dir,files[grep(pattern,files)]) )
###
###    # Use the first N files only, mainly for development.
###    if ( is.numeric(limit) ) {
###        limit <- as.integer( limit )
###        if ( limit <= 0 ) stop("Sorry, limit has to be a positive integer")
###        files <- files[1:limit]
###    }
###
###    # Helper function to only pick the colums needed
###    dropcolumns <- function( x, station, neighbours, forced = c("init","valid","step","shortName") ) {
###        regex <- sprintf("^(%s)$",paste(c(forced,station,sprintf("%s_.*",neighbours)),collapse="|"))
###        x <- x[,grep(regex,names(x))]
###        names(x)[grep(sprintf("^%s$",station),names(x))] <- "C"
###        tmp <- grep(sprintf("^%s_.*$",neighbours),names(x))
###        names(x)[tmp] <- gsub(sprintf("%s_",neighbours),"",names(x)[tmp])
###        x
###    }
###
###    # Reading data
###    requireNamespace( "parallel" )
###    requireNamespace( "data.table" )
###
###    myrbind <- function( x ) {
###        x <- as.data.frame(data.table::rbindlist( x, use.names=TRUE ))
###        rownames( x ) <- NULL
###        return( x )
###    }
###
###    # Parallel worker
###    parfun <- function(file, station, neighbours) {
###
###        # If file size is 0 (file empty): skip
###        if ( file.size(file) == 0 ) return( NULL )
###
###        # Load file
###        tmp <- nc_bilinear_on_file(file, station)
###
###        # Combine sfc/pl data and drop unused columns
###        tmp <- dropcolumns(tmp, station, neighbours)
###
###        # Bring the long format into a wide format (reshape data set)
###        tmp <- reshape(tmp, direction = "wide",
###                            timevar = "shortName", drop = "member",
###                            idvar = c("valid"))
###
###        return( tmp )
###    }
###
###    raw <- nc_bilinear(files, station)
###    browser()
###
###    # Perform parallel reading
###    raw <- parallel::mclapply(files, parfun, station=station,
###                              neighbours=neighbours, mc.cores=mc.cores )
###
###    raw <- myrbind(raw)
###
###    cat("Calculate aggregated variables\n")
###    require("zoo")
###
###    # Aggregate some variables (precipitation, fluxes, ...)
###    cols <- names(raw)[grep("^[A-Z]+\\.(lsp|cp|tp)$", names(raw))]
###    for ( c in cols ) {
###        tmp <- zoo(raw[,c], raw$valid)
###        if ( ! is.regular(tmp, strict = TRUE) )
###            stop("Time series aggregation requires strictly regular zoo objects!")
###        for ( agg in c(2, 6, 12) ) {
###            cat(sprintf("- Sum of %s over %d hours (centered)\r", c, agg))
###            cmd <- sprintf(paste("raw$%1$s%2$dh <- pmax(0, rollapply(tmp, sum,",
###                                 "width = list(seq(%3$d, %4$d)),",
###                                 "coredata = TRUE, fill = NA))"),
###                           c, agg, -(agg/2-1), agg/2)
###            eval(parse(text = cmd))
###        }
###    }; cat("\n")
###
###    # Aggregate some variables (precipitation, fluxes, ...)
###    cols <- names(raw)[grep("^[A-Z]+\\.([thml]cc)$", names(raw))]
###    for ( c in cols ) {
###        tmp <- zoo(raw[,c], raw$valid)
###        if ( ! is.regular(tmp, strict = TRUE) )
###            stop("Time series aggregation requires strictly regular zoo objects!")
###        cmd <- sprintf(paste("raw$%1$s_p3hm3h <- rollapply(tmp, mean,",
###                             "width = list(seq(-3,3)), coredata = TRUE, fill = NA)"), c)
###        eval(parse(text = cmd))
###        cmd <- sprintf(paste("raw$%1$s_p3hp0h <- rollapply(tmp, mean,",
###                             "width = list(seq(0,3)), coredata = TRUE, fill = NA)"), c)
###        eval(parse(text = cmd))
###        cmd <- sprintf(paste("raw$%1$s_p0hm3h <- rollapply(tmp, mean,",
###                             "width = list(seq(-3,0)), coredata = TRUE, fill = NA)"), c)
###        eval(parse(text = cmd))
###    }; cat("\n")
###
###    # If derived variables are requested: compute derived variables
###    raw <- derivedCovariates(raw, stoponerror)
###
###    # If requested: compute temporal differences
###    cols <- names(raw)[grep("^[A-Z]+\\.(t[0-9]+|lt[0-9]+|msl|theta[0-9]+|theta[0-9]+_[0-9]+)$",names(raw))]
###    fun <- function(x) x[length(x)] - x[1L] # Aggregation function (difference)
###    for ( c in cols ) {
###        tmp <- zoo(raw[,c], raw$valid)
###        if ( ! is.regular(tmp, strict = TRUE) )
###            stop("Time series aggregation requires strictly regular zoo objects!")
###        for ( agg in c(3) ) {
###            cat(sprintf("- Temporal change of %s over -%d to +%d hours\r", c, agg, agg))
###            cmd <- sprintf(paste("raw$%1$s_p%2$dhm%2$dh <- rollapply(tmp, fun, width = %3$d,",
###                                 "align = \"center\", coredata = TRUE, fill = NA)"),
###                                 c, agg, 1 + 2*agg)
###            eval(parse(text = cmd))
###        }
###        for ( agg in c(3) ) {
###            cat(sprintf("- Temporal change of %s over last %d hours\r", c, agg))
###            cmd <- sprintf(paste("raw$%1$s_p0hm%2$dh <- rollapply(tmp, fun, width = %2$d + 1,",
###                                 "align = \"right\", coredata = TRUE, fill = NA)"), c, agg)
###            eval(parse(text = cmd))
###            cmd <- sprintf(paste("raw$%1$s_p%2$dhp0h <- rollapply(tmp, fun, width = %2$d + 1,",
###                                 "align = \"left\", coredata = TRUE, fill = NA)"), c, agg)
###            eval(parse(text = cmd))
###        }
###    }; cat("\n")
###
###    # Spatial covariates
###    raw <- spatialCovariates(raw, stoponerror = stoponerror)
###
###    # If drop neighbours: drop them!
###    if ( dropneighbours ) {
###        idx <- grep("^(N|S|E|W|SE|SW|NE|NW|SS|NN)\\.",names(raw))
###        if ( length(idx) > 0 ) raw <- raw[,-idx]
###    }
###
###    # Adding some attributes
###    attr( raw, "created" )       <- Sys.time()
###    attr( raw, "createdon" )     <- as.character(Sys.info()["nodename"])
###    attr( raw, "station" )       <- station
###    attr( raw, "neighbours" )    <- neighbours
###
###    # Return this data.frame
###    return( raw )
###
###}


