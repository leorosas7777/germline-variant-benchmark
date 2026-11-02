process SAMTOOLS_FAIDX {
    tag "${fasta.name}"
    container 'quay.io/biocontainers/samtools:1.24--h9dcdb79_1@sha256:a130447589651ed09252aa95a5e4f4132942cdb54d835d81a04a9a930d656561'

    input:
    path fasta

    output:
    path "*.fai", emit: fai

    script:
    """
    samtools faidx ${fasta}
    """
}
