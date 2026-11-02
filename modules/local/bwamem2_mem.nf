process BWAMEM2_MEM {
    tag "${meta.id}"
    container 'community.wave.seqera.io/library/bwa-mem2_htslib_samtools:db98f81f55b64113@sha256:5ebd1290d9680195817ce75915b79ae2e608834c017824b7e2bc7b141509b242'

    input:
    tuple val(meta), path(reads)
    path index

    output:
    tuple val(meta), path("*.unsorted.bam"), emit: bam

    script:
    def rg = "@RG\\tID:${meta.id}\\tSM:${meta.id}\\tLB:${meta.id}_lib1\\tPL:ILLUMINA"
    """
    INDEX=\$(find -L ./ -name "*.amb" | sed 's/\\.amb\$//')
    bwa-mem2 mem -t ${task.cpus} -R '${rg}' \$INDEX ${reads[0]} ${reads[1]} \\
        | samtools view -b -o ${meta.id}.unsorted.bam -
    """
}
