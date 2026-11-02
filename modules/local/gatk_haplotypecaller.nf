process GATK_HAPLOTYPECALLER {
    tag "${meta.id}"
    container 'broadinstitute/gatk:4.6.2.0@sha256:71b17ee42d149e8ec112603f5305c873ab60d93949ef8bb62a4fff85427f56fb'

    input:
    tuple val(meta), path(bam), path(bai)
    path fasta
    path fai
    path dict
    val regions

    output:
    tuple val(meta), path("*.gatk.vcf.gz"), path("*.gatk.vcf.gz.tbi"), emit: vcf

    script:
    def xmx = Math.max(1, (task.memory.toGiga() * 0.8) as int)
    def region_arg = regions ? "-L ${regions}" : ''
    """
    gatk --java-options "-Xmx${xmx}g" HaplotypeCaller \\
        -R ${fasta} \\
        -I ${bam} \\
        -O ${meta.id}.gatk.vcf.gz \\
        --native-pair-hmm-threads ${task.cpus} \\
        ${region_arg}
    """
}
