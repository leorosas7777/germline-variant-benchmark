process MARKDUPLICATES {
    tag "${meta.id}"
    container 'broadinstitute/gatk:4.6.2.0@sha256:71b17ee42d149e8ec112603f5305c873ab60d93949ef8bb62a4fff85427f56fb'
    publishDir "${params.outdir}/markduplicates", mode: 'copy', pattern: '*.metrics.txt'

    input:
    tuple val(meta), path(bam)

    output:
    tuple val(meta), path("*.markdup.bam"), emit: bam
    path "*.markdup.metrics.txt", emit: metrics

    script:
    def heap = (task.memory.toMega() * 0.8).intValue()
    """
    gatk --java-options "-Xmx${heap}m" MarkDuplicates \\
        --INPUT ${bam} \\
        --OUTPUT ${meta.id}.markdup.bam \\
        --METRICS_FILE ${meta.id}.markdup.metrics.txt \\
        --ASSUME_SORT_ORDER queryname \\
        --TMP_DIR .
    """
}
