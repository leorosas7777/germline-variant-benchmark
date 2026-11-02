process BWAMEM2_INDEX {
    tag "${fasta.baseName}"
    container 'community.wave.seqera.io/library/bwa-mem2_htslib_samtools:db98f81f55b64113@sha256:5ebd1290d9680195817ce75915b79ae2e608834c017824b7e2bc7b141509b242'

    input:
    path fasta

    output:
    path "bwamem2", emit: index

    script:
    """
    mkdir bwamem2
    bwa-mem2 index -p bwamem2/${fasta.baseName} ${fasta}
    """
}
