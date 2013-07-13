### =========================================================================
### VRanges: Variants in a GRanges
### -------------------------------------------------------------------------
###

### - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
### Accessors
###

setMethod("ref", "VRanges", function(x) x@ref)
setReplaceMethod("ref", "VRanges", function(x, value) {
  x@ref <- value
  x
})
setMethod("alt", "VRanges", function(x) x@alt)
setReplaceMethod("alt", "VRanges", function(x, value) {
  x@alt <- as(.rleRecycleVector(value, length(x)), "characterOrRle")
  x
})
setMethod("sampleNames", "VRanges", function(object) object@sampleNames)
setReplaceMethod("sampleNames", "VRanges", function(object, value) {
  object@sampleNames <- as(.rleRecycleVector(value, length(object)),
                           "factorOrRle")
  object
})
setMethod("totalDepth", "VRanges", function(x) x@totalDepth)
setMethod("altDepth", "VRanges", function(x) x@altDepth)
setMethod("refDepth", "VRanges", function(x) x@refDepth)
setMethod("softFilterMatrix", "VRanges", function(x) x@softFilterMatrix)
setReplaceMethod("softFilterMatrix", "VRanges", function(x, value) {
  x@softFilterMatrix <- value
  x
})
setMethod("hardFilters", "VRanges", function(x) x@hardFilters)
setReplaceMethod("hardFilters", "VRanges", function(x, value) {
  x@hardFilters <- value
  x
})
setMethod("called", "VRanges", function(x) {
  rowSums(filt(x)) == ncol(filt(x))
})

### - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
### Constructor
###

VRanges <-
  function(seqnames = Rle(), ranges = IRanges(),
           ref = character(), alt = NA_character_,
           totalDepth = NA_integer_, refDepth = NA_integer_,
           altDepth = NA_integer_, ..., sampleNames = NA_character_,
           softFilterMatrix = FilterMatrix(nrow = length(gr), ncol = 0L,
             filterRules = FilterRules()),
           hardFilters = FilterRules())
{
  gr <- GRanges(seqnames, ranges,
                strand = .rleRecycleVector("+", length(ranges)), ...)
  if (length(gr) == 0L && length(ref) == 0L) {
    maxLen <- 0L
  } else {
    maxLen <- max(length(gr), length(ref), length(alt),
                  length(totalDepth), length(refDepth), length(altDepth),
                  length(sampleNames), nrow(softFilterMatrix))
  }
  ref <- as.character(ref)
  alt <- .rleRecycleVector(alt, maxLen)
  alt <- as(alt, "characterOrRle")
  refDepth <- .rleRecycleVector(refDepth, maxLen)
  altDepth <- .rleRecycleVector(altDepth, maxLen)
  totalDepth <- .rleRecycleVector(totalDepth, maxLen)
  softFilterMatrix <- as.matrix(softFilterMatrix)
  mode(softFilterMatrix) <- "logical"
  softFilterMatrix.ind <-
    .rleRecycleVector(seq_len(nrow(softFilterMatrix)), maxLen)
  softFilterMatrix <- softFilterMatrix[softFilterMatrix.ind,,drop=FALSE]
  sampleNames <- .rleRecycleVector(sampleNames, maxLen)
  new("VRanges", gr, ref = ref, alt = alt,
      totalDepth = as(totalDepth, "integerOrRle"),
      refDepth = as(refDepth, "integerOrRle"),
      altDepth = as(altDepth, "integerOrRle"),
      softFilterMatrix = softFilterMatrix,
      sampleNames = as(sampleNames, "factorOrRle"),
      hardFilters = hardFilters)
}

### - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
### Coercion
###

parseFilterStrings <- function(x) {
  x[x == "."] <- NA
  if (all(is.na(x)))
    return(matrix(nrow = length(x), ncol = 0L))
  filterSplit <- strsplit(x, ";", fixed=TRUE)
  filters <- unlist(filterSplit)
  filterNames <- setdiff(unique(filters[!is.na(filters)]), "PASS")
  filterMat <- matrix(TRUE, length(x), length(filterNames),
                      dimnames = list(NULL, filterNames))
  filterMat[cbind(togroup(filterSplit), match(filters, filterNames))] <- FALSE
  filterMat[is.na(x),] <- NA
  filterMat
}

