process BCFTOOLS_NORM {
    tag "${meta.id}:${meta.caller}"
    container 'quay.io/biocontainers/bcftools:1.24--h118bc1c_4@sha256:186c45de3059dbb1837006c27788284c89d17f8e693e7804624b6cf6ca5caca0'
    publishDir "${params.outdir}/vcf", mode: 'copy'

    input:
    tuple val(meta), path(vcf), path(tbi)
    path fasta
    path fai

    output:
    tuple val(meta), path("*.norm.vcf.gz"), path("*.norm.vcf.gz.tbi"), emit: vcf

    script:
    """
    bcftools norm -m -any -f ${fasta} \\
        -Oz -o ${meta.id}.${meta.caller}.norm.vcf.gz --write-index=tbi \\
        ${vcf}
    """
}
