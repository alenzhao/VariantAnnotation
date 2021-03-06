### =========================================================================
### PolyPhenDb methods 
### =========================================================================

setMethod("keys", "PolyPhenDb",
    function(x)
    {
        sql <- paste("SELECT RSID FROM ppdata ", sep="") 
        unique(dbGetQuery(x$conn, sql))[,1] 
    }
) 

setMethod("columns", "PolyPhenDb",
    function(x)
    {
        dbListFields(conn=x$conn, "ppdata")
    }
) 

setMethod("select", "PolyPhenDb",
    function(x, keys, columns, keytype, ...)
    {
        sql <- .createPPDbQuery(x, keys, columns)
        if (length(sql)) { 
            raw <- dbGetQuery(x$conn, sql)
            .formatPPDbSelect(raw, keys) 
        } else {
            data.frame()
        }
    }
)

.createPPDbQuery <- function(x, keys, cols)
{
    if (missing(keys) && missing(cols)) {
        sql <- "SELECT * FROM ppdata"
    }
    if (!missing(keys)) {
        if(.missingKeys(x, keys, "PolyPhen"))
            return(character()) 
        if (!missing(cols)) {
            if (.missingCols(x, cols, "PolyPhen"))
                return(character()) 
            if (!"RSID" %in% cols)
                cols <- c("RSID", cols)
            fmtcols <- paste(cols, collapse=",")
            fmtkeys <- .sqlIn(keys)
            sql <- paste("SELECT ", fmtcols, " FROM ppdata WHERE RSID 
                IN (", fmtkeys, ")", sep="")
        } else {
            fmtkeys <- .sqlIn(keys)
            sql <- paste("SELECT * FROM ppdata WHERE RSID IN (",
                fmtkeys, ")", sep="")
        }
    } else {
        if (.missingCols(x, cols, "PolyPhen"))
            return(character())
        if (!"RSID" %in% cols)
            cols <- c("RSID", cols)
        fmtcols <- paste(cols, collapse=",")
        sql <- paste("SELECT ", fmtcols, " FROM ppdata", sep="")
    }
    sql
}

.formatPPDbSelect <- function(raw, keys)
{
    ## no data
    if (!nrow(raw))
        return(data.frame())

    if (missing(keys)) {
        df <- data.frame(raw)
        rownames(df) <- NULL
        df
    } else {
    ## restore key order
        missing <- (!keys %in% as.character(raw$RSID))
        lst <- as.list(rep(NA_character_, length(keys)))
        raw <- raw[!duplicated(raw), ]
        for (i in which(missing == FALSE))
            lst[[i]] <- raw[raw$RSID %in% keys[i], ]

        df <- do.call(rbind, lst)
        df$RSID[is.na(df$RSID)] <- keys[missing]
        rownames(df) <- NULL
        df
    }
}

duplicateRSID <- function(db, keys, ...)
{
    fmtrsid <- .sqlIn(keys)
    sql <- paste("SELECT * FROM duplicates WHERE RSID IN (",
                 fmtrsid, ")", sep="")
    q1 <- dbGetQuery(db$conn, sql)

    fmtgp <- .sqlIn(unique(q1$DUPLICATEGROUP))
    gpsql <- paste("SELECT * FROM duplicates WHERE DUPLICATEGROUP IN (",
                   fmtgp, ")", sep="")
    q2 <- dbGetQuery(db$conn, gpsql)

    matched <- q2[!q2$RSID %in% keys, ]
    matchedlst <- split(matched$RSID, matched$DUPLICATEGROUP)
    names(matchedlst) <- q1$RSID[match(names(matchedlst), q1$DUPLICATEGROUP)]

    missing <- !keys %in% q2$RSID
    if (any(missing)) {
        warning(paste("keys not found in database : ", keys[missing],
                      sep=""))
        missinglst <- list(rep(NA, sum(missing)))
        names(missinglst) <- keys[missing]
        matchedlst <- c(matchedlst, missinglst)
    }

    matchedlst[order(match(names(matchedlst), keys))]
}

