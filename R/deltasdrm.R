# DESCRIPTION =========================================================
# Author: Ashesh Rambachan <asheshr@g.harvard.edu>
#
#  This script contains functions to implement the methods
#  described in Rambachan & Roth (2021) for robust inference
#  in difference-in-differences and event study designs.
#
#  This script contains functions that are used to construct
#  the confidence sets for Delta^{SDRM}(Mbar).

# PRELIMINARIES =======================================================
library(tidyverse)
library(TruncatedNormal)
library(lpSolveAPI)
library(ROI)
library(Matrix)
library(pracma)
library(CVXR)
library(foreach)
library(purrr)

# DELTA^{SDRM}(Mbar) FUNCTIONS ---------------------------------------------
# In this section, we implement helper functions to place testing with
# Delta^{SDRM}(Mbar) into the form needed to use the ARP functions.
.create_A_SDRM <- function(numPrePeriods, numPostPeriods,
                          Mbar = 1, s, max_positive = T, dropZero = T) {
  # This function creates a matrix for the linear constraints that \delta \in Delta^SDRM_{s,.}(Mbar), where . is + if max_positve = T and - if max_positive = F.
  #
  # Inputs:
  #   numPrePeriods = number of pre-periods. This is an element of resultsObjects.
  #   numPostPeriods = number of post-periods. This is an element of resultsObjects.

  # First construct matrix Atilde used in DeltaSD -- (numPrePeriods+numPostPeriods-1) x (numPrePeriods+numPostPeriods+1)
  # Note Atilde is just the positive moments; is not related to Atilde, the rotate matrix, in the paper
  # Note: Atilde initially includes t = 0. We then drop it.
  Atilde = matrix(0, nrow = numPrePeriods+numPostPeriods-1, ncol = numPrePeriods+numPostPeriods+1)
  for (r in 1:(numPrePeriods+numPostPeriods-1)) {
    Atilde[r, r:(r+2)] = c(1, -2, 1)
  }

  # Create a vector to extract the max second dif, which corresponds with the second dif for period s, or minus this if max_positive == F
  v_max_dif <- matrix(0, nrow = 1, ncol = numPrePeriods + numPostPeriods + 1)
  v_max_dif[(numPrePeriods+1+s-2):(numPrePeriods+1+s)] <- c(1,-2, 1)

  if(max_positive == F){
    v_max_dif <- -v_max_dif
  }

  # The bounds for the 2nd dif starting with period t are 1*v_max_dif if t<=0 and M*v_max_dif if t>0
  A_UB <- rbind( pracma::repmat(v_max_dif, n=numPrePeriods-1, m = 1),
                 pracma::repmat(Mbar*v_max_dif, n=numPostPeriods, m = 1))

  # Construct A that imposes |Atilde * delta | <= A_UB * delta
  A = rbind(Atilde - A_UB, -Atilde - A_UB)

  #Remove all-zero rows of the matrix Atilde, corresponding with the constraint (delta_s - delta_s-1) - (delta_s - delta_s-1) <= (delta_s - delta_s-1) - (delta_s - delta_s-1)
  zerorows <- apply(X = A, MARGIN = 1, FUN = function(x) t(x) %*% x) <= 10^-10
  A <- A[!zerorows, ]
  #Remove the period corresponding with t=0
  if (dropZero) {
    A = A[, -(numPrePeriods+1)]
    return(A)
  } else {
    return(A)
  }
}

.create_d_SDRM <- function(numPrePeriods, numPostPeriods, dropZero = T){
  # This function creates a vector for the linear constraints that delt is in Delta^SDRM_{s,.}(Mbar), where . is + if max_positve = T and - if max_positive = F.
  # It implements this using the general characterization of d, NOT the sharp
  # characterization of the identified set.
  #
  # Inputs:
  #   numPrePeriods  = number of pre-periods. This is an element of resultsObjects.
  #   numPostPeriods = number of post-periods. This is an element of resultsObjects.

  A_SDRM = .create_A_SDRM(numPrePeriods = numPrePeriods, numPostPeriods = numPostPeriods,
                         Mbar = 0, s = 0, dropZero = dropZero) # d doesn't depend on Mbar or s
  d = rep(0, NROW(A_SDRM))
  return(d)
}