genoToMCol <- function(x) {
  if (length(dim(x)) == 3)
    matrix(x, nrow(x) * ncol(x), dim(x)[3])
  else as.vector(x)
}

setAs("VCF", "VRanges", function(from) {
  from <- expand(from)
  rd <- rowData(from)
  seqnames <- seqnames(rd)
  ranges <- unname(ranges(rd))
  ref <- rd$REF
  alt <- as.character(unlist(rd$ALT))
  alt[!nzchar(alt)] <- NA
  ad <- geno(from)$AD
  if (!is.null(ad)) {
    refDepth <- ad[,,1,drop=FALSE]
    altDepth <- ad[,,2,drop=FALSE]
  } else {
    refDepth <- NA_integer_
    altDepth <- NA_integer_
  }
  totalDepth <- geno(from)$DP
  if (is.null(totalDepth))
    totalDepth <- NA_integer_
  nsamp <- ncol(from)
  sampleNames <- Rle(colnames(from), rep(nrow(from), nsamp))
  meta <- cbind(mcols(rd)["QUAL"], info(from))
  filter <- parseFilterStrings(rd$FILTER)
  if (nsamp > 1L) {
    meta <- meta[rep(seq_len(nrow(meta)), nsamp),,drop=FALSE]
    filter <- filter[rep(seq_len(nrow(filter)), nsamp),,drop=FALSE]
    seqnames <- rep(seqnames, nsamp)
    ranges <- rep(ranges, nsamp)
    alt <- rep(alt, nsamp)
    ref <- rep(ref, nsamp)
  }
  if (!is.null(geno(from)$FT))
    filter <- cbind(filter, parseFilterStrings(as.vector(geno(from)$FT)))
  otherGeno <- geno(from)[setdiff(names(geno(from)), c("AD", "DP", "FT"))]
  if (length(otherGeno) > 0L)
    meta <- DataFrame(meta, lapply(otherGeno, genoToMCol))
  VRanges(seqnames, ranges, ref, alt,
          totalDepth, refDepth, altDepth,
          hardFilters = FilterRules(), sampleNames = sampleNames,
          softFilterMatrix = filter, meta)
})

setAs("VRanges", "VCF", function(from) {
  asVCF(from)
})

makeFORMATheader <- function(x) {
  fixed <-
    DataFrame(row.names = c("AD", "DP", "FT"),
              Number = c(2L, 1L, 1L),
              Type = c("Integer", "Integer", "String"),
              Description =
              c("Allelic depths (number of reads in each observed allele)",
                "Total read depth", "Genotype filters"))
  df <- rbind(fixed, makeINFOheader(x))
  df$Type[df$Type == "Flag"] <- "Integer" # Flags not allowed in FORMAT
  df
}

makeINFOheader <- function(x) {
  df <- mcols(x)
  if (is.null(df))
    df <- new("DataFrame", nrows = length(x))
  rownames(df) <- names(x)
  numberForColumn <- function(xi) {
    if (length(dim(xi)) == 2)
      ncol(xi)
    else if (is.list(xi) || is(xi, "List"))
      "."
    else 1L
  }
  typeForColumn <- function(xi) {
    if (is.integer(xi))
      "Integer"
    else if (is.numeric(xi))
      "Numeric"
    else if (is.logical(xi))
      "Flag"
    else if (is.character(xi) || is.factor(xi)) {
      if (all(nchar(as.character(xi)) == 1L))
        "Character"
      else "String"
    }
  }
  df$Number <- as.character(lapply(x, numberForColumn))
  df$Type <- as.character(lapply(x, typeForColumn))
  if (is.null(df$Description) && nrow(df) > 0L)
    df$Description <- ""
  df
}

