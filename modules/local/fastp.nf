process FASTP {
    tag "${meta.id}"
    container 'quay.io/biocontainers/fastp:1.3.6--h43da1c4_0@sha256:cbbe2402b6b6704df470d7d77dcb498eefd5bcd01f4c38be0ec69899e79ac134'
    publishDir "${params.outdir}/fastp", mode: 'copy', pattern: '*.{html,json}'

    input:
    tuple val(meta), path(reads)

    output:
    tuple val(meta), path("*_trimmed_R{1,2}.fastq.gz"), emit: reads
    path "*.fastp.json", emit: json
    path "*.fastp.html", emit: html

    script:
    def prefix = meta.id
    """
    fastp \\
        --in1 ${reads[0]} --in2 ${reads[1]} \\
        --out1 ${prefix}_trimmed_R1.fastq.gz --out2 ${prefix}_trimmed_R2.fastq.gz \\
        --detect_adapter_for_pe \\
        --thread ${task.cpus} \\
        --json ${prefix}.fastp.json --html ${prefix}.fastp.html
    """
}
