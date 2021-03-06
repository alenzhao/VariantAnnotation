### =========================================================================
### readVcf methods 
### =========================================================================

## TabixFile

setMethod(readVcf, c(file="TabixFile", param="ScanVcfParam"), 
    function(file, genome, param, ..., row.names=TRUE)
{
    .readVcf(file, genome, param, row.names=row.names, ...)
})

setMethod(readVcf, c(file="TabixFile", param="GRanges"),
    function(file, genome, param, ..., row.names=TRUE)
{
    .readVcf(file, genome, param=ScanVcfParam(which=param),
             row.names=row.names, ...)
})

setMethod(readVcf, c(file="TabixFile", param="GRangesList"),
    function(file, genome, param, ..., row.names=TRUE)
{
    .readVcf(file, genome, param=ScanVcfParam(which=param), 
             row.names=row.names, ...)
})

setMethod(readVcf, c(file="TabixFile", param="RangesList"),
    function(file, genome, param, ..., row.names=TRUE)
{
    .readVcf(file, genome, param=ScanVcfParam(which=param), 
             row.names=row.names, ...)
})

setMethod(readVcf, c(file="TabixFile", param="missing"), 
    function(file, genome, param, ..., row.names=TRUE)
{
    .readVcf(file, genome, param=ScanVcfParam(), 
             row.names=row.names, ...)
})

## character

setMethod(readVcf, c(file="character", param="ANY"),
    function(file, genome, param, ..., row.names=TRUE)
{
    file <- .checkFile(file)
    .readVcf(file, genome, param, row.names=row.names, ...)
})

setMethod(readVcf, c(file="character", param="missing"),
    function(file, genome, param, ..., row.names=TRUE)
{
    file <- .checkFile(file)
    .readVcf(file, genome, param=ScanVcfParam(), 
             row.names=row.names, ...)
})

.checkFile <- function(x)
{
    if (1L != length(x)) 
        stop("'x' must be character(1)")
    ## Tabix index supplied as 'file'
    if (grepl("\\.tbi$", x))
        return(TabixFile(sub("\\.tbi", "", x)))

    ## Attempt to create TabixFile
    tryCatch(x <- TabixFile(x), error=function(e) return(x))

    x 
}

.readVcf <- function(file, genome, param, row.names, ...)
{
    if (missing(genome))
        genome <- seqinfo(scanVcfHeader(file))
    if (!is(genome, "character") & !is(genome, "Seqinfo"))
        stop("'genome' must be a 'character(1)' or 'Seqinfo' object")
    if (is(genome, "Seqinfo")) {
        if (is(param, "ScanVcfParam"))
            chr <- names(vcfWhich(param))
        else
            chr <- seqlevels(param)
        ## confirm param seqlevels are in supplied Seqinfo 
        if (any(!chr %in% seqnames(genome)))
            stop("'seqnames' in 'vcfWhich(param)' must be present in 'genome'")
    }
    .scanVcfToVCF(scanVcf(file, param=param, row.names=row.names, ...), file, 
                  genome, param)
}

.scanVcfToVCF <- function(vcf, file, genome, param, ...)
{
    hdr <- scanVcfHeader(file)
    if (length(vcf[[1]]$GENO) > 0L)
        colnms <- colnames(vcf[[1]]$GENO[[1]])
    else
        colnms <- NULL
    vcf <- .collapseLists(vcf, param)

    ## rowRanges
    rowRanges <- vcf$rowRanges
    if (length(rowRanges)) {
        if (is(genome, "character")) { 
           if (length(seqinfo(hdr))) {
               merged <- merge(seqinfo(hdr), seqinfo(rowRanges))
               map <- match(names(merged), names(seqinfo(rowRanges)))
               seqinfo(rowRanges, map) <- merged
           }
           genome(rowRanges) <- genome
        } else if (is(genome, "Seqinfo")) {
            if (length(seqinfo(hdr)))
                reference <- merge(seqinfo(hdr), genome)
            else 
                reference <- genome
            merged <- merge(reference, seqinfo(rowRanges))
            map <- match(names(merged), names(seqinfo(rowRanges)))
            seqinfo(rowRanges, map) <- merged 
        }
    }
    values(rowRanges) <- DataFrame(vcf["paramRangeID"])

    ## fixed fields
    fx <- vcf[c("REF", "ALT", "QUAL", "FILTER")]
    fx$ALT <- .formatALT(fx$ALT)
    fixed <- DataFrame(fx[!sapply(fx, is.null)]) 

    ## info 
    info <- .formatInfo(vcf$INFO, info(hdr), length(rowRanges))

    ## colData
    colData <- DataFrame(Samples=seq_along(colnms), row.names=colnms)

    ## geno
    geno <- SimpleList(lapply(vcf$GENO, `dimnames<-`, NULL))

    vcf <- NULL
    VCF(rowRanges=rowRanges, colData=colData, exptData=list(header=hdr),
        fixed=fixed, info=info, geno=geno)
}