makeFILTERheader <- function(x) {
  mat <- softFilterMatrix(x)
  if (!is(mat, "FilterMatrix"))
    return(DataFrame())
  rules <- filterRules(mat)
  df <- mcols(rules)
  if (is.null(df)) {
    df <- new("DataFrame", nrows = length(rules))
  }
  if (is.null(df$Description)) {
    exprs <- as.logical(lapply(rules, is.expression))
    df <- df[exprs,]
    df$Description <- as.character(lapply(rules[exprs], function(expr) {
      gsub("\"", "\\\"", gsub("\\", "\\\\", deparse(expr[[1]]), fixed=TRUE),
           fixed=TRUE)
    }))
  }
  rownames(df) <- names(rules)
  df
}

## If a row contains a FALSE, all FALSE filters are listed;
## otherwise, if a row contains an NA or it is empty, the result is
## NA (.), otherwise PASS.
makeFILTERstrings <- function(x) {
  failed <- which(!x)
  ftNames <- as.character(colnames(x)[col(x)][failed])
  ftStrings <- rep(NA_character_, nrow(x))
  passedRows <- rowSums(x) > 0L
  failedRows <- rowSums(!x, na.rm=TRUE) > 0L
  ftStrings[passedRows & !failedRows] <- "PASS"
  ftStrings[failedRows] <-
    .pasteCollapse(seqsplit(ftNames, row(x)[failed]), ";")
  ftStrings
}

vranges2Vcf <- function(x, info = character(), filter = character(),
                        meta = character())
{
  if (!is.character(info) || any(is.na(info)) ||
      any(!info %in% colnames(mcols(x))))
    stop("'info' must be a character vector naming the mcols to include",
         " in the INFO column of the VCF file; the rest become FORMAT fields.")
  if (!is.character(filter) || any(is.na(filter)) ||
      any(!filter %in% colnames(softFilterMatrix(x))))
    stop("'filter' must be a character vector naming the filters to include",
         " in the FILTER column of the VCF file; the rest are encoded as the FT",
         " FORMAT field.")
  if (!is.character(meta) || any(is.na(meta)) ||
      any(!meta %in% names(metadata(x))))
    stop("'filter' must be a character vector naming metadata(x) elements",
         " to include as metadata in the VCF header.")
  metaStrings <- as.character(sapply(metadata(x)[meta], as.character))
  if (any(elementLengths(metaStrings) != 1L))
    stop("The elements named in 'meta' must be of length 1")
  
  sampleLevels <- levels(sampleNames(x))
  if (length(sampleLevels) > 1) {
    xUniq <- unique(x)
  } else {
    xUniq <- x
  }
  rowData <- xUniq
  mcols(rowData) <- NULL
  rowData <- as(rowData, "GRanges", strict=TRUE)

  colData <- DataFrame(Samples = seq_along(sampleLevels),
                       row.names = sampleLevels)
  
  meta_vector <- c(source = paste("VariantAnnotation",
                     packageVersion("VariantAnnotation")),
                   phasing = "unphased", fileformat = "VCFv4.1",
                   metaStrings)
  meta_header <- DataFrame(Value = meta_vector, row.names = names(meta_vector))
  genoMCols <- setdiff(names(mcols(x)), info)
  header <- VCFHeader(reference = seqlevels(x), samples = sampleLevels,
                      header = DataFrameList(META = meta_header,
                        FORMAT = makeFORMATheader(mcols(x)[genoMCols]),
                        INFO = makeINFOheader(mcols(x)[info]),
                        FILTER = makeFILTERheader(x)))
  exptData <- SimpleList(header = header)

  alt <- as(as.character(alt(xUniq)), "List")
  alt[is.na(alt(xUniq))] <- CharacterList(character()) # empty list elements->'.'
  qual <- xUniq$QUAL
  if (is.null(qual) || !is.numeric(qual))
    qual <- rep.int(NA_real_, length(xUniq))
  filterStrings <- makeFILTERstrings(softFilterMatrix(xUniq)[,filter,drop=FALSE])
  fixed <- DataFrame(REF = DNAStringSet(ref(xUniq)),
                     ALT = alt,
                     QUAL = qual,
                     FILTER = filterStrings)

  if (length(sampleLevels) > 1) {
    samplesToUniq <- tapply(x, sampleNames(x), function(xi) {
      match(xi, xUniq)
    })
    mergeToUniq <- function(v, sampleToUniq, default) {
      ans <- rep(default, length(xUniq))
      ans[sampleToUniq] <- v
      ans
    }
    genoMatrix <- function(v) {
      default <- NA_integer_
      if (length(v) > length(x)) {
        number <- length(v) / length(x)
        v <- split(v, rep(seq_len(length(x)), number))
        default <- list(rep(default, number))
      }
      mapply(mergeToUniq, split(v, as.factor(sampleNames(x))), samplesToUniq,
             MoreArgs = list(default))
    }
  } else {
    genoMatrix <- function(v) {
      if (is.logical(v))
        v <- as.integer(v)
      if (length(v) > length(x))
        v <- split(v, rep(seq_len(length(x)), length(v) / length(x)))
      matrix(v, nrow = length(x), ncol = 1L)
    }
  }
  alleleDepth <- c(refDepth(x), altDepth(x))
  ft <- softFilterMatrix(x)[,setdiff(colnames(softFilterMatrix(x)), filter),
                            drop=FALSE]
  ftStrings <- makeFILTERstrings(ft)
  geno <-
    SimpleList(AD = genoMatrix(alleleDepth),
               DP = genoMatrix(totalDepth(x)),
               FT = genoMatrix(ftStrings))
  if (length(genoMCols) > 0L)
    geno <- c(geno, SimpleList(lapply(mcols(x)[genoMCols], genoMatrix)))
  
  VCF(rowData = rowData, colData = colData, exptData = exptData, fixed = fixed,
      geno = geno, info = mcols(xUniq)[info])
}

