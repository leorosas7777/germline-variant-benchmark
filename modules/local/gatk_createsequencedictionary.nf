process GATK_CREATESEQUENCEDICTIONARY {
    tag "${fasta.name}"
    container 'broadinstitute/gatk:4.6.2.0@sha256:71b17ee42d149e8ec112603f5305c873ab60d93949ef8bb62a4fff85427f56fb'

    input:
    path fasta

    output:
    path "*.dict", emit: dict

    script:
    def xmx = Math.max(1, (task.memory.toGiga() * 0.8) as int)
    """
    gatk --java-options "-Xmx${xmx}g" CreateSequenceDictionary -R ${fasta}
    """
}
