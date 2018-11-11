# -------------------------------------------------------------------
# - NAME:        GFS_test.R
# - AUTHOR:      Reto Stauffer
# - DATE:        2018-11-05
# -------------------------------------------------------------------
# - DESCRIPTION:
# -------------------------------------------------------------------
# - EDITORIAL:   2018-11-05, RS: Created file on thinkreto.
# -------------------------------------------------------------------
# - L@ST MODIFIED: 2018-11-09 20:53 on marvin
# -------------------------------------------------------------------

    rm(list = ls())
    library("mospack")

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

    # Looks good ...
    PPP <- get_observations("PPP", 11120)
    WT_PPP <- get_observations_wt("PPP", 11120)
    compare(PPP, WT_PPP)

    TTm <- get_observations("TTm", 11120)
    WT_TTm <- get_observations_wt("TTm", 11120)
    compare(TTm, WT_TTm)

    TTn <- get_observations("TTn", 11120)
    WT_TTn <- get_observations_wt("TTn", 11120)
    compare(TTn, WT_TTn)

    TTd <- get_observations("TTd", 11120)
    WT_TTd <- get_observations_wt("TTd", 11120)
    compare(TTd, WT_TTd)

    N <- get_observations("N", 11120)
    WT_N <- get_observations_wt("N", 11120)
    x <- compare(N, WT_N) #, jitter = TRUE)

    # -------------- !!!!!!!!!!!!!!!! ---------------
    # A lot of shit with 000/990
    dd <- get_observations("dd", 11120)
    WT_dd <- get_observations_wt("dd", 11120)
    x <- compare(dd, WT_dd)

    # -------------- !!!!!!!!!!!!!!!! ---------------
    # Some smaller troubles when ... dd == 000?
    ff <- get_observations("ff", 11120)
    WT_ff <- get_observations_wt("ff", 11120)
    WT_dd <- get_observations_wt("dd", 11120)
    x <- compare(ff, WT_ff, jitter = TRUE)
    abline(v = mps2knots(seq(1, 30)), lty = 3, col = "gray60")
    abline(h = mps2knots(seq(1, 30)), lty = 3, col = "gray60")
    x <- merge(x, WT_dd)
    x <- subset(x, round(ogimet) != wt)
    print(x)

    # -------------- !!!!!!!!!!!!!!!! ---------------
    WT_fx <- get_observations_wt("fx", 11120)
    index(WT_fx) <- as.POSIXct(index(WT_fx)) + 6 * 3600 - 86400
    fx <- get_observations("fx", 11120)
    WT_fx <- get_observations_wt("fx", 11120)
    index(WT_fx) <- index(WT_fx) + 1
    x <- compare(fx, WT_fx, jitter = TRUE)
    abline(h = 25, v = 25, col = 4)

    Wv <- get_observations("Wv", 11120)
    WT_Wv <- get_observations_wt("Wv", 11120)
    x <- compare(Wv, WT_Wv, jitter = TRUE)
    x <- subset(x, ! ogimet == wt)
    print(x)

    Wn <- get_observations("Wn", 11120)
    WT_Wn <- get_observations_wt("Wn", 11120)
    x <- compare(Wn, WT_Wn, jitter = TRUE)
    x <- subset(x, ! ogimet == wt)
    print(x)


