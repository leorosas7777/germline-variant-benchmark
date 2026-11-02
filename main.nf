include { FASTP }         from './modules/local/fastp'
include { BWAMEM2_INDEX } from './modules/local/bwamem2_index'
include { BWAMEM2_MEM }   from './modules/local/bwamem2_mem'
include { MARKDUPLICATES } from './modules/local/markduplicates'
include { SAMTOOLS_SORT_INDEX } from './modules/local/samtools_sort_index'

workflow {
    reads_ch = channel.of([
        [id: params.sample],
        [file(params.reads_r1, checkIfExists: true), file(params.reads_r2, checkIfExists: true)]
    ])
    fasta_ch = channel.value(file(params.fasta, checkIfExists: true))

    FASTP(reads_ch)
    BWAMEM2_INDEX(fasta_ch)
    BWAMEM2_MEM(FASTP.out.reads, BWAMEM2_INDEX.out.index)
    MARKDUPLICATES(BWAMEM2_MEM.out.bam)
    SAMTOOLS_SORT_INDEX(MARKDUPLICATES.out.bam)


}