# DELTA^{SDRM}(Mbar) Identified Set Helper Functions --------------------
.compute_IDset_DeltaSDRM_fixedS <- function(s, Mbar, max_positive,
                                            trueBeta, l_vec, numPrePeriods, numPostPeriods) {
  # This helper function computes the upper and lower bound of the identified set
  # given the event study coefficients, lvec and Mbar. It computes the identified
  # set for a user-specified choice of s and (+), (-). This is used by
  # the function compute_IDset_DeltaSDRM below.

  # Create objective function: Wish to min/max l'delta_post
  fDelta = c(rep(0, numPrePeriods), l_vec)

  # Create A_SDRM, d_SDRM for this choice of s, max_positive
  A_SDRM_s = .create_A_SDRM(numPrePeriods = numPrePeriods, numPostPeriods = numPostPeriods,
                           Mbar = Mbar, s = s, max_positive = max_positive)
  d_SDRM = .create_d_SDRM(numPrePeriods = numPrePeriods, numPostPeriods = numPostPeriods)

  # Create vector for direction of inequalities associated with SDRM
  dir_SDRM = rep("<=", length(d_SDRM))

  # Add equality constraint for pre-period coefficients
  prePeriodEqualityMat = cbind(diag(numPrePeriods),
                               matrix(data = 0, nrow = numPrePeriods, ncol = numPostPeriods))
  A_SDRM_s = rbind(A_SDRM_s, prePeriodEqualityMat)
  d_SDRM = c(d_SDRM, trueBeta[1:numPrePeriods])
  dir_SDRM = c(dir_SDRM, rep("==", NROW(prePeriodEqualityMat)))

  # Specify variables between (-inf, inf)
  bounds = list(lower = list(ind = 1:(numPrePeriods + numPostPeriods), val = rep(-Inf, numPrePeriods+numPostPeriods)),
                upper = list(ind = 1:(numPrePeriods + numPostPeriods), val = rep(Inf, numPrePeriods+numPostPeriods)))

  # Create and solve for max
  results.max = Rglpk::Rglpk_solve_LP(obj = fDelta,
                                      max = TRUE,
                                      mat = A_SDRM_s,
                                      dir = dir_SDRM,
                                      rhs = d_SDRM,
                                      bounds = bounds)

  # Create and solve for min
  results.min = Rglpk::Rglpk_solve_LP(obj = fDelta,
                                      max = FALSE,
                                      mat = A_SDRM_s,
                                      dir = dir_SDRM,
                                      rhs = d_SDRM,
                                      bounds = bounds)

  if (results.max$status != 0 & results.min$status != 0) {
    # If the solver does not return solution, we just return the l_vec'trueBeta.
    id.ub = (t(l_vec) %*% trueBeta[(numPrePeriods+1):(numPrePeriods+numPostPeriods)])
    id.lb = (t(l_vec) %*% trueBeta[(numPrePeriods+1):(numPrePeriods+numPostPeriods)])
  }
  else {
    # Construct upper/lower bound of identified set
    id.ub = (t(l_vec) %*% trueBeta[(numPrePeriods+1):(numPrePeriods+numPostPeriods)]) - results.min$optimum
    id.lb = (t(l_vec) %*% trueBeta[(numPrePeriods+1):(numPrePeriods+numPostPeriods)]) - results.max$optimum
  }
  return(
    tibble(id.lb = id.lb, id.ub = id.ub)
  )
}

.compute_IDset_DeltaSDRM <- function(Mbar, trueBeta, l_vec, numPrePeriods, numPostPeriods) {
  # This function computes the upper and lower bound of the identified set
  # given the event study coefficients, lvec and Mbar.
  #
  # To do so, we construct the identified set at each choice of s, +, -. We
  # then take the union of these intervals.
  #
  # Note: lvec is assumed to be non-negative.
  #
  # Inputs:
  #   Mbar          = smoothness param of Delta^SDRM
  #   trueBeta       = vector of population event study coefficients
  #   l_vec          = vector l defining parameter of interest
  #   numPrePeriods  = number of pre-periods
  #   numPostPeriods = number of post-periods
  #
  # Outputs:
  #   dataframe with columns
  #     id.ub = upper bound of ID set
  #     id.lb = lower bound of ID set

  # Construct identified sets for (+) at each value of s
  min_s = -(numPrePeriods - 2)
  id_bounds_plus = purrr::map_dfr(
    .x = min_s:0,
    .f = ~.compute_IDset_DeltaSDRM_fixedS(s = .x, Mbar = Mbar, max_positive = TRUE,
                                          trueBeta = trueBeta, l_vec = l_vec,
                                          numPrePeriods = numPrePeriods, numPostPeriods = numPostPeriods)
  )
  id_bounds_minus = purrr::map_dfr(
    .x = min_s:0,
    .f = ~.compute_IDset_DeltaSDRM_fixedS(s = .x, Mbar = Mbar, max_positive = FALSE,
                                          trueBeta = trueBeta, l_vec = l_vec,
                                          numPrePeriods = numPrePeriods, numPostPeriods = numPostPeriods)
  )

  # Construct the identified set by taking the max of the upper bound and the min of the lower bound
  id.lb = min(min(id_bounds_plus$id.lb), min(id_bounds_minus$id.lb))
  id.ub = max(max(id_bounds_plus$id.ub), max(id_bounds_minus$id.ub))

  # Return identified set
  return(tibble(
    id.lb = id.lb,
    id.ub = id.ub))
}

