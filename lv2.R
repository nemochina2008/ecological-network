#!/usr/bin/Rscript
library(rootSolve)
library(simecol)
require(plyr)
require(bipartite)

#library(doMC)  # 
#registerDoMC()  # register Multi Cores
#getDoParWorkers()  # get available Cores


#' @title Lotka-Volterra (LV) Equations of Holling type II by Bastolla et al.
#' @param time, time step of simulation
#' @param init, the initial state of the LV system, a vector
#' @param parms parameters passed to LV model
#'        r, the intrinsic growth rate of species, a vector
#'        C, the competition matrix in plants and animals
#'        M, the cooperation matrix between plants and animals
#' @return the derivation
#' @details .
#' @import deSolve
model.lv2 <- function(time, init, parms, ...) {
  r = parms[[1]]  # intrinsic growth rate
  C = parms[[2]]  # the competition matrix
  M = parms[[3]]  # the cooperation matrix
  h = parms[[4]]  # handling time
  N = init  # initial state
  dN <- N * ( r - C %*% N + (M %*% N) / (1 + h * M %*% N) )
  list(c(dN))
}

#' @title the [parms] and [init] of mutualistic lv2 model in soft mean field case
#' @param A, the incident matrix of mutualistic networks which are bipartite
#' @param beta0, the mean value of intraspecies competition,
#'        which is endued according to the condition of feasible equilibrium
#' @param gamma0, the mean value of interspecies cooperation
#' @param alpha0, the intrinsic growth rate
#' @param h0, the Handling time, saturate coefficient.
#' @return a list of [parms] and [init] values of [simObj] class
parms.lv2.softmean <- function(A, alpha0 = 1, beta0 = NULL, gamma0 = 1, h0 = 0) {
  numP = dim(A)[1]; numA = dim(A)[2]
  r = rep(alpha0, numP + numA)  # endue the mean value of intrinsic growth rate
  edges = sum(A > 0)  # the number of edges
  # [beta0] take value of squared root of edge number, to ensure the positive definitive of M
  # and thus ensure the only feasible equilibrium.
  if (is.null(beta0))
    beta0 = ceiling( sqrt(edges) )
  C = diag( rep( beta0, numP + numA ) )  # endue the mean value of intraspecies competition
  M = as.one.mode(A)  # transform to adjacency matrix (function of package [bipartite])
  M[M > 0] = gamma0  # endue the mean value of interspecies cooperation
  h = rep(h0, numP + numA)  # endue the mean value of handling time
  parmsV = list(r, C, M, h)  # the [parms] Value of [simObj] class in package [simecol]
  initV = solve(C - M) %*% r  # the [init] Value, which is close to the steady state.
  list(parmsV = parmsV, initV = initV)
}


#' @title LV2 simulation function
#' @param graphs, a list of matrices which are incidence matrices of graphs.
#' @param alpha0,
#' @param beta0,
#' @param gamma0,
#' @param h0,
#' @param isout, if output the time serials of simulation
#' @param steps and stepwise of simulation
sim.lv2 <- function(graphs, alpha0 = 1, beta0 = NULL, gamma0 = 1, h0 = 0.01, isout = FALSE, steps = 1000, stepwise = 0.01) {
  LV2 <- odeModel(
    main = model.lv2, 
    times = c(from = 0, to = steps * stepwise, by = stepwise),
    solver = 'lsoda')
  
  graphs.num = length(graphs)  # number of graphs
  result.lv2 = llply(1:graphs.num, .parallel = TRUE, function(i) {
    A = graphs[[i]]$B  # get the incidence matrix of some graph
    print(i)
    parms.and.init = parms.lv2.softmean(A, alpha0 = alpha0, beta0 = beta0, gamma0 = gamma0, h0 = h0)
    parms(LV2) = parms.and.init[[1]]
    init(LV2) = as.numeric(parms.and.init[[2]])
    if (any(init(LV2) < 0)) {
      print('Initial state values is less than 0 !!')
      stop('Initial state values is less than 0 !!', init(LV2))
    }
    
    LV2 <- sim(LV2)
    LV2.out = out(LV2)
    
    Nstar = as.numeric(LV2.out[nrow(LV2.out), 2:ncol(LV2.out)]) 
    
    Phi = jacobian.full(y = Nstar, func = model.lv2, parms = parms(LV2))
    if (isout) {
      ret = list(out = LV2.out, Nstar = Nstar, Phi = Phi)
    }
    else {
      ret = list(Nstar = Nstar, Phi = Phi)
    }
    ret
    #ret = as.matrix(LV2.out, ncol = length(LV2.out))
    #out = LV2.out[2:length(LV2.out)]
  })
  result.lv2
}

sim.lv1 <- function(graphs, alpha0 = 1, beta0 = NULL, gamma0 = 1) {
  result.lv1 = llply(graphs, function(graph) {
    graph = graph$B
    edges = sum(graph > 0)
    numP = dim(graph)[1]
    numA = dim(graph)[2]
    if (is.null(beta0)) {
      beta0 = ceiling( sqrt(edges) )
    }
    D = diag(beta0, numP + numA)
    A = as.one.mode(graph)
    A[A > 0 ] = gamma0
    M = D - A  # competition interaction matrix
    #r = runif(numP + numA, min = alpha0, max = alpha0)
    r = rep(alpha0, numP + numA)  # endue the mean value of intrinsic growth rate
    Nstar = solve(M) %*% r  # the feasible fixed point
    Phi = - M * as.vector(Nstar)  # the community matrix
    list(Nstar = Nstar, Phi = Phi)
  })
  result.lv1
}

sim.lv1.2 <- function(graphs, alpha0 = 1, beta0 = 0.1, gamma0 = 1) {
  result.lv1 = llply(graphs, function(graph) {
    graph = graph$B
    edges = sum(graph > 0)
    numP = dim(graph)[1]
    numA = dim(graph)[2]
    D = diag(1, numP + numA)
    D[1:numP, 1:numP] = beta0
    D[(numP+1):(numP+numA), (numP+1):(numP+numA)] = beta0
    diag(D) = 1
    A = as.one.mode(graph)
    A[A > 0 ] = gamma0
    M = D - A  # competition interaction matrix
    #r = runif(numP + numA, min = alpha0, max = alpha0)
    r = rep(alpha0, numP + numA)  # endue the mean value of intrinsic growth rate
    Nstar = solve(M) %*% r  # the feasible fixed point
    Phi = - M * as.vector(Nstar)  # the community matrix
    list(Nstar = Nstar, Phi = Phi)
  })
  result.lv1
}

#sum(sim.lv1.2(graphs=list(graph1), gamma0=0.2, beta0=0.03)[[1]]$Nstar)

# save(result.lv2, file = 'result.lv2.RData')
