targets <- c(
  rxode2ll = Sys.getenv("RXODE2LL_VERSION"),
  rxode2 = Sys.getenv("RXODE2_VERSION"),
  nlmixr2est = Sys.getenv("NLMIXR2EST_VERSION"),
  nlmixr2 = Sys.getenv("NLMIXR2_VERSION"),
  mrgsolve = Sys.getenv("MRGSOLVE_VERSION"),
  NonCompart = Sys.getenv("NONCOMPART_VERSION")
)
stopifnot(all(nzchar(targets)))

args <- commandArgs(trailingOnly = TRUE)
if (length(args) == 2L && args[[1L]] == "install") {
  package <- args[[2L]]
  stopifnot(package %in% names(targets))
  if (requireNamespace("bspm", quietly = TRUE)) bspm::disable()
  options(repos = c(CRAN = "https://cloud.r-project.org"))
  message("=== PIN ", package, " -> ", targets[[package]], " ===")
  remotes::install_version(
    package,
    version = targets[[package]],
    repos = "https://cloud.r-project.org",
    dependencies = NA,
    upgrade = "never",
    force = TRUE,
    quiet = FALSE
  )
  # Check installation on disk here; load all engines in a fresh final process.
  stopifnot(as.character(packageVersion(package)) == targets[[package]])
} else if (identical(args, "verify")) {
  stopifnot(as.character(getRversion()) == Sys.getenv("TDM_R_VERSION"))
  for (package in names(targets)) {
    if (!requireNamespace(package, quietly = TRUE)) {
      stop("Package not usable: ", package)
    }
  }
  actual <- vapply(names(targets), function(p) as.character(packageVersion(p)), character(1))
  if (any(actual != targets)) {
    stop("Numerical package version mismatch: ",
         paste(names(targets), actual, targets, sep = "=", collapse = "; "))
  }
  manifest_dir <- "/usr/local/share/tdm-build-base"
  dir.create(manifest_dir, recursive = TRUE, showWarnings = FALSE)
  lock <- data.frame(package = names(targets), version = unname(actual))
  write.table(lock, "/tmp/tdm-numerical-lock.tsv", sep = "\t", quote = FALSE, row.names = FALSE)
  write.table(lock, file.path(manifest_dir, "NUMERICAL_VERSIONS.tsv"),
              sep = "\t", quote = FALSE, row.names = FALSE)
  installed <- installed.packages()
  write.table(installed[, c("Package", "Version", "LibPath"), drop = FALSE],
              file.path(manifest_dir, "R_PACKAGES.tsv"),
              sep = "\t", quote = FALSE, row.names = FALSE)
  message("NUMERICAL PACKAGE LOCK VERIFIED")
} else {
  stop("Usage: numerical-packages.R install <package> | verify")
}