# Delta^{SDRM}(Mbar) Inference Helper Functions -------------------------
.computeConditionalCS_DeltaSDRM_fixedS <- function(s, max_positive, Mbar,
                                                   betahat, sigma, numPrePeriods, numPostPeriods, l_vec,
                                                   alpha, hybrid_flag, hybrid_kappa,
                                                   postPeriodMomentsOnly, gridPoints, grid.ub, grid.lb) {
  # This function computes the ARP CI that includes nuisance parameters
  # for Delta^{SDRM}(Mbar) for a fixed s and (+),(-). This functions uses ARP_computeCI for all
  # of its computations. It is used as a helper function in computeConditionalCS_DeltaSDRM below.

  # Check that hybrid_flag equals LF or ARP
  if (hybrid_flag != "LF" & hybrid_flag != "ARP") {
    stop("hybrid_flag must equal 'ARP' or 'FLCI' or 'LF'")
  }

  # Create hybrid_list object
  hybrid_list = list(hybrid_kappa = hybrid_kappa)

  # Create matrix A_SDRM_s, and vector d_SDRM
  A_SDRM_s = .create_A_SDRM(numPrePeriods = numPrePeriods, numPostPeriods = numPostPeriods,
                           Mbar = Mbar, s = s, max_positive = max_positive)
  d_SDRM = .create_d_SDRM(numPrePeriods = numPrePeriods, numPostPeriods = numPostPeriods)

  # If only use post period moments, construct indices for the post period moments only.
  if (postPeriodMomentsOnly & numPostPeriods > 1){
    postPeriodIndices <- (numPrePeriods +1):NCOL(A_SDRM_s)
    postPeriodRows <- which( rowSums( A_SDRM_s[ , postPeriodIndices] != 0 ) > 0 )
    rowsForARP <- postPeriodRows
  } else{
    rowsForARP <- 1:NROW(A_SDRM_s)
  }

  # if there is only one post-period, we use the no-nuisance parameter functions
  if (numPostPeriods == 1) {
    if (hybrid_flag == "LF") {
      # Compute LF CV and store it in hybrid_list
      lf_cv = .compute_least_favorable_cv(X_T = NULL, sigma = A_SDRM_s %*% sigma %*% t(A_SDRM_s), hybrid_kappa = hybrid_kappa)
      hybrid_list$lf_cv = lf_cv
    }
    # Compute confidence set
    CI <- .APR_computeCI_NoNuis(betahat = betahat, sigma = sigma,
                                            A = A_SDRM_s, d = d_SDRM,
                                            numPrePeriods = numPrePeriods, numPostPeriods = numPostPeriods,
                                            l_vec = l_vec, alpha = alpha, returnLength = FALSE,
                                            hybrid_flag = hybrid_flag, hybrid_list = hybrid_list,
                                            grid.ub = grid.ub, grid.lb = grid.lb,
                                            gridPoints = gridPoints)
  } else { # CASE: NumPostPeriods > 1
    # Compute ARP CI for l'beta using Delta^SDRM
    CI = .ARP_computeCI(betahat = betahat, sigma = sigma, numPrePeriods = numPrePeriods,
                                    numPostPeriods = numPostPeriods, A = A_SDRM_s, d = d_SDRM,
                                    l_vec = l_vec, alpha = alpha,
                                    hybrid_flag = hybrid_flag, hybrid_list = hybrid_list,
                                    returnLength = FALSE,
                                    grid.lb = grid.lb, grid.ub = grid.ub,
                                    gridPoints = gridPoints, rowsForARP = rowsForARP)
  }
  return(CI)
}

