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
include { HAPPY }                         from './modules/local/happy'
include { BENCHMARK_TABLE }               from './modules/local/benchmark_table'
include { MULTIQC }                       from './modules/local/multiqc'

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

    // Benchmark each normalised VCF against the GIAB truth
    def strat_tsv = file(params.stratifications_tsv, checkIfExists: true)
    HAPPY(BCFTOOLS_NORM.out.vcf,
          file(params.truth_vcf, checkIfExists: true),
          file("${params.truth_vcf}.tbi", checkIfExists: true),
          file(params.truth_bed, checkIfExists: true),
          fasta_ch, SAMTOOLS_FAIDX.out.fai,
          strat_tsv.parent, strat_tsv.name, regions)

    // Per-stratum table with confidence intervals (both callers in one file)
    ext_ch = HAPPY.out.extended
        .map { meta, csv -> [meta.caller, csv] }
        .toList()
        .map { pairs -> [pairs.collect { p -> p[0] }, pairs.collect { p -> p[1] }] }
    BENCHMARK_TABLE(ext_ch)

    // One report with read QC, duplicates, benchmark summaries and the stratified table
    qc_ch = FASTP.out.json
        .mix(MARKDUPLICATES.out.metrics, HAPPY.out.summary.map { _meta, csv -> csv },
             BENCHMARK_TABLE.out.mqc)
        .collect()
    MULTIQC(qc_ch, file("${projectDir}/assets/multiqc_config.yml", checkIfExists: true))
}
