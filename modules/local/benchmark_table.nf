process BENCHMARK_TABLE {
    // Local build for now; GHCR image pinned by digest in step 6
    container 'germline-benchmark-report:0.1.0'
    publishDir "${params.outdir}/benchmark", mode: 'copy'

    input:
    tuple val(callers), path(extended)

    output:
    path "benchmark_stratified.csv",     emit: csv
    path "benchmark_stratified_mqc.tsv", emit: mqc

    script:
    def files = extended instanceof List ? extended : [extended]
    def args  = [callers, files].transpose().collect { c, f -> "--extended ${c}:${f}" }.join(' ')
    """
    happy_strat_table.py ${args} --out-prefix benchmark_stratified
    """
}