computeConditionalCS_DeltaSDRM <- function(betahat, sigma, numPrePeriods, numPostPeriods,
                                           l_vec = .basisVector(index = 1, size = numPostPeriods), Mbar = 0,
                                           alpha = 0.05, hybrid_flag = "LF", hybrid_kappa = alpha/10,
                                           returnLength = F, postPeriodMomentsOnly = T,
                                           gridPoints = 10^3, grid.ub, grid.lb) {
  # This function computes the ARP CI that includes nuisance parameters
  # for Delta^{SDRM}(Mbar). This functions uses ARP_computeCI for all
  # of its computations.
  #
  # Inputs:
  #   betahat             = vector of estimated event study coefficients
  #   sigma               = covariance matrix of estimated event study coefficients
  #   numPrePeriods       = number of pre-periods
  #   numPostPeriods      = number of post-periods
  #   l_vec               = vector that defines parameter of interest
  #   Mbar                = tuning parameter for Delta^{SDRM}(Mbar), default Mbar = 0.
  #   alpha               = desired size of CI, default alpha = 0.05
  #   hybrid_flag         = flag for hybrid, default = "LF". Must be either "LF" or "ARP"
  #   hybrid_kappa        = desired size of first-stage hybrid test, default = NULL
  #   returnLength        = returns length of CI only. Otherwise, returns matrix with grid in col 1 and test result in col 2.
  #   numGridPoints       = number of gridpoints to test over, default = 1000
  #   postPeriodMomentsOnly = exclude moments for delta^SDRM that only include pre-period coefs
  #
  #  Outputs:
  #   data_frame containing upper and lower bounds of CI.

  # Create minimal s index for looping.
  min_s = -(numPrePeriods - 2)
  s_indices = min_s:0

  # Construct theta grid by computing id set under parallel trends.
  # The default sets the grid to be equal to [-20*sdTheta, 20*sdTheta]
  sdTheta <- sqrt(t(l_vec) %*% sigma[(numPrePeriods+1):(numPrePeriods+numPostPeriods), (numPrePeriods+1):(numPrePeriods+numPostPeriods)] %*% l_vec)
  if (is.na(grid.ub)) { grid.ub = 20*sdTheta }
  if (is.na(grid.lb)) { grid.lb = -20*sdTheta }

  # Loop over s values for (+), (-), left join the resulting CIs based on the grid
  CIs_SDRM_plus_allS = matrix(0, nrow = gridPoints, ncol = length(s_indices))
  CIs_SDRM_minus_allS = matrix(0, nrow = gridPoints, ncol = length(s_indices))
  for (s_i in 1:length(s_indices)) {
    # Compute CI for s, (+) and bind it to all CI's for (+)
    CI_s_plus = .computeConditionalCS_DeltaSDRM_fixedS(s = s_indices[s_i], max_positive = T, Mbar = Mbar,
                                                       betahat = betahat, sigma = sigma, numPrePeriods = numPrePeriods,
                                                       numPostPeriods = numPostPeriods, l_vec = l_vec,
                                                       alpha = alpha, hybrid_flag = hybrid_flag, hybrid_kappa = hybrid_kappa,
                                                       postPeriodMomentsOnly = postPeriodMomentsOnly,
                                                       gridPoints = gridPoints, grid.ub = grid.ub, grid.lb = grid.lb)
    CIs_SDRM_plus_allS[,s_i] = CI_s_plus$accept

    # Compute CI for s, (-) and bind it to all CI's for (-)
    CI_s_minus = .computeConditionalCS_DeltaSDRM_fixedS(s = s_indices[s_i], max_positive = F, Mbar = Mbar,
                                                        betahat = betahat, sigma = sigma, numPrePeriods = numPrePeriods,
                                                        numPostPeriods = numPostPeriods, l_vec = l_vec,
                                                        alpha = alpha, hybrid_flag = hybrid_flag, hybrid_kappa = hybrid_kappa,
                                                        postPeriodMomentsOnly = postPeriodMomentsOnly,
                                                        gridPoints = gridPoints, grid.ub = grid.ub, grid.lb = grid.lb)
    CIs_SDRM_minus_allS[,s_i] = CI_s_minus$accept
  }
  CIs_SDRM_plus_maxS = apply(CIs_SDRM_plus_allS, MARGIN = 1, FUN = max)
  CIs_SDRM_minus_maxS = apply(CIs_SDRM_minus_allS, MARGIN = 1, FUN = max)

  # Take the max between (+), (-) and Construct grid containing theta points and whether any CI accepted
  CI_SDRM = tibble(grid = seq(grid.lb, grid.ub, length.out = gridPoints),
                   accept = pmax(CIs_SDRM_plus_maxS, CIs_SDRM_minus_maxS))

  # Compute length, else return grid
  if (returnLength == T) {
    gridLength <- 0.5 * ( c(0, diff(CI_SDRM$grid)) + c(diff(CI_SDRM$grid), 0 ) )
    return(sum(CI_SDRM$accept*gridLength))
  } else {
    return(CI_SDRM)
  }
}

