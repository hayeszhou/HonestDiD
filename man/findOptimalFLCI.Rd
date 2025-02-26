\name{findOptimalFLCI}
\alias{findOptimalFLCI}
%- Also NEED an '\alias' for EACH other topic documented here.
\title{
Constructs optimal fixed length confidence interval for Delta = Delta^{SD}(M).
}
\description{
  Computes the optimal FLCI for the scalar parameter of interest under Delta = Delta^{SD}(M).
}
\usage{
findOptimalFLCI(betahat, sigma, numPrePeriods, numPostPeriods, l_vec, M = 0 numPoints = 100, alpha = 0.05)
}
%- maybe also 'usage' for other objects documented here.
\arguments{
  \item{betahat}{
  Vector of estimated event study coefficients.
  }
  \item{sigma}{
  Covariance matrix of event study coefficients.
  }
  \item{numPrePeriods}{
  Number of pre-periods.
  }
  \item{numPostPeriods}{
  Number of post-periods.
  }
  \item{l_vec}{
  Vector of length numPostPeriods that describes the scalar parameter of interest, theta = l_vec'tau. Default equals to first basis vector, (1, 0, ..., 0)
  }
  \item{M}{
  Tuning parameter for Delta^{SD}(M) that governs the degree of non-linearity allowed in the violation of parallel trends. Default equals 0
  }
  \item{numPoints}{
  Number of possible values when optimizing the FLCI. Default equals 100.
  }
  \item{alpha}{
  Desired size of the FLCI. Default equals 0.05 (corresponding to 95\% confidence interval)
  }
}
\details{
%%  ~~ If necessary, more details than the description above ~~
}
\value{
  Returns a list containing items
    \item{FLCI}{
    Vector containing lower and upper bounds of optimal FLCI.
    }
    \item{optimalVec}{
    Vector of length numPrePeriods + numPostPeriods that contains the vector of coefficients associated with the optimal FLCI.
    }
    \item{optimalPrePeriodVec}{
    Vector of length numPrePeriods that contains the vector of coefficients for the optimal FLCI that are associated with the pre-period event study coefficients.
    }
    \item{optimalHalfLength}{
    A scalar that equals the half-length of the optimal FLCI.
    }
    \item{M}{
    Value of M at which the FLCI was computed.
    }
    \item{status}{
      Status of optimization.
    }
}
\references{
 Rambachan, Ashesh and Jonathan Roth. "An Honest Approach to Parallel Trends." 2021.
}
\author{
Ashesh Rambachan
}
\note{
%%  ~~further notes~~
}

%% ~Make other sections like Warning with \section{Warning }{....} ~

\seealso{
%% ~~objects to See Also as \code{\link{help}}, ~~~
}
\examples{
}
