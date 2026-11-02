include { FASTP }                         from './modules/local/fastp'
include { BWAMEM2_INDEX }                 from './modules/local/bwamem2_index'
include { BWAMEM2_MEM }                   from './modules/local/bwamem2_mem'
include { MARKDUPLICATES }                from './modules/local/markduplicates'
include { SAMTOOLS_SORT_INDEX }           from './modules/local/samtools_sort_index'
include { SAMTOOLS_FAIDX }                from './modules/local/samtools_faidx'
include { GATK_CREATESEQUENCEDICTIONARY } from './modules/local/gatk_createsequencedictionary'
include { GATK_HAPLOTYPECALLER }          from './modules/local/gatk_haplotypecaller'
include { DEEPVARIANT }                   from './modules/local/deepvariant'
include { BCFTOOLS_NORM }                 from './modules/local/bcftools_norm'

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

    // Reference auxiliary files
    SAMTOOLS_FAIDX(fasta_ch)
    GATK_CREATESEQUENCEDICTIONARY(fasta_ch)
    def regions = params.calling_regions ?: ''

    // Both callers run in parallel on the same BAM
    GATK_HAPLOTYPECALLER(SAMTOOLS_SORT_INDEX.out.bam, fasta_ch, SAMTOOLS_FAIDX.out.fai,
                         GATK_CREATESEQUENCEDICTIONARY.out.dict, regions)
    DEEPVARIANT(SAMTOOLS_SORT_INDEX.out.bam, fasta_ch, SAMTOOLS_FAIDX.out.fai, regions)

    // Tag each VCF with its caller and normalise both with the same process
    vcf_ch = GATK_HAPLOTYPECALLER.out.vcf.map { meta, vcf, tbi -> [meta + [caller: 'gatk'], vcf, tbi] }
        .mix(DEEPVARIANT.out.vcf.map { meta, vcf, tbi -> [meta + [caller: 'deepvariant'], vcf, tbi] })
    BCFTOOLS_NORM(vcf_ch, fasta_ch, SAMTOOLS_FAIDX.out.fai)
}