## lightweight read functions retrieve a single variable

.geno2geno <- function(lst, ALT=NULL, REF=NULL, GT=NULL)
{
    if (is.null(ALT) && is.null(REF) && is.null(GT)) {
        ALT <- lst$ALT
        REF <- as.character(lst$REF, use.names=FALSE)
        GT <- lst$GENO$GT
    }
    res <- GT
    ## ignore records with GT ".|." 
    if (any(missing <- grepl(".", GT, fixed=TRUE))) 
        GT[missing] <- ".|."
    phasing <- rep("|", length(GT))
    phasing[grepl("/", GT, fixed=TRUE)] <- "/" 

    ## replace
    GTstr <- strsplit(as.vector(GT), "[|,/]")
    if (any(elementNROWS(GTstr) !=2))
        stop("only diploid variants are supported")
    GTmat <- matrix(unlist(GTstr), ncol=2, byrow=TRUE)
    GTA <- suppressWarnings(as.numeric(GTmat[,1]))
    GTB <- suppressWarnings(as.numeric(GTmat[,2]))

    REFcs <- cumsum(elementNROWS(REF))
    ALTcs <- cumsum(elementNROWS(ALT))
    cs <- REFcs + c(0, head(ALTcs, -1)) 
    offset <- rep(cs, ncol(res))
    alleles <- unlist(rbind(REF,ALT), use.names=FALSE)

    alleleA <- alleles[offset + GTA]
    alleleB <- alleles[offset + GTB]
    if (any(missing)) {
        res[!missing] <-  paste0(alleleA[!missing], 
                                 phasing[!missing],
                                 alleleB[!missing])
    } else {
        res[] <- paste0(alleleA, phasing, alleleB)
    }
    res
}

.readLite  <- function(file, var, param, type, ..., row.names)
{
    msg <- NULL
    if (!is.character(var))
        msg <- c(msg, paste0("'", var, "'", " must be a character string"))
    if (length(var) > 1L)
        msg <- c(msg, paste0("'", var, "'", " must be of length 1"))
    if (!is.null(msg))
        stop(msg)

    if (is(param, "ScanVcfParam")) {
        which <- vcfWhich(param)
        samples <- vcfSamples(param)
    } else {
        which <- param 
        samples <- character()
    } 

    if (type == "info")
        param=ScanVcfParam(NA, var, NA, which=which)
    else if (type == "geno") 
        param=ScanVcfParam(NA, NA, var, samples, which=which)
    else if (type == "GT")
        param=ScanVcfParam("ALT", NA, var, samples, which=which)
    scn <- scanVcf(file, param=param, row.names=row.names)
    .collapseLists(scn, param)
}

readInfo <- function(file, x, param=ScanVcfParam(), ..., row.names=TRUE)
{
    lst <- .readLite(file, x, param, "info", row.names=row.names)
    rowRanges <- lst$rowRanges
    res <- .formatInfo(lst$INFO, info(scanVcfHeader(file)), 
                       length(rowRanges))[[1]]
    if (row.names)
        names(res) <- names(rowRanges)
    res 
} 

readGeno <- function(file, x, param=ScanVcfParam(), ..., row.names=TRUE)
{
    lst <- .readLite(file, x, param, "geno", row.names=row.names)
    rowRanges <- lst$rowRanges
    res <- lst$GENO[[1]]
    if (row.names)
        dimnames(res)[[1]] <- names(rowRanges)
    res 
} 

readGT <- function(file, nucleotides=FALSE, param=ScanVcfParam(), ..., 
                   row.names=TRUE)
{
    lst <- .readLite(file, "GT", param, "GT", row.names=row.names)
    if (nucleotides)
        res <- .geno2geno(lst)
    else
        res <- lst$GENO$GT
    rowRanges <- lst$rowRanges
    if (row.names)
        dimnames(res)[[1]] <- names(rowRanges)
    res 
} 
