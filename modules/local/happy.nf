process HAPPY {
    tag "${meta.id}:${meta.caller}"
    container 'community.wave.seqera.io/library/hap.py_rtg-tools:5de06c00cb4eb89f@sha256:b694b49a4d505167ad9d67a6934394bd5d81f4c44cc72afbdd4f8ee16dcc9411'
    publishDir "${params.outdir}/benchmark", mode: 'copy'

    input:
    tuple val(meta), path(query_vcf), path(query_tbi)
    path truth_vcf
    path truth_tbi
    path truth_bed
    path fasta
    path fai
    path strat_dir
    val strat_tsv
    val regions

    output:
    tuple val(meta), path("*.summary.csv"),     emit: summary
    tuple val(meta), path("*.extended.csv"),    emit: extended
    tuple val(meta), path("*.metrics.json.gz"), emit: metrics
    tuple val(meta), path("*.runinfo.json"),    emit: runinfo
    tuple val(meta), path("*.vcf.gz"), path("*.vcf.gz.tbi"), emit: vcf

    script:
    def loc = regions ? "-l ${regions}" : ''
    """
    hap.py \\
        ${truth_vcf} \\
        ${query_vcf} \\
        -f ${truth_bed} \\
        -r ${fasta} \\
        --engine vcfeval \\
        --gender male \\
        --stratification ${strat_dir}/${strat_tsv} \\
        ${loc} \\
        --threads ${task.cpus} \\
        -o ${meta.id}.${meta.caller}
    """
}
