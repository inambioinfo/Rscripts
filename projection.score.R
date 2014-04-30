#!/usr/bin/env Rscript

options(stringsAsFactors=FALSE)

##################
# OPTION PARSING #
##################

suppressPackageStartupMessages(library("optparse"))

option_list <- list(

make_option(c("-i", "--input"), default="stdin",
	help="File or stdin [default=%default]"),

make_option(c("-o", "--output"), default="proj.score",
	help="Output file name WITHOUT extension [default=%default]"),

make_option(c("-l", "--log10"), action="store_true", default=FALSE,
	help="Apply the log10 to the whole matrix as pre-processing step [default=%default]"),	

make_option(c("-p", "--pseudocount"), default=0.001,
	help="Pseudocount to add when applying the log [default=%default]"),

make_option(c("-t", "--thresholds"), default="0.1,0.2,0.25,0.3,0.35,0.4,0.5,0.6,0.7,0.8",
	help="A comma-separated list of different variance thresholds (percentages of the max variance) [default=%default]"),

make_option(c("-B", "--iterations"), default=10,
	help="Number of row permutations [default=%default]"),

make_option(c("-S", "--nb_components"), default=3,
	help="Number of principal components you want to compute the projection score [default=%default]"),

make_option(c("-v", "--verbose"), action="store_true", default=FALSE,
	help="if you want more output [default=%default]")
)

parser <- OptionParser(usage = "%prog [options] file", option_list=option_list)
arguments <- parse_args(parser, positional_arguments = TRUE)
opt <- arguments$options
if (opt$verbose) {print(opt)}


suppressPackageStartupMessages(library("ggplot2"))


##############
# BEGIN
##############

# Read options
var_thresholds = strsplit(opt$thresholds, ",")[[1]]
B = opt$iterations
S = opt$nb_components

if (opt$input == "stdin") {
	m = read.table(file("stdin"), h=T)
} else {
	m = read.table(opt$input, h=T)
}

if (opt$log10) {
	m = log10(m + opt$pseudocount)
}


# Compute the variance for each row
variance = apply(m, 1, var)
# Normalize the variance by the maximum variance
variancen = variance/max(variance)

# Function to compute the alpha_2 measure
alpha_2 = function(lambda, S) {
	sqrt(sum(lambda[1:S]^2)/sum(lambda^2))
}

# Initialize the vector of projection scores
proj_scores = array(numeric(0))

# Iterate over different variance thresholds
for (var_t in var_thresholds) {

	# Get the actual submatrix for this variance threshold
	m_t = m[which(variancen>var_t),]

	# Compute the pca on this submatrix
	pca1 = prcomp(t(m_t), scale.=TRUE)

	# Obtain a matrix of lambdas (sdev) for each permutation
	# Rows are the components and columns are the iterations
	lambda = replicate(B, prcomp(apply(m_t, 1, sample), scale.=TRUE)$sdev) 
	# Count how many times the stdev for each component in the permutation is lower than the observed one
	lambda_counts = rowSums(apply(lambda, 2, function(x) pca1$sdev>=x))
	
	# If at least one observed stdev is not higher than 95% of the permutated lambdas 
	# the submatrix does not support S, and the projection score is assigned to NA
	if (sum(lambda_counts[1:S] < 0.05*B) != 0) {
		proj_score = NA
	} else {
		exp_l = mean(apply(lambda, 2, alpha_2, S=S))
		obs_l = alpha_2(pca1$sdev, S)
		proj_score = obs_l - exp_l
	}
	proj_scores = c(proj_scores, proj_score)
}


###############
# OUTPUT
###############


# Plot the projection score as a function of the variance
df = data.frame(var_thresholds, proj_scores)

theme_set(theme_bw(base_size=16))

gp = ggplot(df, aes(x=var_thresholds, y=proj_scores)) + geom_point(size=3) + geom_line()

ggsave(sprintf("%s.pdf", opt$output), h=7, w=7)

selected = names(which(variancen >= var_thresholds[which.max(proj_scores)]))

write.table(selected, sprintf("%s.txt", opt$output), quote=FALSE, col.names=FALSE, row.names=FALSE, sep='\t')