setMethod("asVCF", "VRanges", vranges2Vcf)

### - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
### Reading from VCF
###

readVRangesFromVCF <- function(x, ...) {
  as(readVcf(x, ...), "VRanges")
}

readVRanges <- function(x, ...) {
  readVRangesFromVCF(x, ...)
}

### - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
### Writing to VCF (see methods-writeVcf.R)
###

### - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
### Utilities
###

setMethod("duplicated", "VRanges",
          function (x, incomparables = FALSE, fromLast = FALSE, 
                    method = c("auto", "quick", "hash"))
          {
            if (!identical(incomparables, FALSE)) 
              stop("\"duplicated\" method for VRanges objects ", 
                   "only accepts 'incomparables=FALSE'")
            IRanges:::duplicatedIntegerQuads(as.factor(seqnames(x)), 
                                             as.factor(alt(x)),
                                             start(x), width(x),
                                             fromLast = fromLast, 
                                             method = method)
          })

setMethod("match", c("VRanges", "VRanges"),
          function(x, table, nomatch = NA_integer_, incomparables = NULL,
                   method = c("auto", "quick", "hash"), ...)
          {
            if (!isSingleNumberOrNA(nomatch)) 
              stop("'nomatch' must be a single number or NA")
            if (!is.integer(nomatch)) 
              nomatch <- as.integer(nomatch)
            if (!is.null(incomparables))
              stop("\"match\" method for VRanges objects ", 
                   "only accepts 'incomparables=NULL'")
            merge(seqinfo(x), seqinfo(table))
            altLevels <- union(alt(x), alt(table))
            IRanges:::matchIntegerQuads(as.factor(seqnames(x)),
                                        factor(alt(x), altLevels), 
                                        start(x), width(x),
                                        as.factor(seqnames(table)),
                                        factor(alt(table), altLevels),
                                        start(table), width(table),
                                        nomatch = nomatch, method = method)
          })

### - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
### Show
###

.showHardFilters <- function(object) {
  cat(IRanges:::labeledLine("  hardFilters", names(hardFilters(object))))
}

setMethod("show", "VRanges", function(object) {
  callNextMethod()
  .showHardFilters(object)
})

setMethod(GenomicRanges:::extraColumnSlotNames, "VRanges",
          function(x) {
            c("ref", "alt", "totalDepth", "refDepth", "altDepth",
              "sampleNames", "softFilterMatrix")
          })