phate <- function(data, t = 20, k = 5, alpha = 10, ndim = 2,
                  pca.method = 'random', npca = 100, mds.method = 'cmds',
                  dist.method = 'euclidean', mds.dist.method = 'euclidean', diff.op = NA,
                  diff.op.t = NA) {
  # Runs PHATE on an input data matrix
  #
  # Args:
  #   data: Data matrix. Must have cells on the rows and genes on the columns
  #   t: Diffusion time scale. Default is 20.
  #   k: k for the adaptive kernel bandwidth. Default is 5.
  #   alpha: The alpha parameter in the exponent of the kernel function.
  #          Determines the kernel decay rate. Default is 10.
  #   ndim: The The number of desired PHATE dimensions in the output Y. 2 or 3
  #         is best for visualization. A higher number can be used for
  #         running other analyses on the PHATE dimensions.
  #   pca.method: The desired method for implementing pca for preprocessing the
  #               data. Options include 'svd', 'random', and 'none' (no pca).
  #               Default is 'random'.
  #   npca: The number of PCA components for preprocessing the data. Default
  #         is 100.
  #   mds.method: Method for implementing MDS. Choices are 'cmds', 'mmds',
  #               and 'nmmds'. Default is 'cmds'.
  #   dist.method: The desired distance function for calculating pairwise
  #                distances on the data. Default is 'euclidean'.
  #   mds.dist.method:  The desired distance function for MDS. Choices are 'euclidean'
  #                     and 'cosine'. Default is 'euclidean'.
  #   diff.op:  If the diffusion operator has been computed on a prior run with the
  #             desired parameters, then this option can be used to directly input the
  #             diffusion operator to save on computational time. Default is NA.
  #   diff.op.t:  Same as for 'DiffOp', if the powered diffusion operator has been
  #               computed on a prior run with the desired parameters then this
  #               option can be used to directly input the diffusion operator to
  #               save on computational time. Default is NA.
  #
  # Returns:
  #   Y: The PHATE embedding.
  #   diff.op: The diffusion operator which can be used as optional input with
  #           another run.
  #   diff.op.t: diff.op^t
  eps <- 2.220446e-16
  if (is.na(diff.op) & is.na(diff.op.t)) {
    M <- svdpca(data, npca, pca.method)
    pdx <- as.matrix(dist(M, dist.method, diag = TRUE, upper = TRUE))
    knn.neighbors <- sapply(1:(dim(pdx)[1]), FastKNN::k.nearest.neighbors, distance_matrix = pdx, k = k)
    knn.eps <- sapply(1:dim(M)[1], function(i) pdx[i, knn.neighbors[1, i]])
    pdx <- pdx / knn.eps
    g.kernel <- exp(-pdx ^ alpha)
    g.kernel <- g.kernel + t(g.kernel)
    diff.deg <- diag(colSums(g.kernel)) # degrees
    diff.op <- solve(diff.deg) %*% g.kernel
    rm(g.kernel, pdx, diff.deg, knn.neighbors, knn.eps)
  }

  if (is.na(diff.op.t)) {
    diff.op.t <- expm::`%^%`(diff.op, t)
  }

  X <- diff.op.t
  X[X <= eps] = eps
  X <- -log(X)

  print(paste('MDS distance method:', mds.dist.method))
  if (mds.dist.method == 'euclidean') {
    X <- svdpca(X, npca, pca.method)
    X.dist <- as.matrix(dist(X, mds.dist.method, diag = TRUE, upper = TRUE))
  } else if (mds.dist.method == "cosine") {
    n <- dim(X)[1]
    X.pairs <- expand.grid(i=1:n, j=1:n)
    X.dist <- matrix(apply(X.pairs, 1, cos.dissim, x = X), n, n)
  }
  print(paste('MDS method:', mds.method))
  embedding <- switch(mds.method, cmds = cmdscale(X, k = ndim),
                      mmds = smacof::mds(X.dist, ndim = ndim, init = "random", itmax = 3000)$conf,
                      nmmds = smacof::mds(X.dist, ndim = ndim, init = "torgerson", type = "ordinal", itmax = 3000)$conf)
  return(list("embedding" = embedding, "diff.op" = diff.op, "diff.op.t" = diff.op.t))
}