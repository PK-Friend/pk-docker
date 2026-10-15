# Engineering smoke test with a synthetic one-compartment model.
# This checks installation, compilation and basic solver behavior, not clinical validity.
targets <- c(
  rxode2ll = "2.0.16",
  rxode2 = "5.1.7.1",
  nlmixr2est = "7.1.0",
  nlmixr2 = "7.0.1",
  mrgsolve = "2.0.1",
  NonCompart = "0.8.4"
)
check <- function(ok, label) {
  if (!isTRUE(ok)) stop("FAILED: ", label)
  message("PASS: ", label)
}
near <- function(actual, expected, tolerance = 1e-5) {
  length(actual) == length(expected) &&
    all(is.finite(actual)) && max(abs(actual - expected)) < tolerance
}

check(as.character(getRversion()) == "4.6.1", "R version")
for (package in c(names(targets), "plumber", "jsonlite", "tidyverse", "logger", "tictoc")) {
  check(requireNamespace(package, quietly = TRUE), paste(package, "namespace loads"))
}
actual <- vapply(names(targets), function(p) as.character(packageVersion(p)), character(1))
check(identical(actual, targets), "numerical package versions")
check(all(nzchar(Sys.which(c("g++", "gfortran", "make", "curl-config")))),
      "model toolchain and curl-config available")
manifest_dir <- "/usr/local/share/tdm-build-base"
check(all(file.exists(file.path(manifest_dir, c(
  "NUMERICAL_VERSIONS.tsv", "R_PACKAGES.tsv", "DPKG_PACKAGES.tsv"
)))), "package inventories available")
lock <- read.delim("/tmp/tdm-numerical-lock.tsv", stringsAsFactors = FALSE)
check(identical(setNames(lock$version, lock$package), targets), "consumer package manifest")

work_dir <- tempfile("tdm-base-smoke-")
dir.create(work_dir)
setwd(work_dir)
times <- c(0.5, 1, 2, 4, 8)
expected <- 100 / 10 * exp(-1 / 10 * times)

# Compiling this synthetic C++ model verifies the toolchain retained in the base image.
cpp_model <- mrgsolve::mcode("tdm_base_smoke", '
$PARAM CL = 1, V = 10
$CMT CENT
$ODE dxdt_CENT = -(CL / V) * CENT;
$TABLE double cp = CENT / V;
$CAPTURE cp
', soloc = work_dir)
cpp_result <- as.data.frame(mrgsolve::mrgsim(
  mrgsolve::ev(cpp_model, amt = 100, cmt = 1),
  tgrid = times,
  obsonly = TRUE
))
check(near(cpp_result$cp, expected), "mrgsolve matches closed-form concentration")

synthetic_model <- function() {
  ini({
    tcl <- 0
    tv <- log(10)
    eta.cl ~ 0.1
    add.err <- 0.1
  })
  model({
    cl <- exp(tcl + eta.cl)
    v <- exp(tv)
    d/dt(CENT) = -(cl / v) * CENT
    cp = CENT / v
    cp ~ add(add.err)
  })
}
events <- data.frame(
  ID = 1,
  TIME = c(0, times),
  EVID = c(1, rep(0, length(times))),
  AMT = c(100, rep(0, length(times))),
  CMT = 1,
  DV = c(NA, 100 / 10 * exp(-1.2 / 10 * times))
)
ui <- nlmixr2est::nlmixr2(synthetic_model)
rx_result <- as.data.frame(rxode2::rxSolve(
  ui,
  events = events,
  params = setNames(rep(0, length(ui$eta)), ui$eta),
  omega = NA,
  sigma = NA
))
check(near(rx_result$cp, expected), "rxode2 matches closed-form concentration")

fit <- as.data.frame(nlmixr2est::nlmixr2(
  synthetic_model, events, est = "posthoc", control = list(print = 0)
))
check(nrow(fit) == length(times) && "IPRED" %in% names(fit) &&
        all(is.finite(fit$IPRED) & fit$IPRED > 0),
      "nlmixr2 posthoc produces finite individual predictions")
observed <- events$DV[events$EVID == 0]
check(mean((fit$IPRED - observed)^2) < mean((expected - observed)^2),
      "posthoc improves fit to synthetic observations")

message("TDM build base smoke checks passed")
