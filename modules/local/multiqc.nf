process MULTIQC {
    container 'quay.io/biocontainers/multiqc:1.35--pyhdfd78af_2@sha256:ceace1ca5329886d92600c225d34a523020c163b1599403e44c8d895d2dfb2a2'
    publishDir "${params.outdir}/multiqc", mode: 'copy'

    input:
    path qc_files
    path config

    output:
    path "multiqc_report.html", emit: report
    path "*_data",              emit: data

    script:
    """
    multiqc --force --config ${config} --filename multiqc_report.html .
    """
}
