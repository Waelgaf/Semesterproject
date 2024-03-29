library(rTensor)
library(ggplot2)
library(plotly)
library(Matrix)
library(rMultiNet)


norm_vec <- function(x) sqrt(sum(x^2))
reg_vec <- function(x,delta) min(delta,norm_vec(x))/norm_vec(x)*x

PowerIteration<- function(tnsr, ranks=NULL, type="TWIST", U_0_list, delta1=1000, delta2=1000, max_iter = 75, tol = 1e-04){
  stopifnot(is(tnsr, "Tensor"))
  if (is.null(ranks))
    stop("ranks must be specified")
  if (sum(ranks > tnsr@modes) != 0)
    stop("ranks must be smaller than the corresponding mode")
  if (sum(ranks <= 0) != 0)
    stop("ranks must be positive")
  if(type == "TWIST")
  {
    num_modes <- tnsr@num_modes
    U_list <- U_0_list
    tnsr_norm <- fnorm(tnsr)
    curr_iter <- 1
    converged <- FALSE
    fnorm_resid <- rep(0, max_iter)
  
    pb <- txtProgressBar(min = 0, max = max_iter, style = 3)
    while ((curr_iter < max_iter) && (!converged)) {
      #cat("iteration", curr_iter, "\n")
      #setTxtProgressBar(pb, curr_iter)
      modes <- tnsr@modes
      modes_seq <- 1:num_modes

      ##Regularization
      U_list_reg = U_list
      W_old <- U_list[[3]]
      for(m in modes_seq)
      {
        if(m == 1 | m == 2)
        {
          U_list_reg[[m]] = t(apply(U_list_reg[[m]],1,reg_vec, delta=delta1))
        }
        if(m == 3)
        {
          U_list_reg[[m]] = t(apply(U_list_reg[[m]],1,reg_vec, delta=delta2))
        }
      }

      ##Iterate
      for (m in modes_seq) {
        X <- ttl(tnsr, lapply(U_list_reg[-m], t), ms = modes_seq[-m])
        U_list[[m]] <- svd(rs_unfold(X, m = m)@data, nu = ranks[m])$u
      }

      Z <- ttm(X, mat = t(U_list[[num_modes]]), m = num_modes)
      W_new <- U_list[[3]]
      conv <- norm(W_old-W_new, type = "F")

      if (conv < tol) {
        converged <- TRUE
        #setTxtProgressBar(pb, max_iter)
      }
      else {
        curr_iter <- curr_iter + 1
      }
    }
    close(pb)
    fnorm_resid <- fnorm_resid[fnorm_resid != 0]
    norm_percent <- (1 - (tail(fnorm_resid, 1)/tnsr_norm)) *
      100
    est <- ttl(Z, U_list, ms = 1:num_modes)
    invisible(list(Z = Z, U = U_list, conv = converged, est = est,
                   norm_percent = norm_percent, fnorm_resid = tail(fnorm_resid,
                                                                   1), all_resids = fnorm_resid))
    network_embedding <- U_list[[3]]
    node_embedding <- U_list[[1]]
    return(list(Z, network_embedding, node_embedding, curr_iter))
  }
  if(type == "TUCKER")
  {
    decomp=tucker(arrT,ranks,max_iter = 10000,tol=1e-05)
    nodes_embedding_Our=decomp[["U"]][[1]] #nodes' embedding
    network_embedding=decomp[["U"]][[3]] #layers' embedding
    Z = decomp[["Z"]]
    return(list(Z, network_embedding, node_embedding))
  }

}

layer_comm_2 <- function(W, m){
  l <- dim(W)[1]
  g <- kmeans(W, m)$cluster
  L <- 1:m
  Z <- array(0, c(l, m))
  for(i in 1:l){
    Z[i,] <- c(L== g[i])
  }
  
  return(list(g, Z))
}

layer_comm_2_r <- function(W, m){
  l <- dim(W)[1]
  km <- kmeans(W, m)
  g <- km$cluster
  L <- 1:m
  Z <- array(0, c(l, m))
  for(i in 1:l){
    Z[i,] <- c(L== g[i])
  }
  
  return(list(g, Z, km$tot.withinss))
}

nodes_comm_2 <- function(A, g_lay, K){
  A <- A@data
  n <- dim(A)[2]
  M <- length(K)
  Z <- list()
  g_nodes <- list()
  for(i in 1:M){
    l <- which(g_lay == i)
    Al <- A[,,l]
    Al <- apply(Al,1:2, mean)
    g_nodes[[i]] <- kmeans(Al, K[i])$cluster
    Zi <- array(0, c(n, M))
    L <- 1:M
    for(j in 1:n){
      Zi[j,] <- c(L== g_nodes[[i]][j])
    }
    Z[[i]] <- Zi
  }
  return(list(g_nodes,Z))
  
}

nodes_comm_2_real_data <- function(A, g_lay, K){
  A <- A@data
  n <- dim(A)[2]
  M <- length(K)
  Z <- list()
  s <- 0
  g_nodes <- list()
  for(i in 1:M){
    l <- which(g_lay == i)
    Al <- A[,,l]
    Al <- apply(Al,1:2, mean)
    km <- kmeans(Al, K[i])
    g_nodes[[i]] <- km$cluster
    s <- s + km$tot.withinss
    Zi <- array(0, c(n, M))
    L <- 1:M
    for(j in 1:n){
      Zi[j,] <- c(L== g_nodes[[i]][j])
    }
    Z[[i]] <- Zi
  }
  return(list(g_nodes,Z, s))
}

