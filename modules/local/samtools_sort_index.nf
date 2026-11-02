process SAMTOOLS_SORT_INDEX {
    tag "${meta.id}"
    container 'quay.io/biocontainers/samtools:1.24--h9dcdb79_1@sha256:a130447589651ed09252aa95a5e4f4132942cdb54d835d81a04a9a930d656561'
    publishDir "${params.outdir}/bam", mode: 'copy'

    input:
    tuple val(meta), path(bam)

    output:
    tuple val(meta), path("*.sorted.bam"), path("*.sorted.bam.bai"), emit: bam

    script:
    """
    samtools sort -@ ${task.cpus} -T tmp_sort -o ${meta.id}.markdup.sorted.bam ${bam}
    samtools index ${meta.id}.markdup.sorted.bam
    """
}
