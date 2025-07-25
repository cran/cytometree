#' Binary tree algorithm for cytometry data analysis.
#'
#'@param M A matrix of size n x p containing cytometry measures
#'of n cells on p markers.
#'
#'@param minleaf An integer indicating the minimum number of cells
#'per population. Default is \code{1}.
#'
#'@param t A real positive-or-null number used for comparison with
#'the normalized AIC computed at each node of the tree.
#'A higher value limits the height of the tree.
#'
#'@param verbose A logical controlling if a text progress bar is displayed 
#'during the execution of the algorithm. By default is TRUE.
#'
#'@param force_first_markers a vector of index to split the data on first.
#'This argument is used in the semi-supervised setting, forcing the algorithm to consider 
#'those markers first, in the order they appear in this \code{force_first_markers} vector, 
#'and forcing the split at every node. Default is \code{NULL}, in which case
#'the clustering algorithm is unsupervised.
#'
#'@returns An object of class 'CytomeTree' providing a partitioning
#'of the set of n cells.
#'\item{\code{annotation}}{ A \code{data.frame} containing the annotation of each 
#'cell population underlying the tree pattern.}
#'\item{\code{labels}}{ The partitioning of the set of n cells.}
#'\item{\code{M}}{ The input matrix.}
#'\item{\code{mark_tree}}{ A two level list containing markers used
#'for node splitting.}
#'\item{pl_list}{ A list of density estimations for each node used in 
#'\code{\link{plot_nodes}} for visualization purposes}
#'
#'@details The algorithm is based on the construction of a binary tree,
#'the nodes of which are subpopulations of cells. At each node,
#'observed cells and markers are modeled by both a family of normal
#'distributions and a family of bi-modal normal mixture distributions.
#'Splitting is done according to a normalized difference of AIC between
#'the two families.
#'@author Chariff Alkhassim, Boris Hejblum
#'
#'@importFrom methods is
#'
#'@export
#'
#'@examples
#'head(DLBCL)
#'
#'# number of cell event
#'N <- nrow(DLBCL)
#'
#'# Cell events
#'cellevents <- DLBCL[, c("FL1", "FL2", "FL4")]
#'
#'
#'# Manual partitioning of the set N (from FlowCAP-I)
#'manual_labels <- DLBCL[, "label"]
#'
#'
#'# Build the binary tree
#'Tree <- CytomeTree(cellevents, minleaf = 1, t=.1)
#'
#'
#'# Retreive the resulting partition of the set N
#'Tree_Partition <- Tree$labels
#'
#'
#'# Plot node distributions
#'par(mfrow=c(1, 2))
#'plot_nodes(Tree)
#'
#'# Choose a node to plot
#'plot_nodes(Tree,"FL4.1")
#'
#'# Plot a graph of the tree
#'par(mfrow=c(1,1))
#'plot_graph(Tree,edge.arrow.size=.3, Vcex =.5, vertex.size = 30)
#'
#'# Run the annotation algorithm
#'Annot <- Annotation(Tree,plot=FALSE)
#'Annot$combinations
#'
#'
#'# Compare to the annotation gotten from the tree
#'Tree$annotation
#'
#'
#'# Example of sought phenotypes
#'# Variable in which sought phenotypes can be entered in the form of matrices.
#'phenotypes <- list()
#'
#'# Sought phenotypes:
#'## FL2+ FL4-.
#'phenotypes[[1]] <- rbind(c("FL2", 1), c("FL4", 0))
#'
#'## FL2- FL4+.
#'phenotypes[[2]] <- rbind(c("FL2", 0), c("FL4", 1))
#'
#'## FL2+ FL4+.
#'phenotypes[[3]] <- rbind(c("FL2", 1), c("FL4", 1))
#'
#'# Retreive cell populations found using Annotation.
#'PhenoInfos <- RetrievePops(Annot, phenotypes)
#'PhenoInfos$phenotypesinfo
#'
#'# F-measure ignoring cells labeled 0 as in FlowCAP-I.
#'
#'# Use FmeasureC() in any other case.
#'FmeasureC_no0(ref=manual_labels, pred=Tree_Partition)
#'
#'
#'
#'if(interactive()){
#'
#'# Scatterplots.
#'library(ggplot2)
#'
#'# Ignoring cells labeled 0 as in FlowCAP-I.
#'rm_zeros <- which(!manual_labels)
#'
#'# Building the data frame to scatter plot the data.
#'FL1 <- cellevents[-c(rm_zeros),"FL1"]
#'FL2 <- cellevents[-c(rm_zeros),"FL2"]
#'FL4 <- cellevents[-c(rm_zeros),"FL4"]
#'n <- length(FL1)
#'Labels <- c(manual_labels[-c(rm_zeros)]%%2+1, Tree_Partition[-c(rm_zeros)])
#'Labels <- as.factor(Labels)
#'method <- as.factor(c(rep("FlowCap-I",n),rep("CytomeTree",n)))
#'
#'scatter_df <- data.frame("FL2" = FL2, "FL4" = FL4, "labels" = Labels, "method" = method)
#'p <- ggplot2::ggplot(scatter_df,  ggplot2::aes_string(x = "FL2", y = "FL4", colour = "labels")) +
#'  ggplot2::geom_point(alpha = 1,cex = 1) +
#'  ggplot2::scale_colour_manual(values = c("green","red","blue")) +
#'  ggplot2::facet_wrap(~ method) +
#'  ggplot2::theme_bw() +
#'  ggplot2::theme(legend.position="bottom")
#'p
#'
#'}

CytomeTree <- function(M, minleaf = 1, t = .1, verbose = TRUE, force_first_markers = NULL){
  if(methods::is(M, "data.frame")){
    M <- as.matrix(M)
  }
  if(!methods::is(M, "matrix") | mode(M) != "numeric"){
    stop("M should be a numeric matrix")
  }
  n <- nrow(M)
  if(minleaf >= n)
  {
    stop("minleaf is superior to n.")
  }
  p <- ncol(M)
  if(p > n){
    stop("p is superior to n.")
  }
  if(any(is.na(M)))
  {
    stop("M contains NAs.")
  }
  
  if(is.null(colnames(M))){
    colnames(M) <- paste0(rep("M",p), 1:p)
  }
  
  if(!is.null(force_first_markers)){
    if(any(!(force_first_markers %in% colnames(M)))){
      cat("'force_first_markers' are not all in M colnames:")
      colnames(M)
      stop()
    }
  }
  
  BT <- BinaryTree(M, floor(minleaf), t, verbose, force_first_markers)
  annotation <- TreeAnnot(BT$labels, BT$combinations)
  Tree <- list("M" = M, "labels" = BT$labels,
               "pl_list"= BT$pl_list, "t"= t,
               "mark_tree" = BT$mark_tree,
               "annotation" = annotation)
  class(Tree) <- "CytomeTree"
  return(Tree)
}
